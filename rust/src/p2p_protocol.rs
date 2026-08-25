use iroh_net::NodeAddr;
use serde::{Deserialize, Serialize};
use crate::storage::NoteItem;

/// Combined thread invitation ticket containing cryptographic keys and network dialing info
#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RoomShareTicket {
    pub room_id: String,
    pub room_name: String,
    pub encryption_key: String, // Base64 ChaCha20 key
    pub node_addr: NodeAddr,    // NodeId, RelayUrl, and Direct SocketAddrs
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
}

/// Bidirectional P2P sync packet exchanged between peers over Iroh streams
#[derive(Serialize, Deserialize, Debug, Clone)]
pub enum SyncPacket {
    // Handshake
    Handshake {
        peer_node_id: String,
        room_id: String,
        display_name: String,
    },
    HandshakeAck {
        accepted: bool,
        status: String,
        host_node_id: String,
        display_name: String,
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
