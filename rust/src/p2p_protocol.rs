use iroh_net::NodeAddr;
use serde::{Deserialize, Serialize};
use crate::storage::NoteItem;

pub const TICKET_VERSION_COMPACT: u8 = 0x01;
pub const TICKET_MAGIC_V1: u8 = 0x54; // 'T'

pub fn hex_prefix(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

pub fn relay_url_to_index(url: Option<&iroh_net::relay::RelayUrl>) -> u8 {
    if let Some(u) = url {
        let s = u.to_string();
        if s.contains("use1-1") {
            1
        } else if s.contains("euw1-1") {
            2
        } else if s.contains("apse1-1") {
            3
        } else if s.contains("usw1-1") {
            4
        } else {
            1 // Default fallback to US East
        }
    } else {
        1 // Default to US East relay for hole-punching
    }
}

pub fn index_to_relay_url(index: u8) -> Option<iroh_net::relay::RelayUrl> {
    let url_str = match index {
        0 => return None,
        1 => "https://use1-1.relay.iroh.network./",
        2 => "https://euw1-1.relay.iroh.network./",
        3 => "https://apse1-1.relay.iroh.network./",
        4 => "https://usw1-1.relay.iroh.network./",
        _ => "https://use1-1.relay.iroh.network./",
    };
    url_str.parse().ok()
}

/// Combined thread invitation ticket containing cryptographic keys and network dialing info
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RoomShareTicket {
    pub room_id: String,
    pub room_name: String,
    pub encryption_key: String, // Base64 ChaCha20 key
    pub node_addr: NodeAddr,    // NodeId, RelayUrl, and Direct SocketAddrs
}

impl RoomShareTicket {
    /// Direct binary packing (66 Bytes Total):
    /// - Byte 0: Version (0x01)
    /// - Bytes 1..33: Host NodeId (32 raw bytes)
    /// - Bytes 33..65: ChaCha20 Secret Key (32 raw bytes)
    /// - Byte 65: Relay Index (1 byte)
    pub fn to_compact_66_bytes(&self) -> anyhow::Result<[u8; 66]> {
        use base64::engine::general_purpose::STANDARD as BASE64;
        use base64::Engine;

        let key_bytes = BASE64.decode(&self.encryption_key)
            .map_err(|e| anyhow::anyhow!("Invalid base64 encryption key: {e}"))?;
        if key_bytes.len() != 32 {
            return Err(anyhow::anyhow!("Encryption key must be 32 bytes"));
        }

        let mut buf = [0u8; 66];
        buf[0] = TICKET_VERSION_COMPACT;
        buf[1..33].copy_from_slice(self.node_addr.node_id.as_bytes());
        buf[33..65].copy_from_slice(&key_bytes);
        buf[65] = relay_url_to_index(self.node_addr.relay_url());

        Ok(buf)
    }

    /// Decode from 66-byte compact binary payload
    pub fn from_compact_66_bytes(bytes: &[u8]) -> anyhow::Result<Self> {
        use base64::engine::general_purpose::STANDARD as BASE64;
        use base64::Engine;

        if bytes.len() != 66 || bytes[0] != TICKET_VERSION_COMPACT {
            return Err(anyhow::anyhow!("Invalid 66-byte compact ticket payload"));
        }

        let mut node_id_bytes = [0u8; 32];
        node_id_bytes.copy_from_slice(&bytes[1..33]);
        let node_id = iroh_net::NodeId::from_bytes(&node_id_bytes)
            .map_err(|e| anyhow::anyhow!("Invalid NodeId in ticket: {e}"))?;

        let mut key_bytes = [0u8; 32];
        key_bytes.copy_from_slice(&bytes[33..65]);
        let encryption_key = BASE64.encode(key_bytes);

        let relay_index = bytes[65];
        let mut node_addr = NodeAddr::new(node_id);
        if let Some(relay_url) = index_to_relay_url(relay_index) {
            node_addr = node_addr.with_relay_url(relay_url);
        }

        // Temporary derived room_id from key fingerprint; will be updated via in-band HandshakeAck
        let room_id = format!("room-{}", &hex_prefix(&key_bytes[0..6]));
        let room_name = "Encrypted Thread".to_string();

        Ok(Self {
            room_id,
            room_name,
            encryption_key,
            node_addr,
        })
    }

    pub fn to_packed_bytes(&self) -> anyhow::Result<Vec<u8>> {
        use base64::engine::general_purpose::STANDARD as BASE64;
        use base64::Engine;
        use std::net::SocketAddr;

        let key_bytes = BASE64.decode(&self.encryption_key)
            .map_err(|e| anyhow::anyhow!("Invalid base64 encryption key: {e}"))?;
        if key_bytes.len() != 32 {
            return Err(anyhow::anyhow!("Encryption key must be 32 bytes"));
        }

        let mut buf = Vec::with_capacity(128);
        buf.push(TICKET_MAGIC_V1);
        buf.extend_from_slice(&key_bytes); // 32 bytes
        buf.extend_from_slice(self.node_addr.node_id.as_bytes()); // 32 bytes

        // Relay URL (length-prefixed)
        let relay_str = self.node_addr.relay_url().map(|r| r.to_string()).unwrap_or_default();
        let relay_bytes = relay_str.as_bytes();
        if relay_bytes.len() > 255 {
            return Err(anyhow::anyhow!("Relay URL too long"));
        }
        buf.push(relay_bytes.len() as u8);
        buf.extend_from_slice(relay_bytes);

        // Direct Addresses
        let direct_addrs: Vec<SocketAddr> = self.node_addr.direct_addresses().copied().collect();
        let addr_count = direct_addrs.len().min(10) as u8;
        buf.push(addr_count);
        for addr in direct_addrs.iter().take(addr_count as usize) {
            match addr {
                SocketAddr::V4(v4) => {
                    buf.push(4);
                    buf.extend_from_slice(&v4.ip().octets());
                    buf.extend_from_slice(&v4.port().to_be_bytes());
                }
                SocketAddr::V6(v6) => {
                    buf.push(6);
                    buf.extend_from_slice(&v6.ip().octets());
                    buf.extend_from_slice(&v6.port().to_be_bytes());
                }
            }
        }

        // Room ID (length-prefixed)
        let room_id_bytes = self.room_id.as_bytes();
        if room_id_bytes.len() > 255 {
            return Err(anyhow::anyhow!("Room ID too long"));
        }
        buf.push(room_id_bytes.len() as u8);
        buf.extend_from_slice(room_id_bytes);

        // Room Name (length-prefixed)
        let room_name_bytes = self.room_name.as_bytes();
        if room_name_bytes.len() > 255 {
            return Err(anyhow::anyhow!("Room name too long"));
        }
        buf.push(room_name_bytes.len() as u8);
        buf.extend_from_slice(room_name_bytes);

        Ok(buf)
    }

    pub fn from_packed_bytes(bytes: &[u8]) -> anyhow::Result<Self> {
        use base64::engine::general_purpose::STANDARD as BASE64;
        use base64::Engine;
        use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

        if bytes.len() < 66 || bytes[0] != TICKET_MAGIC_V1 {
            return Err(anyhow::anyhow!("Invalid packed ticket format"));
        }

        let mut offset = 1;
        let mut key_arr = [0u8; 32];
        key_arr.copy_from_slice(&bytes[offset..offset + 32]);
        offset += 32;
        let encryption_key = BASE64.encode(key_arr);

        let mut node_id_arr = [0u8; 32];
        node_id_arr.copy_from_slice(&bytes[offset..offset + 32]);
        offset += 32;
        let node_id = iroh_net::NodeId::from_bytes(&node_id_arr)
            .map_err(|e| anyhow::anyhow!("Invalid NodeId in ticket: {e}"))?;

        let mut node_addr = NodeAddr::new(node_id);

        if offset >= bytes.len() {
            return Err(anyhow::anyhow!("Unexpected EOF reading relay URL"));
        }
        let relay_len = bytes[offset] as usize;
        offset += 1;
        if relay_len > 0 {
            if offset + relay_len > bytes.len() {
                return Err(anyhow::anyhow!("Unexpected EOF reading relay URL string"));
            }
            let relay_str = std::str::from_utf8(&bytes[offset..offset + relay_len])?;
            offset += relay_len;
            if let Ok(relay_url) = relay_str.parse() {
                node_addr = node_addr.with_relay_url(relay_url);
            }
        }

        if offset >= bytes.len() {
            return Err(anyhow::anyhow!("Unexpected EOF reading direct addrs"));
        }
        let addr_count = bytes[offset] as usize;
        offset += 1;
        let mut direct_addrs = Vec::new();
        for _ in 0..addr_count {
            if offset >= bytes.len() {
                break;
            }
            let addr_type = bytes[offset];
            offset += 1;
            if addr_type == 4 {
                if offset + 6 > bytes.len() {
                    break;
                }
                let ip = Ipv4Addr::new(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3]);
                let port = u16::from_be_bytes([bytes[offset + 4], bytes[offset + 5]]);
                offset += 6;
                direct_addrs.push(SocketAddr::new(IpAddr::V4(ip), port));
            } else if addr_type == 6 {
                if offset + 18 > bytes.len() {
                    break;
                }
                let mut octets = [0u8; 16];
                octets.copy_from_slice(&bytes[offset..offset + 16]);
                let ip = Ipv6Addr::from(octets);
                let port = u16::from_be_bytes([bytes[offset + 16], bytes[offset + 17]]);
                offset += 18;
                direct_addrs.push(SocketAddr::new(IpAddr::V6(ip), port));
            }
        }
        if !direct_addrs.is_empty() {
            node_addr = node_addr.with_direct_addresses(direct_addrs);
        }

        // Room ID
        if offset >= bytes.len() {
            return Err(anyhow::anyhow!("Unexpected EOF reading room ID"));
        }
        let room_id_len = bytes[offset] as usize;
        offset += 1;
        if offset + room_id_len > bytes.len() {
            return Err(anyhow::anyhow!("Unexpected EOF reading room ID string"));
        }
        let room_id = std::str::from_utf8(&bytes[offset..offset + room_id_len])?.to_string();
        offset += room_id_len;

        // Room Name
        let room_name = if offset < bytes.len() {
            let name_len = bytes[offset] as usize;
            offset += 1;
            if offset + name_len <= bytes.len() {
                std::str::from_utf8(&bytes[offset..offset + name_len])?.to_string()
            } else {
                room_id.clone()
            }
        } else {
            room_id.clone()
        };

        Ok(Self {
            room_id,
            room_name,
            encryption_key,
            node_addr,
        })
    }
}

/// Unified ticket decoder supporting 66-byte Base58, 66-byte Base64 URL, v1 packed binary, Zlib JSON, and legacy JSON
pub fn decode_ticket_payload(cleaned: &str) -> anyhow::Result<RoomShareTicket> {
    use base64::engine::general_purpose::{URL_SAFE_NO_PAD, URL_SAFE, STANDARD, STANDARD_NO_PAD};
    use base64::Engine;

    // 1. Try Base58 (66 bytes compact)
    if let Ok(bytes) = bs58::decode(cleaned).into_vec() {
        if bytes.len() == 66 && bytes[0] == TICKET_VERSION_COMPACT {
            return RoomShareTicket::from_compact_66_bytes(&bytes);
        }
    }

    // 2. Try URL-Safe Base64 (No Pad and Standard)
    let b64_bytes = URL_SAFE_NO_PAD.decode(cleaned)
        .or_else(|_| URL_SAFE.decode(cleaned))
        .or_else(|_| STANDARD_NO_PAD.decode(cleaned))
        .or_else(|_| STANDARD.decode(cleaned));

    if let Ok(bytes) = b64_bytes {
        // 2a. Check if 66 bytes compact (Version 0x01)
        if bytes.len() == 66 && bytes[0] == TICKET_VERSION_COMPACT {
            return RoomShareTicket::from_compact_66_bytes(&bytes);
        }

        // 2b. Check if v1 binary packed (Magic 0x54)
        if !bytes.is_empty() && bytes[0] == TICKET_MAGIC_V1 {
            if let Ok(t) = RoomShareTicket::from_packed_bytes(&bytes) {
                return Ok(t);
            }
        }

        // 2c. Check if Zlib compressed JSON
        use std::io::Read;
        let mut decoder = flate2::read::ZlibDecoder::new(bytes.as_slice());
        let mut buf = Vec::new();
        if decoder.read_to_end(&mut buf).is_ok() && !buf.is_empty() {
            if let Ok(t) = serde_json::from_slice::<RoomShareTicket>(&buf) {
                return Ok(t);
            }
        }

        // 2d. Check if raw JSON RoomShareTicket
        if let Ok(t) = serde_json::from_slice::<RoomShareTicket>(&bytes) {
            return Ok(t);
        }

        // 2e. Check if legacy RoomInvitePayload
        if let Ok(legacy) = serde_json::from_slice::<crate::p2p::RoomInvitePayload>(&bytes) {
            let host_node_id: iroh_net::NodeId = legacy.host_node_id.parse().map_err(|e| anyhow::anyhow!("Invalid host NodeId in legacy invite: {e}"))?;
            let mut node_addr = NodeAddr::new(host_node_id);

            if let Some(ref relay_str) = legacy.relay_url {
                if let Ok(relay_url) = relay_str.parse::<iroh_net::relay::RelayUrl>() {
                    node_addr = node_addr.with_relay_url(relay_url);
                }
            }

            for addr_str in &legacy.direct_addrs {
                if let Ok(sock_addr) = addr_str.parse::<std::net::SocketAddr>() {
                    node_addr = node_addr.with_direct_addresses(vec![sock_addr]);
                }
            }

            return Ok(RoomShareTicket {
                room_id: legacy.room_id,
                room_name: legacy.room_name,
                encryption_key: legacy.shared_key_b64,
                node_addr,
            });
        }
    }

    Err(anyhow::anyhow!("Unrecognized or corrupted ticket format"))
}

/// Encrypted note payload transferred over the P2P wire
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct EncryptedNotePayload {
    pub id: String,
    pub room_id: String,
    pub ciphertext: Vec<u8>,
    pub nonce: [u8; 12],
    pub timestamp_ms: i64,
    pub is_todo: bool,
    pub is_completed: bool,
    pub is_pinned: bool,
    pub tags: Vec<String>,
    pub author_id: Option<String>,
    pub author_name: Option<String>,
}

/// Bidirectional P2P sync packet exchanged between peers over Iroh streams
#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum SyncPacket {
    // Handshake
    Handshake {
        peer_node_id: String,
        room_id: String,
        display_name: String,
        key_fingerprint: Option<String>,
    },
    HandshakeAck {
        accepted: bool,
        status: String,
        host_node_id: String,
        display_name: String,
        room_id: Option<String>,
        room_name: Option<String>,
    },
    // Catch-up sync
    RequestHistory {
        room_id: String,
        last_synced_timestamp: i64,
    },
    HistoryResponse {
        room_id: String,
        notes: Vec<EncryptedNotePayload>,
    },
    // Live events
    BroadcastNote {
        room_id: String,
        note: EncryptedNotePayload,
    },
    TypingEvent {
        room_id: String,
        peer_id: String,
        is_typing: bool,
    },
    PeerJoin {
        room_id: String,
        peer_id: String,
        display_name: String,
    },
    PresenceHeartbeat {
        room_id: String,
        peer_id: String,
        timestamp: i64,
    },
    PresenceHeartbeatAck {
        room_id: String,
        peer_id: String,
    },
    PeerDisconnecting {
        room_id: String,
        peer_id: String,
    },
}

/// Rich room event streamed across FRB to Flutter for live UI updates
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RoomEvent {
    pub event_type: String, // "note_received", "peer_joined", "peer_left", "remote_typing", "active_peer_count"
    pub room_id: String,
    pub note: Option<NoteItem>,
    pub peer_id: Option<String>,
    pub display_name: Option<String>,
    pub is_typing: Option<bool>,
    pub total_members: i32,
    pub active_online: i32,
}

impl RoomEvent {
    pub fn note_received(
        room_id: String,
        note: NoteItem,
        peer_id: Option<String>,
        display_name: Option<String>,
    ) -> Self {
        Self {
            event_type: "note_received".into(),
            room_id,
            note: Some(note),
            peer_id,
            display_name,
            is_typing: None,
            total_members: 0,
            active_online: 0,
        }
    }

    pub fn peer_joined(room_id: String, peer_id: String, display_name: String) -> Self {
        Self {
            event_type: "peer_joined".into(),
            room_id,
            note: None,
            peer_id: Some(peer_id),
            display_name: Some(display_name),
            is_typing: None,
            total_members: 0,
            active_online: 0,
        }
    }

    pub fn peer_left(room_id: String, peer_id: String) -> Self {
        Self {
            event_type: "peer_left".into(),
            room_id,
            note: None,
            peer_id: Some(peer_id),
            display_name: None,
            is_typing: None,
            total_members: 0,
            active_online: 0,
        }
    }

    pub fn remote_typing(room_id: String, peer_id: String, is_typing: bool) -> Self {
        Self {
            event_type: "remote_typing".into(),
            room_id,
            note: None,
            peer_id: Some(peer_id),
            display_name: None,
            is_typing: Some(is_typing),
            total_members: 0,
            active_online: 0,
        }
    }

    pub fn active_peer_count(room_id: String, total_members: i32, active_online: i32) -> Self {
        Self {
            event_type: "active_peer_count".into(),
            room_id,
            note: None,
            peer_id: None,
            display_name: None,
            is_typing: None,
            total_members,
            active_online,
        }
    }
}
