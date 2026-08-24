use std::sync::Mutex;
use anyhow::{anyhow, Result};

pub use crate::storage::{NoteItem, RoomItem, VaultStatus};
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

/// Create and encrypt a new note in the specified room.
pub fn save_note(room_id: String, content: String) -> Result<NoteItem> {
    with_store(|store| store.save_note(&room_id, &content))
}

/// Update an existing note's content and re-encrypt.
pub fn update_note(note_id: String, content: String) -> Result<NoteItem> {
    with_store(|store| store.update_note(&note_id, &content))
}

/// Toggle completion status of a todo note item.
pub fn toggle_todo(note_id: String, is_completed: bool) -> Result<NoteItem> {
    with_store(|store| store.toggle_todo(&note_id, is_completed))
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
