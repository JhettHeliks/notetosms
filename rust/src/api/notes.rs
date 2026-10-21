use std::sync::Mutex;
use anyhow::{anyhow, Result};
use crate::frb_generated::StreamSink;

pub use crate::p2p::P2pEvent;
use crate::p2p::P2pNode;
pub use crate::p2p_protocol::RoomEvent;
pub use crate::storage::{NoteItem, RoomInvite, RoomItem, SharedRoomInfo, UserProfile, VaultStatus};
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

/// Helper called by P2P sync engine to query notes for history sync
pub(crate) fn get_notes_for_history(room_id: &str, since_timestamp: i64) -> Result<Vec<NoteItem>> {
    with_store(|store| store.get_notes_since(room_id, since_timestamp))
}

/// Helper called by P2P sync engine to upsert received notes into local encrypted SQLite store
pub(crate) fn upsert_synced_note(
    id: &str,
    room_id: &str,
    content: &str,
    timestamp_ms: i64,
    is_todo: bool,
    is_completed: bool,
    is_pinned: bool,
    author_id: Option<&str>,
    author_name: Option<&str>,
) -> Result<NoteItem> {
    with_store(|store| {
        store.upsert_remote_note(
            id,
            room_id,
            content,
            timestamp_ms,
            is_todo,
            is_completed,
            is_pinned,
            author_id,
            author_name,
        )
    })
}

pub(crate) fn upsert_room(
    id: &str,
    name: &str,
    icon: &str,
    color: u32,
) -> Result<RoomItem> {
    with_store(|store| store.upsert_room(id, name, icon, color))
}

/// Get user profile
pub fn get_user_profile() -> Result<UserProfile> {
    with_store(|store| store.get_user_profile())
}

/// Save user profile
pub fn save_user_profile(display_name: String, avatar_color: u32, avatar_icon: String) -> Result<()> {
    with_store(|store| {
        store.save_user_profile(&UserProfile {
            display_name: display_name.clone(),
            avatar_color,
            avatar_icon,
        })?;
        Ok(())
    })?;

    // Update live P2P node display name
    crate::get_runtime().spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            node.set_display_name(display_name).await;
        }
    });

    Ok(())
}

/// Set per-thread background P2P sync toggle
pub fn set_room_background_sync(room_id: String, enabled: bool) -> Result<()> {
    with_store(|store| store.set_room_background_sync(&room_id, enabled))
}

/// Save room encryption details and share ticket in vault
pub fn save_room_encryption_details(room_id: String, encryption_key: String, share_ticket: Option<String>) -> Result<()> {
    with_store(|store| store.save_room_encryption_details(&room_id, &encryption_key, share_ticket.as_deref()))
}

/// Query shared rooms with encryption keys for auto-restore
pub fn get_shared_rooms_with_keys() -> Result<Vec<SharedRoomInfo>> {
    with_store(|store| store.get_shared_rooms_with_keys())
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

    // Automatically boot P2P network, re-register shared room keys, and reconnect active threads
    crate::get_runtime().spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            let _ = node.boot_p2p_network().await;
        }
    });

    Ok(status)
}

/// Initialize or unlock vault using default path.
pub fn init_vault(passphrase: String) -> Result<()> {
    init_vault_at_path(DEFAULT_DB_PATH.to_string(), passphrase)?;
    Ok(())
}

/// Check whether the vault database exists on disk and contains a valid database header/salt.
pub fn is_vault_initialized(db_path: Option<String>) -> bool {
    // 1. If an active store is in memory, check it first
    if let Ok(guard) = GLOBAL_STORE.lock() {
        if let Some(store) = guard.as_ref() {
            if let Ok(init) = store.is_vault_initialized() {
                if init {
                    return true;
                }
            }
        }
    }

    // 2. Check the provided db_path if specified
    if let Some(ref path) = db_path {
        if !path.trim().is_empty() {
            return crate::storage::check_vault_file_initialized(path);
        }
    }

    // 3. Fallback to default path or chat_notes.db
    if crate::storage::check_vault_file_initialized(DEFAULT_DB_PATH) {
        return true;
    }
    if crate::storage::check_vault_file_initialized("chat_notes.db") {
        return true;
    }

    false
}

/// Get the current status of the vault (initialization state, lock state, db path).
pub fn get_vault_status() -> Result<VaultStatus> {
    let guard = GLOBAL_STORE
        .lock()
        .map_err(|e| anyhow!("Store lock failed: {e}"))?;

    if let Some(store) = guard.as_ref() {
        store.get_vault_status()
    } else {
        let is_init = crate::storage::check_vault_file_initialized(DEFAULT_DB_PATH)
            || crate::storage::check_vault_file_initialized("chat_notes.db");
        Ok(VaultStatus {
            is_initialized: is_init,
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
    let note_clone = note.clone();
    crate::get_runtime().spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            let _ = node.broadcast_note_item(&r_id, &note_clone).await;
        }
    });

    Ok(note)
}

/// Update an existing note's content and re-encrypt, broadcasting to active P2P peers.
pub fn update_note(note_id: String, content: String) -> Result<NoteItem> {
    let updated = with_store(|store| store.update_note(&note_id, &content))?;

    let r_id = updated.room_id.clone();
    let note_clone = updated.clone();
    crate::get_runtime().spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            let _ = node.broadcast_note_item(&r_id, &note_clone).await;
        }
    });

    Ok(updated)
}

/// Toggle completion status of a todo note item, broadcasting to active P2P peers if shared.
pub fn toggle_todo(note_id: String, is_completed: bool) -> Result<NoteItem> {
    let updated = with_store(|store| store.toggle_todo(&note_id, is_completed))?;

    let r_id = updated.room_id.clone();
    let note_clone = updated.clone();
    crate::get_runtime().spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            let _ = node.broadcast_note_item(&r_id, &note_clone).await;
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

/// Get a room by its ID.
pub fn get_room_by_id(room_id: &str) -> Result<RoomItem> {
    with_store(|store| store.get_room(room_id))
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
// Backup & Export / Restore APIs
// ---------------------------------------------------------------------------

/// Export an encrypted SQLite vault database snapshot to destination path.
pub fn export_encrypted_backup(destination_path: String) -> Result<()> {
    with_store(|store| store.export_encrypted_backup(&destination_path))
}

/// Export decrypted plaintext notes and room metadata as structured JSON to destination path.
pub fn export_unencrypted_backup(destination_path: String) -> Result<()> {
    with_store(|store| store.export_unencrypted_backup(&destination_path))
}

/// Import a backup (encrypted database or plaintext JSON) with transaction safety.
pub fn import_backup(source_path: String, passphrase: Option<String>) -> Result<()> {
    with_store(|store| store.import_backup(&source_path, passphrase))
}

// ---------------------------------------------------------------------------
// P2P Peer-to-Peer Synchronization APIs
// ---------------------------------------------------------------------------

/// Start or initialize the local Iroh P2P node and return its NodeId string.
pub async fn start_p2p_node() -> Result<String> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        Ok::<String, anyhow::Error>(node.node_id().to_string())
    });
    handle.await?
}

/// Set the local device display name for P2P presence.
pub async fn set_p2p_display_name(display_name: String) -> Result<()> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        node.set_display_name(display_name).await;
        Ok::<(), anyhow::Error>(())
    });
    handle.await?
}

/// Get the local device display name.
pub async fn get_p2p_display_name() -> Result<String> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        Ok::<String, anyhow::Error>(node.get_display_name().await)
    });
    handle.await?
}

/// Export a combined invitation ticket containing encryption key and network dialing address.
pub async fn export_room_ticket(room_id: String) -> Result<String> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        let room_name = with_store(|store| {
            let rooms = store.list_rooms()?;
            let name = rooms
                .into_iter()
                .find(|r| r.id == room_id)
                .map(|r| r.name)
                .unwrap_or_else(|| room_id.clone());
            Ok(name)
        })?;

        node.export_room_ticket(room_id, room_name).await
    });
    handle.await?
}

/// Import a combined invitation ticket, persist room in local SQLite, and dial peer.
pub async fn import_room_ticket(ticket: String) -> Result<RoomItem> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        let ticket_obj = node.import_room_ticket(ticket).await?;

        let room = with_store(|store| {
            store.upsert_room(
                &ticket_obj.room_id,
                &ticket_obj.room_name,
                "chat_bubble",
                0xFF6366F1,
            )
        })?;

        Ok::<RoomItem, anyhow::Error>(room)
    });
    handle.await?
}

/// Generate a shareable invite URI / QR payload for a room with an encrypted shared key.
pub async fn generate_room_invite(room_id: String, _room_name: String) -> Result<String> {
    export_room_ticket(room_id).await
}

/// Generate a remote P2P sync ticket for a room using Iroh.
pub async fn generate_sync_ticket(room_id: String) -> Result<String> {
    export_room_ticket(room_id).await
}

/// Join a shared note room using a peer's invite URI / QR payload.
pub async fn join_room_by_invite(invite_payload: String) -> Result<RoomItem> {
    import_room_ticket(invite_payload).await
}

/// Connect to a remote peer and synchronize a room using an Iroh sync ticket.
pub async fn connect_sync_ticket(ticket: String) -> Result<()> {
    import_room_ticket(ticket).await.map(|_| ())
}

/// Send live typing indicator status for a room across connected P2P peers.
pub async fn send_typing_status(room_id: String, is_typing: bool) -> Result<()> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        node.broadcast_typing(&room_id, is_typing).await?;
        Ok::<(), anyhow::Error>(())
    });
    handle.await?
}

/// Subscribe to rich live room events (incoming notes, peer joins/leaves, typing, peer count)
pub async fn subscribe_room_events(room_id: String, sink: StreamSink<RoomEvent>) -> Result<()> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        let mut rx = node.subscribe_room_events(&room_id).await;

        // Emit current active peer count immediately
        let (total, online) = node.get_peer_counts(&room_id).await;
        let _ = sink.add(RoomEvent::active_peer_count(
            room_id.clone(),
            total,
            online,
        ));

        crate::get_runtime().spawn(async move {
            while let Ok(event) = rx.recv().await {
                if sink.add(event).is_err() {
                    break;
                }
            }
        });

        Ok::<(), anyhow::Error>(())
    });
    handle.await?
}

/// Subscribe to legacy P2P network events
pub async fn subscribe_p2p_events(sink: StreamSink<P2pEvent>) -> Result<()> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        let mut rx = node.subscribe_legacy_events();

        crate::get_runtime().spawn(async move {
            while let Ok(event) = rx.recv().await {
                if sink.add(event).is_err() {
                    break;
                }
            }
        });

        Ok::<(), anyhow::Error>(())
    });
    handle.await?
}

/// Get the local P2P NodeId
pub async fn get_local_node_id() -> Result<String> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        Ok::<String, anyhow::Error>(node.node_id().to_string())
    });
    handle.await?
}

/// Automatically re-hydrate P2P network, re-register all shared room keys, and dial active threads
pub async fn boot_p2p_network() -> Result<()> {
    let handle = crate::get_runtime().spawn(async move {
        let node = P2pNode::get_or_init().await?;
        node.boot_p2p_network().await
    });
    handle.await?
}

/// Gracefully signal disconnect to all connected peers and close active connections
pub async fn disconnect_all_peers() -> Result<()> {
    let handle = crate::get_runtime().spawn(async move {
        if let Ok(node) = P2pNode::get_or_init().await {
            node.disconnect_all_peers().await;
        }
        Ok::<(), anyhow::Error>(())
    });
    handle.await?
}

