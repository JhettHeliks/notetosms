use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
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

pub use crate::p2p_protocol::{
    decode_ticket_payload, hex_prefix, EncryptedNotePayload, RoomEvent, RoomShareTicket,
    SyncPacket, TICKET_VERSION_COMPACT,
};
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

        // Restore custom user profile display name if set
        if let Ok(profile) = crate::api::notes::get_user_profile() {
            node.set_display_name(profile.display_name).await;
        }

        // Restore shared room keys and initiate background sync for active threads
        if let Ok(shared_rooms) = crate::api::notes::get_shared_rooms_with_keys() {
            for r in shared_rooms {
                if let Ok(key_bytes_vec) = BASE64.decode(&r.encryption_key) {
                    if key_bytes_vec.len() == 32 {
                        let mut k = [0u8; 32];
                        k.copy_from_slice(&key_bytes_vec);
                        node.register_shared_room(r.room_id.clone(), k).await;
                    }
                }
                if r.is_background_sync_enabled {
                    if let Some(ticket_str) = r.share_ticket {
                        let node_clone = node.clone();
                        crate::get_runtime().spawn(async move {
                            let _ = node_clone.import_room_ticket(ticket_str).await;
                        });
                    }
                }
            }
        }

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
            let mut unique_peers = std::collections::HashSet::new();
            if let Some(list) = peers.get(room_id) {
                for p in list {
                    unique_peers.insert(&p.peer_id);
                }
            }
            unique_peers.len() as i32 + 1 // +1 for local self
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
                key_fingerprint,
            } => {
                let (has_room, matched_room_id, matched_room_name) = {
                    let rooms = self.shared_rooms.read().await;
                    if let Some(_k) = rooms.get(&room_id) {
                        let r_name = crate::api::notes::get_room_by_id(&room_id)
                            .ok()
                            .map(|r| r.name)
                            .unwrap_or_else(|| room_id.clone());
                        (true, room_id.clone(), r_name)
                    } else if let Ok(all_rooms) = crate::api::notes::get_shared_rooms_with_keys() {
                        let mut found = None;
                        for r in all_rooms {
                            if let Ok(k_bytes) = BASE64.decode(&r.encryption_key) {
                                if k_bytes.len() == 32 {
                                    let fp = hex_prefix(&k_bytes[0..8]);
                                    if key_fingerprint.as_deref() == Some(&fp) || r.room_id == room_id {
                                        let r_name = crate::api::notes::get_room_by_id(&r.room_id)
                                            .ok()
                                            .map(|room| room.name)
                                            .unwrap_or_else(|| r.room_id.clone());
                                        found = Some((r.room_id.clone(), r_name));
                                        break;
                                    }
                                }
                            }
                        }
                        if let Some((r_id, r_name)) = found {
                            (true, r_id, r_name)
                        } else {
                            (false, room_id.clone(), room_id.clone())
                        }
                    } else {
                        (false, room_id.clone(), room_id.clone())
                    }
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
                            room_id: None,
                            room_name: None,
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
                        room_id: Some(matched_room_id.clone()),
                        room_name: Some(matched_room_name),
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
                    let list = peers.entry(matched_room_id.clone()).or_default();
                    list.retain(|p| p.peer_id != remote_id && p.connection.stable_id() != connection.stable_id());
                    list.push(active_peer);
                }

                let is_new = {
                    let mut known = self.known_members.write().await;
                    let map = known.entry(matched_room_id.clone()).or_default();
                    let is_new = !map.contains_key(&remote_id);
                    map.insert(remote_id.clone(), remote_display_name.clone());
                    map.insert(self.node_id().to_string(), self.get_display_name().await);
                    is_new
                };

                let (total, online) = self.get_peer_counts(&matched_room_id).await;

                let _ = self.legacy_event_sender.send(P2pEvent::peer_connected(remote_id.clone(), matched_room_id.clone()));
                if is_new {
                    self.emit_room_event(&matched_room_id, RoomEvent::peer_joined(
                        matched_room_id.clone(),
                        remote_id.clone(),
                        remote_display_name.clone(),
                    )).await;
                }
                self.emit_room_event(&matched_room_id, RoomEvent::active_peer_count(
                    matched_room_id.clone(),
                    total,
                    online,
                )).await;

                // Spawn incoming streams loop for this connection
                let stream_node = self.clone();
                let stream_room_id = matched_room_id.clone();
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
                list.retain(|p| p.peer_id != peer_id && p.connection.stable_id() != connection.stable_id());
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
            SyncPacket::PresenceHeartbeat { room_id: pkt_room_id, peer_id: _remote_id, .. } => {
                // Respond with heartbeat ACK
                if pkt_room_id == room_id {
                    let ack = SyncPacket::PresenceHeartbeatAck {
                        room_id: room_id.to_string(),
                        peer_id: self.node_id().to_string(),
                    };
                    let _ = write_packet_and_finish(send, &ack).await;
                }
            }
            SyncPacket::PresenceHeartbeatAck { .. } => {
                // Heartbeat touched last_seen above
            }
            SyncPacket::PeerDisconnecting {
                room_id: pkt_room_id,
                peer_id: remote_id,
            } => {
                if pkt_room_id == room_id {
                    {
                        let mut peers = self.active_peers.write().await;
                        if let Some(list) = peers.get_mut(room_id) {
                            list.retain(|p| p.peer_id != remote_id);
                        }
                    }
                    let (total, online) = self.get_peer_counts(room_id).await;
                    let _ = self.legacy_event_sender.send(P2pEvent::peer_disconnected(remote_id.clone(), room_id.to_string()));
                    self.emit_room_event(room_id, RoomEvent::peer_left(
                        room_id.to_string(),
                        remote_id,
                    )).await;
                    self.emit_room_event(room_id, RoomEvent::active_peer_count(
                        room_id.to_string(),
                        total,
                        online,
                    )).await;
                }
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
                                        author_id: n.author_id,
                                        author_name: n.author_name,
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
                            let note_author_id = note.author_id.as_deref().or(Some(peer_id));
                            let note_author_name = note.author_name.as_deref().or(sender_dn.as_deref());

                            if let Ok(plaintext) = decrypt_shared_content(&note.ciphertext, &note.nonce, &key_bytes) {
                                if let Ok(saved_item) = crate::api::notes::upsert_synced_note(
                                    &note.id,
                                    room_id,
                                    &plaintext,
                                    note.timestamp_ms,
                                    note.is_todo,
                                    note.is_completed,
                                    note.is_pinned,
                                    note_author_id,
                                    note_author_name,
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
                                        note_author_name.map(|s| s.to_string()),
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

                        let note_author_id = note.author_id.as_deref().or(Some(peer_id));
                        let note_author_name = note.author_name.as_deref().or(sender_dn.as_deref());

                        if let Ok(plaintext) = decrypt_shared_content(&note.ciphertext, &note.nonce, &key_bytes) {
                            if let Ok(saved_item) = crate::api::notes::upsert_synced_note(
                                &note.id,
                                room_id,
                                &plaintext,
                                note.timestamp_ms,
                                note.is_todo,
                                note.is_completed,
                                note.is_pinned,
                                note_author_id,
                                note_author_name,
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
                                    note_author_name.map(|s| s.to_string()),
                                )).await;
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    }

    /// Background heartbeat loop: runs every 10 seconds, sends heartbeats, checks timeouts (22s)
    async fn run_heartbeat_loop(&self) {
        let mut interval = tokio::time::interval(Duration::from_secs(10));
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
                        let is_closed = peer.connection.close_reason().is_some();
                        if is_closed || now.duration_since(ls) > Duration::from_secs(22) {
                            timed_out_peers.push(peer.peer_id.clone());
                        } else {
                            // Send heartbeat
                            let pkt = SyncPacket::PresenceHeartbeat {
                                room_id: room_id.clone(),
                                peer_id: local_id.clone(),
                                timestamp: now_ms,
                            };
                            let conn = peer.connection.clone();
                            let p_id = peer.peer_id.clone();
                            let r_id = room_id.clone();
                            let node_ref = self.clone();
                            crate::get_runtime().spawn(async move {
                                match conn.open_bi().await {
                                    Ok((mut send, mut recv)) => {
                                        if write_packet_and_finish(&mut send, &pkt).await.is_ok() {
                                            if let Ok(SyncPacket::PresenceHeartbeatAck { .. }) = read_packet(&mut recv).await {
                                                // Ack received and touched
                                            }
                                        }
                                    }
                                    Err(_) => {
                                        // QUIC connection closed/dead: remove immediately
                                        let mut peers = node_ref.active_peers.write().await;
                                        if let Some(list) = peers.get_mut(&r_id) {
                                            list.retain(|p| p.peer_id != p_id);
                                        }
                                        let (total, online) = node_ref.get_peer_counts(&r_id).await;
                                        let _ = node_ref.legacy_event_sender.send(P2pEvent::peer_disconnected(p_id.clone(), r_id.clone()));
                                        node_ref.emit_room_event(&r_id, RoomEvent::peer_left(r_id.clone(), p_id)).await;
                                        node_ref.emit_room_event(&r_id, RoomEvent::active_peer_count(r_id.clone(), total, online)).await;
                                    }
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

    pub async fn disconnect_all_peers(&self) {
        let local_id = self.node_id().to_string();
        let mut peers_map = self.active_peers.write().await;
        for (room_id, peer_list) in peers_map.iter_mut() {
            for peer in peer_list.drain(..) {
                let pkt = SyncPacket::PeerDisconnecting {
                    room_id: room_id.clone(),
                    peer_id: local_id.clone(),
                };
                let conn = peer.connection.clone();
                crate::get_runtime().spawn(async move {
                    if let Ok((mut send, _recv)) = conn.open_bi().await {
                        let _ = write_packet_and_finish(&mut send, &pkt).await;
                    }
                    conn.close(0u32.into(), b"App pausing or closing");
                });
            }
            let (total, online) = (1, 1);
            let _ = self.emit_room_event(room_id, RoomEvent::active_peer_count(room_id.clone(), total, online)).await;
        }
    }

    pub async fn boot_p2p_network(&self) -> Result<()> {
        if let Ok(profile) = crate::api::notes::get_user_profile() {
            self.set_display_name(profile.display_name.clone()).await;
        }

        if let Ok(shared_rooms) = crate::api::notes::get_shared_rooms_with_keys() {
            for r in shared_rooms {
                if let Ok(key_bytes_vec) = BASE64.decode(&r.encryption_key) {
                    if key_bytes_vec.len() == 32 {
                        let mut k = [0u8; 32];
                        k.copy_from_slice(&key_bytes_vec);
                        self.register_shared_room(r.room_id.clone(), k).await;
                    }
                }
                if let Some(ticket_str) = r.share_ticket {
                    if !ticket_str.trim().is_empty() {
                        let node_clone = self.clone();
                        crate::get_runtime().spawn(async move {
                            let _ = node_clone.import_room_ticket(ticket_str).await;
                        });
                    }
                }
            }
        }
        Ok(())
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
            room_id: room_id.clone(),
            room_name,
            encryption_key: BASE64.encode(key_bytes),
            node_addr,
        };

        // Compact 66-byte binary payload (Version 0x01 + 32B NodeId + 32B RoomKey + 1B RelayIndex)
        // Encoded via Base58 (~89-91 chars) for compact, SMS-friendly, fast-scanning QR codes
        let compact_66 = ticket.to_compact_66_bytes()?;
        let encoded_token = bs58::encode(&compact_66).into_string();
        let ticket_url = format!("notetosms://join?ticket={}", encoded_token);

        // Persist room encryption key & ticket in encrypted SQLite storage
        let _ = crate::api::notes::save_room_encryption_details(
            room_id,
            BASE64.encode(key_bytes),
            Some(ticket_url.clone()),
        );

        Ok(ticket_url)
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
            .trim_start_matches("notetosms://invite?data=")
            .trim_start_matches("chatnotes://join?ticket=")
            .trim_start_matches("chatnotes://invite?data=");

        let mut ticket = decode_ticket_payload(cleaned)?;

        let key_bytes_vec = BASE64.decode(&ticket.encryption_key).context("Invalid base64 room encryption key")?;
        if key_bytes_vec.len() != 32 {
            return Err(anyhow!("Room encryption key must be exactly 32 bytes"));
        }
        let mut key_bytes = [0u8; 32];
        key_bytes.copy_from_slice(&key_bytes_vec);

        // Dial host directly using Iroh endpoint
        let connection = self
            .endpoint
            .connect(ticket.node_addr.clone(), P2P_ALPN)
            .await?;

        let (mut send, mut recv) = connection.open_bi().await.context("Failed to open handshake bi-stream")?;

        let my_display_name = self.get_display_name().await;
        write_packet_and_finish(
            &mut send,
            &SyncPacket::Handshake {
                peer_node_id: self.node_id().to_string(),
                room_id: ticket.room_id.clone(),
                display_name: my_display_name.clone(),
                key_fingerprint: Some(hex_prefix(&key_bytes[0..8])),
            },
        )
        .await?;

        let ack = read_packet(&mut recv).await?;
        let (host_display_name, matched_room_id, matched_room_name) = match ack {
            SyncPacket::HandshakeAck {
                accepted,
                status,
                display_name: host_dn,
                room_id: ack_r_id,
                room_name: ack_r_name,
                ..
            } => {
                if !accepted {
                    return Err(anyhow!("Handshake rejected by host: {}", status));
                }
                (
                    host_dn,
                    ack_r_id.unwrap_or_else(|| ticket.room_id.clone()),
                    ack_r_name.unwrap_or_else(|| ticket.room_name.clone()),
                )
            }
            _ => return Err(anyhow!("Unexpected response during handshake")),
        };

        ticket.room_id = matched_room_id.clone();
        ticket.room_name = matched_room_name.clone();

        // Register room key in memory under final resolved room ID
        self.register_shared_room(ticket.room_id.clone(), key_bytes).await;

        // Persist room and key in local SQLite database
        let _ = crate::api::notes::upsert_room(&ticket.room_id, &ticket.room_name, "chat_bubble", 0xFF1A73E8);
        let _ = crate::api::notes::save_room_encryption_details(
            ticket.room_id.clone(),
            ticket.encryption_key.clone(),
            Some(format!("notetosms://join?ticket={}", cleaned)),
        );

        let host_peer_id = ticket.node_addr.node_id.to_string();
        let active_peer = ActivePeer {
            peer_id: host_peer_id.clone(),
            display_name: host_display_name.clone(),
            connection: connection.clone(),
            last_seen: Arc::new(RwLock::new(Instant::now())),
        };

        {
            let mut peers = self.active_peers.write().await;
            let list = peers.entry(ticket.room_id.clone()).or_default();
            list.retain(|p| p.peer_id != host_peer_id && p.connection.stable_id() != connection.stable_id());
            list.push(active_peer);
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
                                let note_author_id = note.author_id.as_deref().or(Some(&host_id_for_history));
                                let note_author_name = note.author_name.as_deref().or(Some(&host_dn_for_history));

                                if let Ok(plaintext) = decrypt_shared_content(&note.ciphertext, &note.nonce, &kb) {
                                    if let Ok(saved) = crate::api::notes::upsert_synced_note(
                                        &note.id,
                                        &room_id,
                                        &plaintext,
                                        note.timestamp_ms,
                                        note.is_todo,
                                        note.is_completed,
                                        note.is_pinned,
                                        note_author_id,
                                        note_author_name,
                                    ) {
                                        node_ref.emit_room_event(&room_id, RoomEvent::note_received(
                                            room_id.clone(),
                                            saved,
                                            Some(host_id_for_history.clone()),
                                            note_author_name.map(|s| s.to_string()),
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
        let my_display_name = self.get_display_name().await;

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
                author_name: Some(my_display_name),
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

        let payload_token = ticket_uri.trim_start_matches("notetosms://join?ticket=");
        // Assert token is compact (under 92 characters!)
        assert!(payload_token.len() <= 92, "Ticket token length is {} (expected <= 92)", payload_token.len());

        let decoded_ticket = decode_ticket_payload(payload_token).unwrap();
        assert!(!decoded_ticket.encryption_key.is_empty());
        assert_eq!(decoded_ticket.node_addr.node_id, node.node_id());

        // Verify direct 66-byte decode
        let raw_bytes = bs58::decode(payload_token).into_vec().unwrap();
        assert_eq!(raw_bytes.len(), 66);
        assert_eq!(raw_bytes[0], TICKET_VERSION_COMPACT);
    }
}
