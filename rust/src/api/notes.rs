use std::sync::Mutex;
use anyhow::{anyhow, Result};
use crate::frb_generated::StreamSink;

pub use crate::p2p::P2pEvent;
use crate::p2p::P2pNode;
pub use crate::storage::{NoteItem, RoomInvite, RoomItem, VaultStatus};
use crate::storage::EncryptedStore;

static GLOBAL_STORE: Mutex<Option<EncryptedStore>> = Mutex::new(None);
const DEFAULT_DB_PATH: &str = "notetosms_vault.db";

fn with_store<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&mut EncryptedStore) -> Result<R>,
{
    let mut guard = GLOBAL_STORE
        .lock()
        .map_err(|e| anyhow!("Store lock failed: {e}"))?;

    let store = guard
        .as_mut()
        .ok_or_else(|| anyhow!("Vault store not initialized. Call init_vault first."))?;

    f(store)
}

/// Initialize or unlock vault at a specified custom database file path.
pub fn init_vault_at_path(db_path: String, passphrase: String) -> Result<VaultStatus> {
    let mut guard = GLOBAL_STORE
        .lock()
        .map_err(|e| anyhow!("Store lock failed: {e}"))?;

    let path = if db_path.trim().is_empty() {
        DEFAULT_DB_PATH.to_string()
    } else {
        db_path
    };

    let mut store = EncryptedStore::open(&path)?;
    store.unlock_or_init(&passphrase)?;
    let status = store.get_vault_status()?;

    *guard = Some(store);
    Ok(status)
}

/// Initialize or unlock vault using default path.
pub fn init_vault(passphrase: String) -> Result<()> {
    init_vault_at_path(DEFAULT_DB_PATH.to_string(), passphrase)?;
    Ok(())
}

/// Get the current status of the vault (initialization state, lock state, db path).
pub fn get_vault_status() -> Result<VaultStatus> {
    let guard = GLOBAL_STORE
        .lock()
        .map_err(|e| anyhow!("Store lock failed: {e}"))?;

    if let Some(store) = guard.as_ref() {
        store.get_vault_status()
    } else {
        Ok(VaultStatus {
            is_initialized: false,
            is_unlocked: false,
            db_path: DEFAULT_DB_PATH.to_string(),
        })
    }
}

/// Lock the vault and securely wipe the derived Argon2 / ChaCha20 key from memory.
pub fn lock_vault() -> Result<()> {
    let mut guard = GLOBAL_STORE
        .lock()
        .map_err(|e| anyhow!("Store lock failed: {e}"))?;

    if let Some(store) = guard.as_mut() {
        store.lock()?;
    }
    Ok(())
}

/// Change master passphrase, re-encrypting all notes with a new Argon2 salt and key.
pub fn change_passphrase(old_pass: String, new_pass: String) -> Result<()> {
    with_store(|store| store.change_passphrase(&old_pass, &new_pass))
}

/// Create and encrypt a new note in the specified room, and broadcast to active P2P peers if shared.
pub fn save_note(room_id: String, content: String) -> Result<NoteItem> {
    let note = with_store(|store| store.save_note(&room_id, &content))?;

    let r_id = room_id.clone();
    let text = content.clone();
    tokio::spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            let _ = node.broadcast_note(&r_id, &text, false, false).await;
        }
    });

    Ok(note)
}

/// Update an existing note's content and re-encrypt.
pub fn update_note(note_id: String, content: String) -> Result<NoteItem> {
    with_store(|store| store.update_note(&note_id, &content))
}

/// Toggle completion status of a todo note item, broadcasting to active P2P peers if shared.
pub fn toggle_todo(note_id: String, is_completed: bool) -> Result<NoteItem> {
    let updated = with_store(|store| store.toggle_todo(&note_id, is_completed))?;

    let r_id = updated.room_id.clone();
    let text = updated.content.clone();
    tokio::spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            let _ = node.broadcast_note(&r_id, &text, true, is_completed).await;
        }
    });

    Ok(updated)
}

/// Pin or unpin a note to the top of its room.
pub fn pin_note(note_id: String, is_pinned: bool) -> Result<NoteItem> {
    with_store(|store| store.pin_note(&note_id, is_pinned))
}

/// Permanently delete an encrypted note from the database.
pub fn delete_note(note_id: String) -> Result<()> {
    with_store(|store| store.delete_note(&note_id))
}

/// Fetch and decrypt all notes for a given room.
pub fn get_notes(room_id: String) -> Result<Vec<NoteItem>> {
    with_store(|store| store.get_notes(&room_id))
}

/// Perform lightning-fast full-text search across decrypted note index.
pub fn search_notes(query: String, room_id_filter: Option<String>) -> Result<Vec<NoteItem>> {
    with_store(|store| store.search_notes(&query, room_id_filter.as_deref()))
}

/// List all available note rooms / channels.
pub fn list_rooms() -> Result<Vec<RoomItem>> {
    with_store(|store| store.list_rooms())
}

/// Create a new customized room / channel.
pub fn create_room(id: String, name: String, icon: String, color: u32) -> Result<RoomItem> {
    with_store(|store| store.create_room(&id, &name, &icon, color))
}

/// Delete a room and its associated notes.
pub fn delete_room(room_id: String) -> Result<()> {
    with_store(|store| store.delete_room(&room_id))
}

/// Export a shareable room invite token/URI for a note channel.
pub fn export_room_invite(room_id: String) -> Result<String> {
    with_store(|store| store.export_room_invite(&room_id))
}

/// Parse a room invite URI / token without joining.
pub fn parse_room_invite(invite_data: String) -> Result<RoomInvite> {
    with_store(|store| store.parse_room_invite(&invite_data))
}

/// Import and join a note room using an invite token / URI.
pub fn import_room_invite(invite_data: String) -> Result<RoomItem> {
    with_store(|store| store.import_room_invite(&invite_data))
}

// ---------------------------------------------------------------------------
// P2P Peer-to-Peer Synchronization APIs
// ---------------------------------------------------------------------------

/// Start or initialize the local Iroh P2P node and return its NodeId string.
pub async fn start_p2p_node() -> Result<String> {
    let node = P2pNode::get_or_init().await?;
    Ok(node.node_id().to_string())
}

/// Generate a shareable invite URI / QR payload for a room with an encrypted shared key.
pub async fn generate_room_invite(room_id: String, room_name: String) -> Result<String> {
    let node = P2pNode::get_or_init().await?;
    node.generate_room_invite(room_id, room_name).await
}

/// Join a shared note room using a peer's invite URI / QR payload.
pub async fn join_room_by_invite(invite_payload: String) -> Result<RoomItem> {
    let node = P2pNode::get_or_init().await?;
    let payload = node.join_room_by_invite(invite_payload).await?;

    let room = with_store(|store| {
        let existing = store.list_rooms()?;
        if let Some(r) = existing.into_iter().find(|r| r.id == payload.room_id) {
            Ok(r)
        } else {
            store.create_room(&payload.room_id, &payload.room_name, "chat_bubble", 0xFF6366F1)
        }
    })?;

    Ok(room)
}

/// Subscribe to P2P network events (peer connection, disconnection, incoming notes)
pub async fn subscribe_p2p_events(sink: StreamSink<P2pEvent>) -> Result<()> {
    let node = P2pNode::get_or_init().await?;
    let mut rx = node.subscribe_events();

    tokio::spawn(async move {
        while let Ok(event) = rx.recv().await {
            if event.event_type == "note_received" {
                if let (Some(ref r_id), Some(ref cnt)) = (&event.room_id, &event.content) {
                    let _ = with_store(|store| store.save_note(r_id, cnt));
                }
            }

            if sink.add(event).is_err() {
                break;
            }
        }
    });

    Ok(())
}
