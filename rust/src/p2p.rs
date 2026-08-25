use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Key, Nonce,
};
use iroh_net::endpoint::{get_remote_node_id, Connection, Endpoint, Incoming, RecvStream, SendStream};
use iroh_net::key::{NodeId, SecretKey};
use iroh_net::NodeAddr;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{broadcast, Mutex, RwLock};
use ulid::Ulid;

pub const P2P_ALPN: &[u8] = b"notetosms/p2p/v1";

/// Packet types exchanged over P2P QUIC streams
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum P2pPacket {
    Handshake {
        peer_node_id: String,
        room_id: String,
    },
    HandshakeAck {
        accepted: bool,
        status: String,
    },
    NoteDelta {
        ulid: String,
        room_id: String,
        author_id: String,
        ciphertext: Vec<u8>,
        nonce: [u8; 12],
        timestamp_ms: i64,
        is_todo: bool,
        is_completed: bool,
    },
}

/// Invitation ticket for joining a shared room
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomInvitePayload {
    pub room_id: String,
    pub room_name: String,
    pub shared_key_b64: String, // 32-byte room key encoded in base64
    pub host_node_id: String,
    pub relay_url: Option<String>,
    pub direct_addrs: Vec<String>,
}

/// P2P Event emitted across FRB to Flutter
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct P2pEvent {
    pub event_type: String, // "node_started", "peer_connected", "peer_disconnected", "note_received", "sync_error"
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

#[derive(Clone)]
pub struct P2pNode {
    pub secret_key: SecretKey,
    pub endpoint: Arc<Endpoint>,
    pub active_peers: Arc<RwLock<HashMap<String, Vec<Connection>>>>,
    pub shared_rooms: Arc<RwLock<HashMap<String, [u8; 32]>>>,
    pub event_sender: broadcast::Sender<P2pEvent>,
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
            .alpns(vec![P2P_ALPN.to_vec()])
            .bind()
            .await
            .context("Failed to bind iroh endpoint")?;

        let (event_sender, _) = broadcast::channel(128);

        let node = P2pNode {
            secret_key,
            endpoint: Arc::new(endpoint),
            active_peers: Arc::new(RwLock::new(HashMap::new())),
            shared_rooms: Arc::new(RwLock::new(HashMap::new())),
            event_sender,
        };

        let listener_node = node.clone();
        crate::get_runtime().spawn(async move {
            listener_node.run_listener_loop().await;
        });

        let node_id = node.node_id().to_string();
        let _ = node.event_sender.send(P2pEvent::node_started(node_id));

        *guard = Some(node.clone());
        Ok(node)
    }

    pub fn node_id(&self) -> NodeId {
        self.endpoint.node_id()
    }

    pub fn subscribe_events(&self) -> broadcast::Receiver<P2pEvent> {
        self.event_sender.subscribe()
    }

    async fn run_listener_loop(&self) {
        while let Some(incoming) = self.endpoint.accept().await {
            let node = self.clone();
            crate::get_runtime().spawn(async move {
                if let Err(e) = node.handle_incoming_connection(incoming).await {
                    let _ = node.event_sender.send(P2pEvent::sync_error(format!("Incoming connection error: {:#}", e)));
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
            P2pPacket::Handshake { room_id, .. } => {
                let has_room = {
                    let rooms = self.shared_rooms.read().await;
                    rooms.contains_key(&room_id)
                };

                if !has_room {
                    write_packet(
                        &mut send,
                        &P2pPacket::HandshakeAck {
                            accepted: false,
                            status: "Room not registered or key missing on host".into(),
                        },
                    )
                    .await?;
                    return Ok(());
                }

                write_packet(
                    &mut send,
                    &P2pPacket::HandshakeAck {
                        accepted: true,
                        status: "OK".into(),
                    },
                )
                .await?;

                {
                    let mut peers = self.active_peers.write().await;
                    peers.entry(room_id.clone()).or_default().push(connection.clone());
                }

                let _ = self.event_sender.send(P2pEvent::peer_connected(peer_node_id.clone(), room_id.clone()));

                let stream_node = self.clone();
                let stream_room_id = room_id.clone();
                crate::get_runtime().spawn(async move {
                    if let Err(e) = stream_node.process_incoming_streams(connection, stream_room_id, peer_node_id).await {
                        let _ = stream_node.event_sender.send(P2pEvent::sync_error(format!("Stream loop ended: {:#}", e)));
                    }
                });
            }
            _ => {
                return Err(anyhow!("Expected Handshake packet"));
            }
        }

        Ok(())
    }

    async fn process_incoming_streams(&self, connection: Connection, room_id: String, peer_id: String) -> Result<()> {
        loop {
            match connection.accept_bi().await {
                Ok((mut _send, mut recv)) => {
                    match read_packet(&mut recv).await {
                        Ok(P2pPacket::NoteDelta {
                            ulid,
                            room_id: delta_room_id,
                            author_id,
                            ciphertext,
                            nonce,
                            timestamp_ms,
                            is_todo,
                            is_completed,
                        }) => {
                            if delta_room_id == room_id {
                                if let Some(key_bytes) = self.get_room_key(&room_id).await {
                                    if let Ok(plaintext) = decrypt_shared_content(&ciphertext, &nonce, &key_bytes) {
                                        let _ = self.event_sender.send(P2pEvent::note_received(
                                            ulid,
                                            room_id.clone(),
                                            plaintext,
                                            author_id,
                                            timestamp_ms,
                                            is_todo,
                                            is_completed,
                                        ));
                                    }
                                }
                            }
                        }
                        Ok(_) => {}
                        Err(e) => {
                            eprintln!("Error reading packet from stream: {:#}", e);
                            break;
                        }
                    }
                }
                Err(_) => {
                    break;
                }
            }
        }

        {
            let mut peers = self.active_peers.write().await;
            if let Some(list) = peers.get_mut(&room_id) {
                list.retain(|c: &Connection| c.stable_id() != connection.stable_id());
            }
        }

        let _ = self.event_sender.send(P2pEvent::peer_disconnected(peer_id, room_id));

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

    /// Generate an invite ticket string for a room (encoded with node address & shared key)
    pub async fn generate_room_invite(&self, room_id: String, room_name: String) -> Result<String> {
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

        let direct_addrs: Vec<String> = node_addr
            .direct_addresses()
            .map(|addr| addr.to_string())
            .collect();

        let relay_url = node_addr.relay_url().map(|r| r.to_string());

        let payload = RoomInvitePayload {
            room_id,
            room_name,
            shared_key_b64: BASE64.encode(key_bytes),
            host_node_id: node_addr.node_id.to_string(),
            relay_url,
            direct_addrs,
        };

        let json = serde_json::to_string(&payload)?;
        let base64_invite = BASE64.encode(json.as_bytes());
        Ok(format!("notetosms://invite?data={}", base64_invite))
    }

    /// Parse invite payload, connect to peer, perform handshake, and register room
    pub async fn join_room_by_invite(&self, invite_payload: String) -> Result<RoomInvitePayload> {
        let cleaned = invite_payload
            .trim()
            .trim_start_matches("notetosms://invite?data=");

        let json_bytes = BASE64.decode(cleaned).context("Invalid base64 invite payload")?;
        let payload: RoomInvitePayload = serde_json::from_slice(&json_bytes).context("Invalid invite JSON structure")?;

        let key_bytes_vec = BASE64.decode(&payload.shared_key_b64).context("Invalid shared room key in invite")?;
        if key_bytes_vec.len() != 32 {
            return Err(anyhow!("Shared key length must be exactly 32 bytes"));
        }
        let mut key_bytes = [0u8; 32];
        key_bytes.copy_from_slice(&key_bytes_vec);

        self.register_shared_room(payload.room_id.clone(), key_bytes).await;

        let host_node_id: NodeId = payload.host_node_id.parse().context("Invalid host NodeId")?;
        let mut node_addr = NodeAddr::new(host_node_id);

        if let Some(ref relay_str) = payload.relay_url {
            if let Ok(relay_url) = relay_str.parse() {
                node_addr = node_addr.with_relay_url(relay_url);
            }
        }

        for addr_str in &payload.direct_addrs {
            if let Ok(sock_addr) = addr_str.parse() {
                node_addr = node_addr.with_direct_addresses(vec![sock_addr]);
            }
        }

        let connection: Connection = self
            .endpoint
            .connect(node_addr, P2P_ALPN)
            .await
            .context("Failed to connect to host peer via iroh")?;

        let (mut send, mut recv) = connection.open_bi().await.context("Failed to open handshake bi-stream")?;

        write_packet(
            &mut send,
            &P2pPacket::Handshake {
                peer_node_id: self.node_id().to_string(),
                room_id: payload.room_id.clone(),
            },
        )
        .await?;

        let ack = read_packet(&mut recv).await?;
        match ack {
            P2pPacket::HandshakeAck { accepted, status } => {
                if !accepted {
                    return Err(anyhow!("Handshake rejected by host: {}", status));
                }
            }
            _ => return Err(anyhow!("Unexpected response during handshake")),
        }

        {
            let mut peers = self.active_peers.write().await;
            peers.entry(payload.room_id.clone()).or_default().push(connection.clone());
        }

        let _ = self.event_sender.send(P2pEvent::peer_connected(payload.host_node_id.clone(), payload.room_id.clone()));

        let stream_node = self.clone();
        let stream_room_id = payload.room_id.clone();
        let stream_host_id = payload.host_node_id.clone();
        crate::get_runtime().spawn(async move {
            let _ = stream_node
                .process_incoming_streams(connection, stream_room_id, stream_host_id)
                .await;
        });

        Ok(payload)
    }

    /// Broadcast a note delta to all active peers connected to a shared room
    pub async fn broadcast_note(
        &self,
        room_id: &str,
        content: &str,
        is_todo: bool,
        is_completed: bool,
    ) -> Result<()> {
        let key_bytes = match self.get_room_key(room_id).await {
            Some(k) => k,
            None => return Ok(()),
        };

        let active_conns: Vec<Connection> = {
            let peers = self.active_peers.read().await;
            peers.get(room_id).cloned().unwrap_or_default()
        };

        if active_conns.is_empty() {
            return Ok(());
        }

        let (ciphertext, nonce) = encrypt_shared_content(content.as_bytes(), &key_bytes)?;
        let ulid = Ulid::new().to_string();
        let now_ms = chrono::Utc::now().timestamp_millis();

        let packet = P2pPacket::NoteDelta {
            ulid,
            room_id: room_id.to_string(),
            author_id: self.node_id().to_string(),
            ciphertext,
            nonce,
            timestamp_ms: now_ms,
            is_todo,
            is_completed,
        };

        for conn in active_conns {
            let pkt = packet.clone();
            crate::get_runtime().spawn(async move {
                if let Ok((mut send, _recv)) = conn.open_bi().await {
                    let _ = write_packet(&mut send, &pkt).await;
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

async fn write_packet(send: &mut SendStream, packet: &P2pPacket) -> Result<()> {
    let bytes = serde_json::to_vec(packet)?;
    let len = (bytes.len() as u32).to_be_bytes();
    send.write_all(&len).await?;
    send.write_all(&bytes).await?;
    send.finish()?;
    Ok(())
}

async fn read_packet(recv: &mut RecvStream) -> Result<P2pPacket> {
    let mut len_buf = [0u8; 4];
    recv.read_exact(&mut len_buf).await?;
    let len = u32::from_be_bytes(len_buf) as usize;

    if len > 10 * 1024 * 1024 {
        return Err(anyhow!("Packet size exceeds 10MB limit"));
    }

    let mut data_buf = vec![0u8; len];
    recv.read_exact(&mut data_buf).await?;

    let packet: P2pPacket = serde_json::from_slice(&data_buf)?;
    Ok(packet)
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

    #[test]
    fn test_ulid_generation_is_monotonic_and_sortable() {
        let ulid1 = Ulid::new().to_string();
        std::thread::sleep(std::time::Duration::from_millis(2));
        let ulid2 = Ulid::new().to_string();

        assert_ne!(ulid1, ulid2);
        assert!(ulid2 > ulid1);
    }

    #[tokio::test]
    async fn test_p2p_node_init_and_invite_generation() {
        let node = P2pNode::get_or_init().await.unwrap();
        let invite_uri = node
            .generate_room_invite("project-x".into(), "Project X".into())
            .await
            .unwrap();

        assert!(invite_uri.starts_with("notetosms://invite?data="));

        let payload_base64 = invite_uri.trim_start_matches("notetosms://invite?data=");
        let json_bytes = BASE64.decode(payload_base64).unwrap();
        let payload: RoomInvitePayload = serde_json::from_slice(&json_bytes).unwrap();

        assert_eq!(payload.room_id, "project-x");
        assert_eq!(payload.room_name, "Project X");
        assert!(!payload.shared_key_b64.is_empty());
        assert_eq!(payload.host_node_id, node.node_id().to_string());
    }
}
