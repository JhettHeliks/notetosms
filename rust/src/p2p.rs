use anyhow::{anyhow, Context, Result};
use base64::{
    engine::general_purpose::{STANDARD as BASE64, URL_SAFE_NO_PAD as BASE64_URL},
    Engine,
};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Key, Nonce,
};
use iroh_net::endpoint::{get_remote_node_id, Connection, Endpoint, Incoming, RecvStream, SendStream};
use iroh_net::key::{NodeId, SecretKey};
use iroh_net::relay::RelayMode;
use iroh_net::NodeAddr;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{broadcast, Mutex, RwLock};

pub use crate::p2p_protocol::{EncryptedNotePayload, RoomEvent, RoomShareTicket, SyncPacket};
use crate::storage::NoteItem;

pub const P2P_ALPN: &[u8] = b"notetosms/p2p/v2";

/// Legacy invitation ticket for joining a shared room (backward compatibility)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomInvitePayload {
    pub room_id: String,
    pub room_name: String,
    pub shared_key_b64: String, // 32-byte room key encoded in base64
    pub host_node_id: String,
    pub relay_url: Option<String>,
    pub direct_addrs: Vec<String>,
}

/// Legacy P2P Event for backward compatibility
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct P2pEvent {
    pub event_type: String, // "node_started", "peer_connected", "peer_disconnected", "note_received", "typing", "sync_error"
    pub peer_id: Option<String>,
    pub room_id: Option<String>,
    pub note_id: Option<String>,
    pub content: Option<String>,
    pub author_id: Option<String>,
    pub timestamp_ms: Option<i64>,
    pub is_todo: Option<bool>,
    pub is_completed: Option<bool>,
    pub message: Option<String>,
}

impl P2pEvent {
    pub fn node_started(node_id: String) -> Self {
        Self {
            event_type: "node_started".into(),
            peer_id: Some(node_id),
            room_id: None,
            note_id: None,
            content: None,
            author_id: None,
            timestamp_ms: None,
            is_todo: None,
            is_completed: None,
            message: None,
        }
    }

    pub fn peer_connected(peer_id: String, room_id: String) -> Self {
        Self {
            event_type: "peer_connected".into(),
            peer_id: Some(peer_id),
            room_id: Some(room_id),
            note_id: None,
            content: None,
            author_id: None,
            timestamp_ms: None,
            is_todo: None,
            is_completed: None,
            message: None,
        }
    }

    pub fn peer_disconnected(peer_id: String, room_id: String) -> Self {
        Self {
            event_type: "peer_disconnected".into(),
            peer_id: Some(peer_id),
            room_id: Some(room_id),
            note_id: None,
            content: None,
            author_id: None,
            timestamp_ms: None,
            is_todo: None,
            is_completed: None,
            message: None,
        }
    }

    pub fn note_received(
        note_id: String,
        room_id: String,
        content: String,
        author_id: String,
        timestamp_ms: i64,
        is_todo: bool,
        is_completed: bool,
    ) -> Self {
        Self {
            event_type: "note_received".into(),
            peer_id: None,
            room_id: Some(room_id),
            note_id: Some(note_id),
            content: Some(content),
            author_id: Some(author_id),
            timestamp_ms: Some(timestamp_ms),
            is_todo: Some(is_todo),
            is_completed: Some(is_completed),
            message: None,
        }
    }

    pub fn typing(peer_id: String, room_id: String) -> Self {
        Self {
            event_type: "typing".into(),
            peer_id: Some(peer_id),
            room_id: Some(room_id),
            note_id: None,
            content: None,
            author_id: None,
            timestamp_ms: None,
            is_todo: None,
            is_completed: None,
            message: None,
        }
    }

    pub fn sync_error(message: String) -> Self {
        Self {
            event_type: "sync_error".into(),
            peer_id: None,
            room_id: None,
            note_id: None,
            content: None,
            author_id: None,
            timestamp_ms: None,
            is_todo: None,
            is_completed: None,
            message: Some(message),
        }
    }
}

/// Active connected peer metadata
#[derive(Clone)]
pub struct ActivePeer {
    pub peer_id: String,
    pub display_name: String,
    pub connection: Connection,
    pub last_seen: Arc<RwLock<Instant>>,
}

#[derive(Clone)]
pub struct P2pNode {
    pub secret_key: SecretKey,
    pub endpoint: Arc<Endpoint>,
    pub display_name: Arc<RwLock<String>>,
    pub active_peers: Arc<RwLock<HashMap<String, Vec<ActivePeer>>>>,
    pub known_members: Arc<RwLock<HashMap<String, HashMap<String, String>>>>, // room_id -> (peer_id -> display_name)
    pub shared_rooms: Arc<RwLock<HashMap<String, [u8; 32]>>>,
    pub legacy_event_sender: broadcast::Sender<P2pEvent>,
    pub room_event_senders: Arc<RwLock<HashMap<String, broadcast::Sender<RoomEvent>>>>,
}

static P2P_INSTANCE: Mutex<Option<P2pNode>> = Mutex::const_new(None);

impl P2pNode {
    /// Initialize or get the global P2P node
    pub async fn get_or_init() -> Result<P2pNode> {
        let mut guard = P2P_INSTANCE.lock().await;
        if let Some(ref node) = *guard {
            return Ok(node.clone());
        }

        let secret_key = SecretKey::generate();

        let endpoint = Endpoint::builder()
            .secret_key(secret_key.clone())
            .relay_mode(RelayMode::Default)
            .alpns(vec![P2P_ALPN.to_vec(), b"notetosms/p2p/v1".to_vec()])
            .bind()
            .await
            .context("Failed to bind iroh endpoint")?;

        let (legacy_event_sender, _) = broadcast::channel(256);

        let node = P2pNode {
            secret_key,
            endpoint: Arc::new(endpoint),
            display_name: Arc::new(RwLock::new("NoteToSMS Device".to_string())),
            active_peers: Arc::new(RwLock::new(HashMap::new())),
            known_members: Arc::new(RwLock::new(HashMap::new())),
            shared_rooms: Arc::new(RwLock::new(HashMap::new())),
            legacy_event_sender,
            room_event_senders: Arc::new(RwLock::new(HashMap::new())),
        };

        // Spawn listener loop
        let listener_node = node.clone();
        crate::get_runtime().spawn(async move {
            listener_node.run_listener_loop().await;
        });

        // Spawn background heartbeat and presence sweep loop (runs every 5 seconds)
        let heartbeat_node = node.clone();
        crate::get_runtime().spawn(async move {
            heartbeat_node.run_heartbeat_loop().await;
        });

        let node_id = node.node_id().to_string();
        let _ = node.legacy_event_sender.send(P2pEvent::node_started(node_id));

        *guard = Some(node.clone());
        Ok(node)
    }

    pub fn node_id(&self) -> NodeId {
        self.endpoint.node_id()
    }

    pub async fn set_display_name(&self, name: String) {
        let mut n = self.display_name.write().await;
        *n = name;
    }

    pub async fn get_display_name(&self) -> String {
        self.display_name.read().await.clone()
    }

    pub fn subscribe_legacy_events(&self) -> broadcast::Receiver<P2pEvent> {
        self.legacy_event_sender.subscribe()
    }

    pub async fn subscribe_room_events(&self, room_id: &str) -> broadcast::Receiver<RoomEvent> {
        let mut senders = self.room_event_senders.write().await;
        let sender = senders.entry(room_id.to_string()).or_insert_with(|| {
            let (tx, _) = broadcast::channel(256);
            tx
        });
        sender.subscribe()
    }

    pub async fn emit_room_event(&self, room_id: &str, event: RoomEvent) {
        let senders = self.room_event_senders.read().await;
        if let Some(sender) = senders.get(room_id) {
            let _ = sender.send(event);
        }
    }

    pub async fn get_peer_counts(&self, room_id: &str) -> (i32, i32) {
        let active_count = {
            let peers = self.active_peers.read().await;
            peers.get(room_id).map(|p| p.len() as i32).unwrap_or(0) + 1 // +1 for local self
        };

        let total_count = {
            let known = self.known_members.read().await;
            known.get(room_id).map(|m| m.len() as i32).unwrap_or(0).max(active_count)
        };

        (total_count, active_count)
    }

    /// Background listener loop on Device A: continuously accepts incoming connections
    async fn run_listener_loop(&self) {
        while let Some(incoming) = self.endpoint.accept().await {
            let node = self.clone();
            crate::get_runtime().spawn(async move {
                if let Err(e) = node.handle_incoming_connection(incoming).await {
                    debug_print(&format!("Incoming connection error: {:#}", e));
                }
            });
        }
    }

    async fn handle_incoming_connection(&self, incoming: Incoming) -> Result<()> {
        let connecting = incoming.accept().context("Failed to accept incoming QUIC connection")?;
        let connection: Connection = connecting.await.context("Failed to establish QUIC connection")?;
        let peer_node_id = get_remote_node_id(&connection)?.to_string();

        let (mut send, mut recv) = connection.accept_bi().await.context("Failed to accept bi-directional stream")?;

        let packet = read_packet(&mut recv).await?;
        match packet {
            SyncPacket::Handshake {
                peer_node_id: remote_id,
                room_id,
                display_name: remote_display_name,
            } => {
                let has_room = {
                    let rooms = self.shared_rooms.read().await;
                    rooms.contains_key(&room_id)
                };

                let my_display_name = self.get_display_name().await;

                if !has_room {
                    write_packet_and_finish(
                        &mut send,
                        &SyncPacket::HandshakeAck {
                            accepted: false,
                            status: "Room not registered or key missing on host".into(),
                            host_node_id: self.node_id().to_string(),
                            display_name: my_display_name,
                        },
                    )
                    .await?;
                    return Ok(());
                }

                write_packet_and_finish(
                    &mut send,
                    &SyncPacket::HandshakeAck {
                        accepted: true,
                        status: "OK".into(),
                        host_node_id: self.node_id().to_string(),
                        display_name: my_display_name,
                    },
                )
                .await?;

                let active_peer = ActivePeer {
                    peer_id: remote_id.clone(),
                    display_name: remote_display_name.clone(),
                    connection: connection.clone(),
                    last_seen: Arc::new(RwLock::new(Instant::now())),
                };

                {
                    let mut peers = self.active_peers.write().await;
                    peers.entry(room_id.clone()).or_default().push(active_peer);
                }

                let is_new = {
                    let mut known = self.known_members.write().await;
                    let map = known.entry(room_id.clone()).or_default();
                    let is_new = !map.contains_key(&remote_id);
                    map.insert(remote_id.clone(), remote_display_name.clone());
                    map.insert(self.node_id().to_string(), self.get_display_name().await);
                    is_new
                };

                let (total, online) = self.get_peer_counts(&room_id).await;

                let _ = self.legacy_event_sender.send(P2pEvent::peer_connected(remote_id.clone(), room_id.clone()));
                if is_new {
                    self.emit_room_event(&room_id, RoomEvent::peer_joined(
                        room_id.clone(),
                        remote_id.clone(),
                        remote_display_name.clone(),
                    )).await;
                }
                self.emit_room_event(&room_id, RoomEvent::active_peer_count(
                    room_id.clone(),
                    total,
                    online,
                )).await;

                // Spawn incoming streams loop for this connection
                let stream_node = self.clone();
                let stream_room_id = room_id.clone();
                let stream_peer_id = remote_id.clone();
                crate::get_runtime().spawn(async move {
                    let _ = stream_node
                        .process_incoming_streams(connection, stream_room_id, stream_peer_id)
                        .await;
                });
            }
            _ => {
                debug_print(&format!("Expected Handshake packet from peer: {}", peer_node_id));
                return Err(anyhow!("Expected Handshake packet"));
            }
        }

        Ok(())
    }

    async fn process_incoming_streams(&self, connection: Connection, room_id: String, peer_id: String) -> Result<()> {
        loop {
            match connection.accept_bi().await {
                Ok((mut send, mut recv)) => {
                    let packet = match read_packet(&mut recv).await {
                        Ok(p) => p,
                        Err(e) => {
                            debug_print(&format!("Error reading packet from stream: {e}"));
                            break;
                        }
                    };

                    self.handle_sync_packet(packet, &connection, &mut send, &room_id, &peer_id).await;
                }
                Err(_) => {
                    break;
                }
            }
        }

        // Connection closed or dropped: remove from active peers
        {
            let mut peers = self.active_peers.write().await;
            if let Some(list) = peers.get_mut(&room_id) {
                list.retain(|p| p.connection.stable_id() != connection.stable_id());
            }
        }

        let (total, online) = self.get_peer_counts(&room_id).await;

        let _ = self.legacy_event_sender.send(P2pEvent::peer_disconnected(peer_id.clone(), room_id.clone()));
        self.emit_room_event(&room_id, RoomEvent::peer_left(
            room_id.clone(),
            peer_id.clone(),
        )).await;
        self.emit_room_event(&room_id, RoomEvent::active_peer_count(
            room_id.clone(),
            total,
            online,
        )).await;

        Ok(())
    }

    async fn handle_sync_packet(
        &self,
        packet: SyncPacket,
        _connection: &Connection,
        send: &mut SendStream,
        room_id: &str,
        peer_id: &str,
    ) {
        // Update heartbeat / last_seen for this peer
        {
            let peers = self.active_peers.read().await;
            if let Some(list) = peers.get(room_id) {
                for p in list {
                    if p.peer_id == peer_id {
                        let mut ls = p.last_seen.write().await;
                        *ls = Instant::now();
                    }
                }
            }
        }

        match packet {
            SyncPacket::PresenceHeartbeat { .. } => {
                // Heartbeat touched last_seen above
            }
            SyncPacket::PeerJoin {
                room_id: pkt_room_id,
                peer_id: remote_id,
                display_name,
            } => {
                if pkt_room_id == room_id {
                    let is_new = {
                        let mut known = self.known_members.write().await;
                        let map = known.entry(room_id.to_string()).or_default();
                        let is_new = !map.contains_key(&remote_id);
                        map.insert(remote_id.clone(), display_name.clone());
                        is_new
                    };
                    let (total, online) = self.get_peer_counts(room_id).await;
                    if is_new {
                        self.emit_room_event(room_id, RoomEvent::peer_joined(
                            room_id.to_string(),
                            remote_id,
                            display_name,
                        )).await;
                    }
                    self.emit_room_event(room_id, RoomEvent::active_peer_count(
                        room_id.to_string(),
                        total,
                        online,
                    )).await;
                }
            }
            SyncPacket::TypingEvent {
                room_id: pkt_room_id,
                peer_id: remote_id,
                is_typing,
            } => {
                if pkt_room_id == room_id {
                    if is_typing {
                        let _ = self.legacy_event_sender.send(P2pEvent::typing(remote_id.clone(), room_id.to_string()));
                    }
                    self.emit_room_event(room_id, RoomEvent::remote_typing(
                        room_id.to_string(),
                        remote_id,
                        is_typing,
                    )).await;
                }
            }
            SyncPacket::RequestHistory {
                room_id: pkt_room_id,
                last_synced_timestamp,
            } => {
                if pkt_room_id == room_id {
                    if let Some(key_bytes) = self.get_room_key(room_id).await {
                        if let Ok(notes) = crate::api::notes::get_notes_for_history(room_id, last_synced_timestamp) {
                            let mut encrypted_payloads = Vec::new();
                            for n in notes {
                                if let Ok((cipher, nonce)) = encrypt_shared_content(n.content.as_bytes(), &key_bytes) {
                                    encrypted_payloads.push(EncryptedNotePayload {
                                        id: n.id,
                                        room_id: n.room_id,
                                        ciphertext: cipher,
                                        nonce,
                                        timestamp_ms: n.timestamp_ms,
                                        is_todo: n.is_todo,
                                        is_completed: n.is_completed,
                                        is_pinned: n.is_pinned,
                                        tags: n.tags,
                                        author_id: None,
                                    });
                                }
                            }

                            let response = SyncPacket::HistoryResponse {
                                room_id: room_id.to_string(),
                                notes: encrypted_payloads,
                            };
                            let _ = write_packet_and_finish(send, &response).await;
                        }
                    }
                }
            }
            SyncPacket::HistoryResponse {
                room_id: pkt_room_id,
                notes,
            } => {
                if pkt_room_id == room_id {
                    if let Some(key_bytes) = self.get_room_key(room_id).await {
                        let sender_dn = {
                            let known = self.known_members.read().await;
                            known.get(room_id).and_then(|m| m.get(peer_id).cloned())
                        };

                        for note in notes {
                            if let Ok(plaintext) = decrypt_shared_content(&note.ciphertext, &note.nonce, &key_bytes) {
                                if let Ok(saved_item) = crate::api::notes::upsert_synced_note(
                                    &note.id,
                                    room_id,
                                    &plaintext,
                                    note.timestamp_ms,
                                    note.is_todo,
                                    note.is_completed,
                                    note.is_pinned,
                                ) {
                                    let _ = self.legacy_event_sender.send(P2pEvent::note_received(
                                        saved_item.id.clone(),
                                        room_id.to_string(),
                                        plaintext,
                                        peer_id.to_string(),
                                        saved_item.timestamp_ms,
                                        saved_item.is_todo,
                                        saved_item.is_completed,
                                    ));
                                    self.emit_room_event(room_id, RoomEvent::note_received(
                                        room_id.to_string(),
                                        saved_item,
                                        Some(peer_id.to_string()),
                                        sender_dn.clone(),
                                    )).await;
                                }
                            }
                        }
                    }
                }
            }
            SyncPacket::BroadcastNote {
                room_id: pkt_room_id,
                note,
            } => {
                if pkt_room_id == room_id {
                    if let Some(key_bytes) = self.get_room_key(room_id).await {
                        let sender_dn = {
                            let known = self.known_members.read().await;
                            known.get(room_id).and_then(|m| m.get(peer_id).cloned())
                        };

                        if let Ok(plaintext) = decrypt_shared_content(&note.ciphertext, &note.nonce, &key_bytes) {
                            if let Ok(saved_item) = crate::api::notes::upsert_synced_note(
                                &note.id,
                                room_id,
                                &plaintext,
                                note.timestamp_ms,
                                note.is_todo,
                                note.is_completed,
                                note.is_pinned,
                            ) {
                                let _ = self.legacy_event_sender.send(P2pEvent::note_received(
                                    saved_item.id.clone(),
                                    room_id.to_string(),
                                    plaintext,
                                    peer_id.to_string(),
                                    saved_item.timestamp_ms,
                                    saved_item.is_todo,
                                    saved_item.is_completed,
                                ));
                                self.emit_room_event(room_id, RoomEvent::note_received(
                                    room_id.to_string(),
                                    saved_item,
                                    Some(peer_id.to_string()),
                                    sender_dn,
                                )).await;
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    }

    /// Background heartbeat loop: runs every 5 seconds, sends heartbeats, checks timeouts (15s)
    async fn run_heartbeat_loop(&self) {
        let mut interval = tokio::time::interval(Duration::from_secs(5));
        loop {
            interval.tick().await;

            let now = Instant::now();
            let now_ms = chrono::Utc::now().timestamp_millis();
            let local_id = self.node_id().to_string();

            let mut rooms_to_update = Vec::new();

            {
                let mut peers_map = self.active_peers.write().await;
                for (room_id, peer_list) in peers_map.iter_mut() {
                    let mut timed_out_peers = Vec::new();

                    for peer in peer_list.iter() {
                        let ls = *peer.last_seen.read().await;
                        if now.duration_since(ls) > Duration::from_secs(15) {
                            timed_out_peers.push(peer.peer_id.clone());
                        } else {
                            // Send heartbeat
                            let pkt = SyncPacket::PresenceHeartbeat {
                                room_id: room_id.clone(),
                                peer_id: local_id.clone(),
                                timestamp: now_ms,
                            };
                            let conn = peer.connection.clone();
                            crate::get_runtime().spawn(async move {
                                if let Ok((mut send, _recv)) = conn.open_bi().await {
                                    let _ = write_packet_and_finish(&mut send, &pkt).await;
                                }
                            });
                        }
                    }

                    if !timed_out_peers.is_empty() {
                        peer_list.retain(|p| !timed_out_peers.contains(&p.peer_id));
                        rooms_to_update.push((room_id.clone(), timed_out_peers));
                    }
                }
            }

            for (room_id, timed_out) in rooms_to_update {
                let (total, online) = self.get_peer_counts(&room_id).await;
                for p_id in timed_out {
                    let _ = self.legacy_event_sender.send(P2pEvent::peer_disconnected(p_id.clone(), room_id.clone()));
                    self.emit_room_event(&room_id, RoomEvent::peer_left(
                        room_id.clone(),
                        p_id,
                    )).await;
                }
                self.emit_room_event(&room_id, RoomEvent::active_peer_count(
                    room_id.clone(),
                    total,
                    online,
                )).await;
            }
        }
    }

    pub async fn register_shared_room(&self, room_id: String, key_bytes: [u8; 32]) {
        let mut rooms = self.shared_rooms.write().await;
        rooms.insert(room_id, key_bytes);
    }

    pub async fn get_room_key(&self, room_id: &str) -> Option<[u8; 32]> {
        let rooms = self.shared_rooms.read().await;
        rooms.get(room_id).copied()
    }

    /// Export a combined invitation ticket containing encryption key and network dialing address
    pub async fn export_room_ticket(&self, room_id: String, room_name: String) -> Result<String> {
        let key_bytes = match self.get_room_key(&room_id).await {
            Some(k) => k,
            None => {
                let mut k = [0u8; 32];
                rand::rngs::OsRng.fill_bytes(&mut k);
                self.register_shared_room(room_id.clone(), k).await;
                k
            }
        };

        let node_addr: NodeAddr = self.endpoint.node_addr().await.context("Failed to get local NodeAddr")?;

        let ticket = RoomShareTicket {
            room_id,
            room_name,
            encryption_key: BASE64.encode(key_bytes),
            node_addr,
        };

        // Compress: JSON → Zlib → URL-safe Base64 (produces ~40% shorter tickets = denser QR)
        let json = serde_json::to_vec(&ticket)?;
        let mut encoder = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::best());
        use std::io::Write;
        encoder.write_all(&json).context("Zlib encode failed")?;
        let compressed = encoder.finish().context("Zlib finish failed")?;
        let base64_ticket = BASE64_URL.encode(&compressed);
        Ok(format!("notetosms://join?ticket={}", base64_ticket))
    }

    /// Alias for backward compatibility
    pub async fn generate_room_invite(&self, room_id: String, room_name: String) -> Result<String> {
        self.export_room_ticket(room_id, room_name).await
    }

    /// Import and connect to a room using a combined RoomShareTicket or legacy invite
    pub async fn import_room_ticket(&self, ticket_data: String) -> Result<RoomShareTicket> {
        let cleaned = ticket_data
            .trim()
            .trim_start_matches("notetosms://join?ticket=")
            .trim_start_matches("notetosms://invite?data=");

        // Try compressed format (URL-safe Base64 → Zlib → JSON) first, then fall back to legacy plain Base64-JSON
        let json_bytes: Vec<u8> = if let Ok(compressed) = BASE64_URL.decode(cleaned) {
            use std::io::Read;
            let mut decoder = flate2::read::ZlibDecoder::new(compressed.as_slice());
            let mut buf = Vec::new();
            if decoder.read_to_end(&mut buf).is_ok() && !buf.is_empty() {
                buf
            } else if let Ok(plain) = BASE64.decode(cleaned) {
                plain
            } else {
                return Err(anyhow!("Invalid compressed or base64 ticket string"));
            }
        } else if let Ok(plain) = BASE64.decode(cleaned) {
            plain
        } else {
            return Err(anyhow!("Invalid base64 ticket string"));
        };

        // Attempt deserializing as new RoomShareTicket, fallback to RoomInvitePayload
        let ticket: RoomShareTicket = if let Ok(t) = serde_json::from_slice::<RoomShareTicket>(&json_bytes) {
            t
        } else if let Ok(legacy) = serde_json::from_slice::<RoomInvitePayload>(&json_bytes) {
            let host_node_id: NodeId = legacy.host_node_id.parse().context("Invalid host NodeId in legacy invite")?;
            let mut node_addr = NodeAddr::new(host_node_id);

            if let Some(ref relay_str) = legacy.relay_url {
                if let Ok(relay_url) = relay_str.parse() {
                    node_addr = node_addr.with_relay_url(relay_url);
                }
            }

            for addr_str in &legacy.direct_addrs {
                if let Ok(sock_addr) = addr_str.parse() {
                    node_addr = node_addr.with_direct_addresses(vec![sock_addr]);
                }
            }

            RoomShareTicket {
                room_id: legacy.room_id,
                room_name: legacy.room_name,
                encryption_key: legacy.shared_key_b64,
                node_addr,
            }
        } else {
            return Err(anyhow!("Unsupported ticket payload format"));
        };

        let key_bytes_vec = BASE64.decode(&ticket.encryption_key).context("Invalid base64 room encryption key")?;
        if key_bytes_vec.len() != 32 {
            return Err(anyhow!("Room encryption key must be exactly 32 bytes"));
        }
        let mut key_bytes = [0u8; 32];
        key_bytes.copy_from_slice(&key_bytes_vec);

        // Register room key in memory
        self.register_shared_room(ticket.room_id.clone(), key_bytes).await;

        // Dial Device A directly using Iroh endpoint
        let connection: Connection = self
            .endpoint
            .connect(ticket.node_addr.clone(), P2P_ALPN)
            .await
            .context("Failed to connect to peer endpoint via Iroh")?;

        let (mut send, mut recv) = connection.open_bi().await.context("Failed to open handshake bi-stream")?;

        let my_display_name = self.get_display_name().await;
        write_packet_and_finish(
            &mut send,
            &SyncPacket::Handshake {
                peer_node_id: self.node_id().to_string(),
                room_id: ticket.room_id.clone(),
                display_name: my_display_name.clone(),
            },
        )
        .await?;

        let ack = read_packet(&mut recv).await?;
        let host_display_name = match ack {
            SyncPacket::HandshakeAck {
                accepted,
                status,
                display_name: host_dn,
                ..
            } => {
                if !accepted {
                    return Err(anyhow!("Handshake rejected by host: {}", status));
                }
                host_dn
            }
            _ => return Err(anyhow!("Unexpected response during handshake")),
        };

        let host_peer_id = ticket.node_addr.node_id.to_string();
        let active_peer = ActivePeer {
            peer_id: host_peer_id.clone(),
            display_name: host_display_name.clone(),
            connection: connection.clone(),
            last_seen: Arc::new(RwLock::new(Instant::now())),
        };

        {
            let mut peers = self.active_peers.write().await;
            peers.entry(ticket.room_id.clone()).or_default().push(active_peer);
        }

        let is_new = {
            let mut known = self.known_members.write().await;
            let map = known.entry(ticket.room_id.clone()).or_default();
            let is_new = !map.contains_key(&host_peer_id);
            map.insert(host_peer_id.clone(), host_display_name.clone());
            map.insert(self.node_id().to_string(), my_display_name.clone());
            is_new
        };

        let (total, online) = self.get_peer_counts(&ticket.room_id).await;

        let _ = self.legacy_event_sender.send(P2pEvent::peer_connected(host_peer_id.clone(), ticket.room_id.clone()));
        if is_new {
            self.emit_room_event(&ticket.room_id, RoomEvent::peer_joined(
                ticket.room_id.clone(),
                host_peer_id.clone(),
                host_display_name.clone(),
            )).await;
        }
        self.emit_room_event(&ticket.room_id, RoomEvent::active_peer_count(
            ticket.room_id.clone(),
            total,
            online,
        )).await;

        // Send PeerJoin
        let join_conn = connection.clone();
        let join_room_id = ticket.room_id.clone();
        let my_dn_clone = my_display_name.clone();
        let my_node_id = self.node_id().to_string();
        crate::get_runtime().spawn(async move {
            if let Ok((mut send, _recv)) = join_conn.open_bi().await {
                let _ = write_packet_and_finish(
                    &mut send,
                    &SyncPacket::PeerJoin {
                        room_id: join_room_id,
                        peer_id: my_node_id,
                        display_name: my_dn_clone,
                    },
                )
                .await;
            }
        });

        // Request history and process response directly on the request stream
        let req_conn = connection.clone();
        let req_room_id = ticket.room_id.clone();
        let node_ref = self.clone();
        let host_dn_for_history = host_display_name.clone();
        let host_id_for_history = host_peer_id.clone();
        crate::get_runtime().spawn(async move {
            if let Ok((mut send, mut recv)) = req_conn.open_bi().await {
                let req_history_pkt = SyncPacket::RequestHistory {
                    room_id: req_room_id.clone(),
                    last_synced_timestamp: 0,
                };
                if write_packet_and_finish(&mut send, &req_history_pkt).await.is_ok() {
                    if let Ok(SyncPacket::HistoryResponse { room_id, notes }) = read_packet(&mut recv).await {
                        if let Some(kb) = node_ref.get_room_key(&room_id).await {
                            for note in notes {
                                if let Ok(plaintext) = decrypt_shared_content(&note.ciphertext, &note.nonce, &kb) {
                                    if let Ok(saved) = crate::api::notes::upsert_synced_note(
                                        &note.id,
                                        &room_id,
                                        &plaintext,
                                        note.timestamp_ms,
                                        note.is_todo,
                                        note.is_completed,
                                        note.is_pinned,
                                    ) {
                                        node_ref.emit_room_event(&room_id, RoomEvent::note_received(
                                            room_id.clone(),
                                            saved,
                                            Some(host_id_for_history.clone()),
                                            Some(host_dn_for_history.clone()),
                                        )).await;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        });

        // Spawn stream reader loop for future incoming broadcasts from host
        let stream_node = self.clone();
        let stream_room_id = ticket.room_id.clone();
        let stream_host_id = host_peer_id.clone();
        crate::get_runtime().spawn(async move {
            let _ = stream_node
                .process_incoming_streams(connection, stream_room_id, stream_host_id)
                .await;
        });

        Ok(ticket)
    }

    /// Alias for join_room_by_invite
    pub async fn join_room_by_invite(&self, invite_payload: String) -> Result<RoomInvitePayload> {
        let ticket = self.import_room_ticket(invite_payload).await?;
        let direct_addrs = ticket
            .node_addr
            .direct_addresses()
            .map(|a| a.to_string())
            .collect();
        let relay_url = ticket.node_addr.relay_url().map(|r| r.to_string());

        Ok(RoomInvitePayload {
            room_id: ticket.room_id,
            room_name: ticket.room_name,
            shared_key_b64: ticket.encryption_key,
            host_node_id: ticket.node_addr.node_id.to_string(),
            relay_url,
            direct_addrs,
        })
    }

    /// Broadcast a note item to all active peers connected to a shared room
    pub async fn broadcast_note_item(&self, room_id: &str, note: &NoteItem) -> Result<()> {
        let key_bytes = match self.get_room_key(room_id).await {
            Some(k) => k,
            None => return Ok(()),
        };

        let active_conns: Vec<Connection> = {
            let peers = self.active_peers.read().await;
            peers
                .get(room_id)
                .map(|list| list.iter().map(|p| p.connection.clone()).collect())
                .unwrap_or_default()
        };

        if active_conns.is_empty() {
            return Ok(());
        }

        let (ciphertext, nonce) = encrypt_shared_content(note.content.as_bytes(), &key_bytes)?;

        let packet = SyncPacket::BroadcastNote {
            room_id: room_id.to_string(),
            note: EncryptedNotePayload {
                id: note.id.clone(),
                room_id: note.room_id.clone(),
                ciphertext,
                nonce,
                timestamp_ms: note.timestamp_ms,
                is_todo: note.is_todo,
                is_completed: note.is_completed,
                is_pinned: note.is_pinned,
                tags: note.tags.clone(),
                author_id: Some(self.node_id().to_string()),
            },
        };

        for conn in active_conns {
            let pkt = packet.clone();
            crate::get_runtime().spawn(async move {
                if let Ok((mut send, _recv)) = conn.open_bi().await {
                    let _ = write_packet_and_finish(&mut send, &pkt).await;
                }
            });
        }

        Ok(())
    }

    /// Broadcast a typing indicator event across active peers in a room
    pub async fn broadcast_typing(&self, room_id: &str, is_typing: bool) -> Result<()> {
        let active_conns: Vec<Connection> = {
            let peers = self.active_peers.read().await;
            peers
                .get(room_id)
                .map(|list| list.iter().map(|p| p.connection.clone()).collect())
                .unwrap_or_default()
        };

        if active_conns.is_empty() {
            return Ok(());
        }

        let packet = SyncPacket::TypingEvent {
            room_id: room_id.to_string(),
            peer_id: self.node_id().to_string(),
            is_typing,
        };

        for conn in active_conns {
            let pkt = packet.clone();
            crate::get_runtime().spawn(async move {
                if let Ok((mut send, _recv)) = conn.open_bi().await {
                    let _ = write_packet_and_finish(&mut send, &pkt).await;
                }
            });
        }

        Ok(())
    }
}

pub fn encrypt_shared_content(plaintext: &[u8], key_bytes: &[u8; 32]) -> Result<(Vec<u8>, [u8; 12])> {
    let key = Key::from_slice(key_bytes);
    let cipher = ChaCha20Poly1305::new(key);
    let mut nonce_bytes = [0u8; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| anyhow!("ChaCha20Poly1305 encryption failed: {e}"))?;

    Ok((ciphertext, nonce_bytes))
}

pub fn decrypt_shared_content(ciphertext: &[u8], nonce_bytes: &[u8; 12], key_bytes: &[u8; 32]) -> Result<String> {
    let key = Key::from_slice(key_bytes);
    let cipher = ChaCha20Poly1305::new(key);
    let nonce = Nonce::from_slice(nonce_bytes);

    let plaintext_bytes = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| anyhow!("ChaCha20Poly1305 decryption failed: {e}"))?;

    let text = String::from_utf8(plaintext_bytes).context("Decrypted bytes are not valid UTF-8")?;
    Ok(text)
}

async fn write_packet(send: &mut SendStream, packet: &SyncPacket) -> Result<()> {
    let bytes = serde_json::to_vec(packet)?;
    let len = (bytes.len() as u32).to_be_bytes();
    send.write_all(&len).await?;
    send.write_all(&bytes).await?;
    Ok(())
}

async fn write_packet_and_finish(send: &mut SendStream, packet: &SyncPacket) -> Result<()> {
    write_packet(send, packet).await?;
    send.finish()?;
    Ok(())
}

async fn read_packet(recv: &mut RecvStream) -> Result<SyncPacket> {
    let mut len_buf = [0u8; 4];
    recv.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf) as usize;

    if len > 10 * 1024 * 1024 {
        return Err(anyhow!("Packet size exceeds 10MB limit"));
    }

    let mut data_buf = vec![0u8; len];
    recv.read_exact(&mut data_buf).await?;

    let packet: SyncPacket = serde_json::from_slice(&data_buf)?;
    Ok(packet)
}

fn debug_print(msg: &str) {
    #[cfg(debug_assertions)]
    eprintln!("[P2P] {}", msg);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shared_content_encryption_decryption_roundtrip() {
        let key_bytes = [42u8; 32];
        let original_text = "Encrypted P2P Shared Note Payload #sync";

        let (ciphertext, nonce) = encrypt_shared_content(original_text.as_bytes(), &key_bytes).unwrap();
        assert_ne!(ciphertext, original_text.as_bytes());

        let decrypted = decrypt_shared_content(&ciphertext, &nonce, &key_bytes).unwrap();
        assert_eq!(decrypted, original_text);
    }

    #[tokio::test]
    async fn test_p2p_node_init_and_invite_generation() {
        let node = P2pNode::get_or_init().await.unwrap();
        let ticket_uri = node
            .export_room_ticket("project-x".into(), "Project X".into())
            .await
            .unwrap();

        assert!(ticket_uri.starts_with("notetosms://join?ticket="));

        let payload_base64 = ticket_uri.trim_start_matches("notetosms://join?ticket=");
        let json_bytes = BASE64.decode(payload_base64).unwrap();
        let ticket: RoomShareTicket = serde_json::from_slice(&json_bytes).unwrap();

        assert_eq!(ticket.room_id, "project-x");
        assert_eq!(ticket.room_name, "Project X");
        assert!(!ticket.encryption_key.is_empty());
        assert_eq!(ticket.node_addr.node_id, node.node_id());
    }
}
