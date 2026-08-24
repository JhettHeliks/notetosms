use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use rand::RngCore;
use rusqlite::{params, Connection, OptionalExtension};
use zeroize::Zeroizing;

use crate::crypto::{
    decrypt_payload, derive_key, encrypt_payload, generate_salt, KEY_LEN, NONCE_LEN, SALT_LEN,
};

const VERIFY_MAGIC_PLAINTEXT: &[u8] = b"CHATNOTES_ENCRYPTED_VAULT_V1_OK";
const CURRENT_SCHEMA_VERSION: i32 = 1;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct NoteItem {
    pub id: String,
    pub room_id: String,
    pub content: String,
    pub timestamp_ms: i64,
    pub is_todo: bool,
    pub is_completed: bool,
    pub is_pinned: bool,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RoomItem {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color: u32,
    pub created_at: i64,
    pub sort_order: i32,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VaultStatus {
    pub is_initialized: bool,
    pub is_unlocked: bool,
    pub db_path: String,
}

pub struct EncryptedStore {
    conn: Connection,
    active_key: Option<Zeroizing<[u8; KEY_LEN]>>,
    db_path: String,
}

impl EncryptedStore {
    /// Open or create the database at `db_path`.
    pub fn open<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let path_str = db_path.as_ref().to_string_lossy().to_string();
        let conn = Connection::open(&db_path)
            .map_err(|e| anyhow!("Failed to open SQLite database at {path_str}: {e}"))?;

        // Enable foreign keys and WAL mode for high performance
        conn.pragma_update(None, "foreign_keys", "ON")?;
        let _ = conn.pragma_update(None, "journal_mode", "WAL");

        let mut store = Self {
            conn,
            active_key: None,
            db_path: path_str,
        };

        store.init_tables()?;
        Ok(store)
    }

    /// Open in-memory database for testing.
    pub fn open_in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()
            .map_err(|e| anyhow!("Failed to open in-memory SQLite: {e}"))?;
        conn.pragma_update(None, "foreign_keys", "ON")?;

        let mut store = Self {
            conn,
            active_key: None,
            db_path: ":memory:".to_string(),
        };

        store.init_tables()?;
        Ok(store)
    }

    fn init_tables(&mut self) -> Result<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS vault_metadata (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                salt BLOB NOT NULL,
                verify_ciphertext BLOB NOT NULL,
                verify_nonce BLOB NOT NULL,
                created_at INTEGER NOT NULL,
                schema_version INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS rooms (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                icon TEXT NOT NULL DEFAULT 'chat_bubble',
                color INTEGER NOT NULL DEFAULT 4284704511,
                created_at INTEGER NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS notes (
                id TEXT PRIMARY KEY,
                room_id TEXT NOT NULL,
                ciphertext BLOB NOT NULL,
                nonce BLOB NOT NULL,
                timestamp_ms INTEGER NOT NULL,
                is_todo INTEGER NOT NULL DEFAULT 0,
                is_completed INTEGER NOT NULL DEFAULT 0,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                tags TEXT NOT NULL DEFAULT '',
                FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_notes_room_timestamp ON notes(room_id, timestamp_ms);
            CREATE INDEX IF NOT EXISTS idx_notes_pinned ON notes(is_pinned);
            "#,
        )?;
        Ok(())
    }

    pub fn is_vault_initialized(&self) -> Result<bool> {
        let count: i64 = self.conn.query_row(
            "SELECT COUNT(*) FROM vault_metadata WHERE id = 1",
            [],
            |r| r.get(0),
        )?;
        Ok(count > 0)
    }

    pub fn is_unlocked(&self) -> bool {
        self.active_key.is_some()
    }

    pub fn get_vault_status(&self) -> Result<VaultStatus> {
        Ok(VaultStatus {
            is_initialized: self.is_vault_initialized()?,
            is_unlocked: self.is_unlocked(),
            db_path: self.db_path.clone(),
        })
    }

    /// Unlock an existing vault with passphrase, or initialize if fresh.
    pub fn unlock_or_init(&mut self, passphrase: &str) -> Result<()> {
        if passphrase.trim().is_empty() {
            return Err(anyhow!("Passphrase cannot be empty"));
        }

        let is_initialized = self.is_vault_initialized()?;

        if !is_initialized {
            // Fresh database: generate salt, derive key, store metadata & default rooms
            let salt = generate_salt();
            let key = derive_key(passphrase, &salt)?;
            let (verify_ciphertext, verify_nonce) = encrypt_payload(&key, VERIFY_MAGIC_PLAINTEXT)?;
            let now = current_time_ms();

            self.conn.execute(
                "INSERT INTO vault_metadata (id, salt, verify_ciphertext, verify_nonce, created_at, schema_version)
                 VALUES (1, ?1, ?2, ?3, ?4, ?5)",
                params![salt.to_vec(), verify_ciphertext, verify_nonce.to_vec(), now, CURRENT_SCHEMA_VERSION],
            )?;

            // Seed initial rooms
            self.seed_default_rooms(now)?;

            self.active_key = Some(key);
            self.init_temp_fts()?;
        } else {
            // Existing vault: load salt and verify passphrase
            let (salt_vec, verify_ciphertext, verify_nonce_vec): (Vec<u8>, Vec<u8>, Vec<u8>) = self
                .conn
                .query_row(
                    "SELECT salt, verify_ciphertext, verify_nonce FROM vault_metadata WHERE id = 1",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .context("Failed to load vault metadata")?;

            if salt_vec.len() < SALT_LEN || verify_nonce_vec.len() < NONCE_LEN {
                return Err(anyhow!("Corrupted vault metadata in database"));
            }

            let key = derive_key(passphrase, &salt_vec)?;
            let mut nonce = [0u8; NONCE_LEN];
            nonce.copy_from_slice(&verify_nonce_vec[..NONCE_LEN]);

            let decrypted = decrypt_payload(&key, &verify_ciphertext, &nonce)
                .map_err(|_| anyhow!("Incorrect passphrase. Vault remains locked."))?;

            if decrypted.as_slice() != VERIFY_MAGIC_PLAINTEXT {
                return Err(anyhow!("Vault verification failed. Invalid key."));
            }

            self.active_key = Some(key);
            self.init_temp_fts()?;
            self.rebuild_temp_fts()?;
        }

        Ok(())
    }

    /// Seed default rooms if empty
    fn seed_default_rooms(&mut self, now: i64) -> Result<()> {
        let count: i64 = self.conn.query_row("SELECT COUNT(*) FROM rooms", [], |r| r.get(0))?;
        if count == 0 {
            let default_rooms: [(&str, &str, &str, u32, i32); 4] = [
                ("general", "General", "chat_bubble", 0xFF6366F1, 0),
                ("personal", "Personal", "lock", 0xFF10B981, 1),
                ("ideas", "Ideas", "lightbulb", 0xFFF59E0B, 2),
                ("secure-vault", "Vault Secrets", "security", 0xFFF43F5E, 3),
            ];

            for (id, name, icon, color, sort_order) in default_rooms {
                self.conn.execute(
                    "INSERT INTO rooms (id, name, icon, color, created_at, sort_order)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![id, name, icon, color as i64, now, sort_order],
                )?;
            }
        }
        Ok(())
    }

    /// Lock vault by zeroizing and dropping active encryption key and clearing temporary FTS table.
    pub fn lock(&mut self) -> Result<()> {
        self.active_key = None;
        let _ = self.conn.execute("DROP TABLE IF EXISTS temp.notes_fts", []);
        Ok(())
    }

    /// Change vault passphrase by re-encrypting all notes and metadata in a single transaction.
    pub fn change_passphrase(&mut self, old_pass: &str, new_pass: &str) -> Result<()> {
        if new_pass.trim().is_empty() {
            return Err(anyhow!("New passphrase cannot be empty"));
        }

        let key = self.get_active_key()?;

        // Verify old pass matches active key
        let salt_vec: Vec<u8> = self.conn.query_row(
            "SELECT salt FROM vault_metadata WHERE id = 1",
            [],
            |r| r.get(0),
        )?;
        let derived_old = derive_key(old_pass, &salt_vec)?;
        if derived_old.as_slice() != key.as_slice() {
            return Err(anyhow!("Current passphrase verification failed"));
        }

        // Fetch and decrypt all notes with old key
        let mut notes_to_reencrypt = Vec::new();
        {
            let mut stmt = self.conn.prepare("SELECT id, ciphertext, nonce FROM notes")?;
            let rows = stmt.query_map([], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, Vec<u8>>(1)?, r.get::<_, Vec<u8>>(2)?))
            })?;

            for row in rows {
                let (id, cipher, nonce_vec) = row?;
                if nonce_vec.len() < NONCE_LEN {
                    continue;
                }
                let mut nonce = [0u8; NONCE_LEN];
                nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);
                let decrypted = decrypt_payload(key, &cipher, &nonce)?;
                let content_str = String::from_utf8(decrypted.to_vec())
                    .map_err(|e| anyhow!("Corrupt UTF-8 note data: {e}"))?;
                notes_to_reencrypt.push((id, content_str));
            }
        }

        // Generate new salt and new key
        let new_salt = generate_salt();
        let new_key = derive_key(new_pass, &new_salt)?;
        let (new_verify_ciphertext, new_verify_nonce) = encrypt_payload(&new_key, VERIFY_MAGIC_PLAINTEXT)?;

        // Execute re-encryption in a single transaction
        let tx = self.conn.transaction()?;

        tx.execute(
            "UPDATE vault_metadata SET salt = ?1, verify_ciphertext = ?2, verify_nonce = ?3 WHERE id = 1",
            params![new_salt.to_vec(), new_verify_ciphertext, new_verify_nonce.to_vec()],
        )?;

        for (id, content) in notes_to_reencrypt {
            let (new_cipher, new_nonce) = encrypt_payload(&new_key, content.as_bytes())?;
            tx.execute(
                "UPDATE notes SET ciphertext = ?1, nonce = ?2 WHERE id = ?3",
                params![new_cipher, new_nonce.to_vec(), id],
            )?;
        }

        tx.commit()?;

        self.active_key = Some(new_key);
        Ok(())
    }

    fn get_active_key(&self) -> Result<&Zeroizing<[u8; KEY_LEN]>> {
        self.active_key
            .as_ref()
            .ok_or_else(|| anyhow!("Vault is locked. Please unlock first."))
    }

    // --- Temporary FTS5 Search Table Management ---

    fn init_temp_fts(&mut self) -> Result<()> {
        let _ = self.conn.execute(
            r#"
            CREATE VIRTUAL TABLE IF NOT EXISTS temp.notes_fts USING fts5(
                id UNINDEXED,
                room_id UNINDEXED,
                content,
                tokenize = 'unicode61'
            );
            "#,
            [],
        );
        Ok(())
    }

    fn rebuild_temp_fts(&mut self) -> Result<()> {
        let key = self.get_active_key()?;
        let _ = self.conn.execute("DELETE FROM temp.notes_fts", []);

        let mut stmt = self.conn.prepare("SELECT id, room_id, ciphertext, nonce FROM notes")?;
        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Vec<u8>>(2)?,
                r.get::<_, Vec<u8>>(3)?,
            ))
        })?;

        for row in rows {
            let (id, room_id, cipher, nonce_vec) = row?;
            if nonce_vec.len() < NONCE_LEN {
                continue;
            }
            let mut nonce = [0u8; NONCE_LEN];
            nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);
            if let Ok(decrypted) = decrypt_payload(key, &cipher, &nonce) {
                if let Ok(content_str) = String::from_utf8(decrypted.to_vec()) {
                    let _ = self.conn.execute(
                        "INSERT INTO temp.notes_fts (id, room_id, content) VALUES (?1, ?2, ?3)",
                        params![id, room_id, content_str],
                    );
                }
            }
        }
        Ok(())
    }

    // --- Note CRUD Operations ---

    pub fn save_note(&mut self, room_id: &str, content: &str) -> Result<NoteItem> {
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return Err(anyhow!("Note content cannot be empty"));
        }

        let key = self.get_active_key()?;
        let (is_todo, is_completed) = parse_todo_state(content);
        let tags = extract_tags(content);
        let tags_str = tags.join(",");
        let timestamp_ms = current_time_ms();
        let id = format!("note_{}_{}", timestamp_ms, generate_random_id());

        let (ciphertext, nonce) = encrypt_payload(key, content.as_bytes())?;

        self.conn.execute(
            r#"
            INSERT INTO notes (id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0, ?8)
            "#,
            params![
                id,
                room_id,
                ciphertext,
                nonce.to_vec(),
                timestamp_ms,
                if is_todo { 1 } else { 0 },
                if is_completed { 1 } else { 0 },
                tags_str,
            ],
        )?;

        // Update temporary FTS index
        let _ = self.conn.execute(
            "INSERT INTO temp.notes_fts (id, room_id, content) VALUES (?1, ?2, ?3)",
            params![id, room_id, content],
        );

        Ok(NoteItem {
            id,
            room_id: room_id.to_string(),
            content: content.to_string(),
            timestamp_ms,
            is_todo,
            is_completed,
            is_pinned: false,
            tags,
        })
    }

    pub fn update_note(&mut self, note_id: &str, content: &str) -> Result<NoteItem> {
        let trimmed = content.trim();
        if trimmed.is_empty() {
            return Err(anyhow!("Note content cannot be empty"));
        }

        let key = self.get_active_key()?;
        let (is_todo, is_completed) = parse_todo_state(content);
        let tags = extract_tags(content);
        let tags_str = tags.join(",");

        let (ciphertext, nonce) = encrypt_payload(key, content.as_bytes())?;

        let (room_id, timestamp_ms, is_pinned): (String, i64, i32) = self.conn.query_row(
            "SELECT room_id, timestamp_ms, is_pinned FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?;

        self.conn.execute(
            r#"
            UPDATE notes 
            SET ciphertext = ?1, nonce = ?2, is_todo = ?3, is_completed = ?4, tags = ?5
            WHERE id = ?6
            "#,
            params![
                ciphertext,
                nonce.to_vec(),
                if is_todo { 1 } else { 0 },
                if is_completed { 1 } else { 0 },
                tags_str,
                note_id,
            ],
        )?;

        // Update temporary FTS table
        let _ = self.conn.execute("DELETE FROM temp.notes_fts WHERE id = ?1", params![note_id]);
        let _ = self.conn.execute(
            "INSERT INTO temp.notes_fts (id, room_id, content) VALUES (?1, ?2, ?3)",
            params![note_id, room_id, content],
        );

        Ok(NoteItem {
            id: note_id.to_string(),
            room_id,
            content: content.to_string(),
            timestamp_ms,
            is_todo,
            is_completed,
            is_pinned: is_pinned > 0,
            tags,
        })
    }

    pub fn toggle_todo(&mut self, note_id: &str, is_completed: bool) -> Result<NoteItem> {
        let key = self.get_active_key()?;
        
        let (room_id, cipher, nonce_vec, timestamp_ms, is_pinned, tags_str): (
            String,
            Vec<u8>,
            Vec<u8>,
            i64,
            i32,
            String,
        ) = self.conn.query_row(
            "SELECT room_id, ciphertext, nonce, timestamp_ms, is_pinned, tags FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?)),
        )?;

        if nonce_vec.len() < NONCE_LEN {
            return Err(anyhow!("Corrupt note nonce"));
        }
        let mut nonce = [0u8; NONCE_LEN];
        nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);

        let decrypted = decrypt_payload(key, &cipher, &nonce)?;
        let mut text = String::from_utf8(decrypted.to_vec())
            .map_err(|e| anyhow!("Corrupt UTF-8 note text: {e}"))?;

        // Update the checkbox prefix in text if present
        text = update_todo_checkbox_in_text(&text, is_completed);

        let (new_cipher, new_nonce) = encrypt_payload(key, text.as_bytes())?;

        self.conn.execute(
            "UPDATE notes SET ciphertext = ?1, nonce = ?2, is_completed = ?3 WHERE id = ?4",
            params![new_cipher, new_nonce.to_vec(), if is_completed { 1 } else { 0 }, note_id],
        )?;

        // Update FTS
        let _ = self.conn.execute("DELETE FROM temp.notes_fts WHERE id = ?1", params![note_id]);
        let _ = self.conn.execute(
            "INSERT INTO temp.notes_fts (id, room_id, content) VALUES (?1, ?2, ?3)",
            params![note_id, room_id, text],
        );

        let tags = if tags_str.is_empty() {
            Vec::new()
        } else {
            tags_str.split(',').map(|s| s.to_string()).collect()
        };

        Ok(NoteItem {
            id: note_id.to_string(),
            room_id,
            content: text,
            timestamp_ms,
            is_todo: true,
            is_completed,
            is_pinned: is_pinned > 0,
            tags,
        })
    }

    pub fn pin_note(&mut self, note_id: &str, is_pinned: bool) -> Result<NoteItem> {
        let key = self.get_active_key()?;

        let (room_id, cipher, nonce_vec, timestamp_ms, is_todo, is_completed, tags_str): (
            String,
            Vec<u8>,
            Vec<u8>,
            i64,
            i32,
            i32,
            String,
        ) = self.conn.query_row(
            "SELECT room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, tags FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?)),
        )?;

        if nonce_vec.len() < NONCE_LEN {
            return Err(anyhow!("Corrupt note nonce"));
        }
        let mut nonce = [0u8; NONCE_LEN];
        nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);

        let decrypted = decrypt_payload(key, &cipher, &nonce)?;
        let text = String::from_utf8(decrypted.to_vec())
            .map_err(|e| anyhow!("Corrupt UTF-8 note text: {e}"))?;

        self.conn.execute(
            "UPDATE notes SET is_pinned = ?1 WHERE id = ?2",
            params![if is_pinned { 1 } else { 0 }, note_id],
        )?;

        let tags = if tags_str.is_empty() {
            Vec::new()
        } else {
            tags_str.split(',').map(|s| s.to_string()).collect()
        };

        Ok(NoteItem {
            id: note_id.to_string(),
            room_id,
            content: text,
            timestamp_ms,
            is_todo: is_todo > 0,
            is_completed: is_completed > 0,
            is_pinned,
            tags,
        })
    }

    pub fn delete_note(&mut self, note_id: &str) -> Result<()> {
        let _ = self.get_active_key()?;
        self.conn.execute("DELETE FROM notes WHERE id = ?1", params![note_id])?;
        let _ = self.conn.execute("DELETE FROM temp.notes_fts WHERE id = ?1", params![note_id]);
        Ok(())
    }

    pub fn get_notes(&self, room_id: &str) -> Result<Vec<NoteItem>> {
        let key = self.get_active_key()?;

        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags
            FROM notes
            WHERE room_id = ?1
            ORDER BY is_pinned DESC, timestamp_ms ASC
            "#,
        )?;

        let rows = stmt.query_map(params![room_id], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Vec<u8>>(2)?,
                r.get::<_, Vec<u8>>(3)?,
                r.get::<_, i64>(4)?,
                r.get::<_, i32>(5)?,
                r.get::<_, i32>(6)?,
                r.get::<_, i32>(7)?,
                r.get::<_, String>(8)?,
            ))
        })?;

        let mut notes = Vec::new();
        for row in rows {
            let (id, r_id, cipher, nonce_vec, timestamp_ms, is_todo, is_completed, is_pinned, tags_str) = row?;
            if nonce_vec.len() < NONCE_LEN {
                continue;
            }
            let mut nonce = [0u8; NONCE_LEN];
            nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);

            if let Ok(decrypted) = decrypt_payload(key, &cipher, &nonce) {
                if let Ok(content) = String::from_utf8(decrypted.to_vec()) {
                    let tags = if tags_str.is_empty() {
                        Vec::new()
                    } else {
                        tags_str.split(',').map(|s| s.to_string()).collect()
                    };
                    notes.push(NoteItem {
                        id,
                        room_id: r_id,
                        content,
                        timestamp_ms,
                        is_todo: is_todo > 0,
                        is_completed: is_completed > 0,
                        is_pinned: is_pinned > 0,
                        tags,
                    });
                }
            }
        }

        Ok(notes)
    }

    pub fn search_notes(&self, query: &str, room_filter: Option<&str>) -> Result<Vec<NoteItem>> {
        let key = self.get_active_key()?;
        let trimmed_query = query.trim();
        if trimmed_query.is_empty() {
            return Ok(Vec::new());
        }

        // Try FTS5 matching first, fall back to in-memory search
        let sanitized_query = sanitize_fts_query(trimmed_query);
        let mut matched_ids: Vec<String> = Vec::new();

        if let Ok(mut stmt) = self.conn.prepare(
            "SELECT id FROM temp.notes_fts WHERE notes_fts MATCH ?1 ORDER BY rank LIMIT 100",
        ) {
            if let Ok(rows) = stmt.query_map(params![sanitized_query], |r| r.get(0)) {
                for id in rows.flatten() {
                    matched_ids.push(id);
                }
            }
        }

        let mut results = Vec::new();

        if !matched_ids.is_empty() {
            // Retrieve notes by matched IDs
            for id in matched_ids {
                let note_res = self.conn.query_row(
                    r#"
                    SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags
                    FROM notes WHERE id = ?1
                    "#,
                    params![id],
                    |r| {
                        Ok((
                            r.get::<_, String>(0)?,
                            r.get::<_, String>(1)?,
                            r.get::<_, Vec<u8>>(2)?,
                            r.get::<_, Vec<u8>>(3)?,
                            r.get::<_, i64>(4)?,
                            r.get::<_, i32>(5)?,
                            r.get::<_, i32>(6)?,
                            r.get::<_, i32>(7)?,
                            r.get::<_, String>(8)?,
                        ))
                    },
                ).optional()?;

                if let Some((nid, rid, cipher, nonce_vec, ts, is_todo, is_completed, is_pinned, tags_str)) = note_res {
                    if let Some(rf) = room_filter {
                        if rid != rf {
                            continue;
                        }
                    }
                    if nonce_vec.len() >= NONCE_LEN {
                        let mut nonce = [0u8; NONCE_LEN];
                        nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);
                        if let Ok(decrypted) = decrypt_payload(key, &cipher, &nonce) {
                            if let Ok(content) = String::from_utf8(decrypted.to_vec()) {
                                let tags = if tags_str.is_empty() {
                                    Vec::new()
                                } else {
                                    tags_str.split(',').map(|s| s.to_string()).collect()
                                };
                                results.push(NoteItem {
                                    id: nid,
                                    room_id: rid,
                                    content,
                                    timestamp_ms: ts,
                                    is_todo: is_todo > 0,
                                    is_completed: is_completed > 0,
                                    is_pinned: is_pinned > 0,
                                    tags,
                                });
                            }
                        }
                    }
                }
            }
        } else {
            // Fallback: in-memory substring match across notes
            let mut stmt = self.conn.prepare(
                "SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags FROM notes ORDER BY timestamp_ms DESC",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, Vec<u8>>(2)?,
                    r.get::<_, Vec<u8>>(3)?,
                    r.get::<_, i64>(4)?,
                    r.get::<_, i32>(5)?,
                    r.get::<_, i32>(6)?,
                    r.get::<_, i32>(7)?,
                    r.get::<_, String>(8)?,
                ))
            })?;

            let q_lower = trimmed_query.to_lowercase();
            for row in rows {
                let (nid, rid, cipher, nonce_vec, ts, is_todo, is_completed, is_pinned, tags_str) = row?;
                if let Some(rf) = room_filter {
                    if rid != rf {
                        continue;
                    }
                }
                if nonce_vec.len() >= NONCE_LEN {
                    let mut nonce = [0u8; NONCE_LEN];
                    nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);
                    if let Ok(decrypted) = decrypt_payload(key, &cipher, &nonce) {
                        if let Ok(content) = String::from_utf8(decrypted.to_vec()) {
                            if content.to_lowercase().contains(&q_lower) || rid.to_lowercase().contains(&q_lower) {
                                let tags = if tags_str.is_empty() {
                                    Vec::new()
                                } else {
                                    tags_str.split(',').map(|s| s.to_string()).collect()
                                };
                                results.push(NoteItem {
                                    id: nid,
                                    room_id: rid,
                                    content,
                                    timestamp_ms: ts,
                                    is_todo: is_todo > 0,
                                    is_completed: is_completed > 0,
                                    is_pinned: is_pinned > 0,
                                    tags,
                                });
                            }
                        }
                    }
                }
            }
        }

        Ok(results)
    }

    // --- Room Operations ---

    pub fn list_rooms(&self) -> Result<Vec<RoomItem>> {
        let mut stmt = self
            .conn
            .prepare("SELECT id, name, icon, color, created_at, sort_order FROM rooms ORDER BY sort_order ASC, name ASC")?;

        let rows = stmt.query_map([], |r| {
            Ok(RoomItem {
                id: r.get(0)?,
                name: r.get(1)?,
                icon: r.get(2)?,
                color: r.get::<_, i64>(3)? as u32,
                created_at: r.get(4)?,
                sort_order: r.get(5)?,
            })
        })?;

        let mut rooms = Vec::new();
        for room in rows {
            rooms.push(room?);
        }
        Ok(rooms)
    }

    pub fn create_room(&mut self, id: &str, name: &str, icon: &str, color: u32) -> Result<RoomItem> {
        let trimmed_id = id.trim().to_lowercase().replace(' ', "-");
        let trimmed_name = name.trim();

        if trimmed_id.is_empty() || trimmed_name.is_empty() {
            return Err(anyhow!("Room ID and Name cannot be empty"));
        }

        let now = current_time_ms();
        let max_sort: i32 = self
            .conn
            .query_row("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM rooms", [], |r| r.get(0))
            .unwrap_or(0);

        self.conn.execute(
            "INSERT INTO rooms (id, name, icon, color, created_at, sort_order) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![trimmed_id, trimmed_name, icon, color as i64, now, max_sort],
        )?;

        Ok(RoomItem {
            id: trimmed_id,
            name: trimmed_name.to_string(),
            icon: icon.to_string(),
            color,
            created_at: now,
            sort_order: max_sort,
        })
    }

    pub fn delete_room(&mut self, room_id: &str) -> Result<()> {
        if room_id == "general" {
            return Err(anyhow!("The default #general room cannot be deleted"));
        }
        self.conn.execute("DELETE FROM rooms WHERE id = ?1", params![room_id])?;
        Ok(())
    }
}

// --- Helper Utilities ---

fn current_time_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn generate_random_id() -> String {
    let mut bytes = [0u8; 8];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

mod hex {
    pub fn encode(bytes: [u8; 8]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }
}

fn parse_todo_state(content: &str) -> (bool, bool) {
    let trimmed = content.trim_start();
    if trimmed.starts_with("[ ]") || trimmed.starts_with("- [ ]") {
        (true, false)
    } else if trimmed.starts_with("[x]") || trimmed.starts_with("[X]") || trimmed.starts_with("- [x]") || trimmed.starts_with("- [X]") {
        (true, true)
    } else {
        (false, false)
    }
}

fn update_todo_checkbox_in_text(content: &str, is_completed: bool) -> String {
    let trimmed = content.trim_start();
    let new_box = if is_completed { "[x] " } else { "[ ] " };

    if trimmed.starts_with("[ ] ") {
        format!("{}{}", new_box, &trimmed[4..])
    } else if trimmed.starts_with("[x] ") || trimmed.starts_with("[X] ") {
        format!("{}{}", new_box, &trimmed[4..])
    } else if trimmed.starts_with("- [ ] ") {
        format!("- {}{}", new_box, &trimmed[6..])
    } else if trimmed.starts_with("- [x] ") || trimmed.starts_with("- [X] ") {
        format!("- {}{}", new_box, &trimmed[6..])
    } else if trimmed.starts_with("[ ]") {
        format!("{}{}", new_box, &trimmed[3..])
    } else if trimmed.starts_with("[x]") || trimmed.starts_with("[X]") {
        format!("{}{}", new_box, &trimmed[3..])
    } else {
        format!("{}{}", new_box, content)
    }
}

fn extract_tags(content: &str) -> Vec<String> {
    content
        .split_whitespace()
        .filter(|w| w.starts_with('#') && w.len() > 1)
        .map(|w| w.trim_matches(|c: char| !c.is_alphanumeric() && c != '_' && c != '-').to_lowercase())
        .filter(|t| !t.is_empty())
        .collect()
}

fn sanitize_fts_query(query: &str) -> String {
    let clean: String = query
        .chars()
        .filter(|c| c.is_alphanumeric() || c.is_whitespace() || *c == '_' || *c == '-')
        .collect();
    let tokens: Vec<&str> = clean.split_whitespace().collect();
    if tokens.is_empty() {
        return "\"\"".to_string();
    }
    tokens
        .iter()
        .map(|t| format!("\"{}*\"", t))
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_store_init_and_unlock_flow() {
        let mut store = EncryptedStore::open_in_memory().expect("failed to open store");
        assert!(!store.is_vault_initialized().unwrap());
        assert!(!store.is_unlocked());

        // Initialize vault
        store.unlock_or_init("master_secret_pass").expect("failed to init");
        assert!(store.is_vault_initialized().unwrap());
        assert!(store.is_unlocked());

        // Default rooms created
        let rooms = store.list_rooms().expect("failed to list rooms");
        assert_eq!(rooms.len(), 4);
        assert_eq!(rooms[0].id, "general");

        // Save a note
        let note = store.save_note("general", "Hello #antigravity secure world!").expect("save note failed");
        assert_eq!(note.room_id, "general");
        assert_eq!(note.tags, vec!["antigravity"]);
        assert!(!note.is_todo);

        // Fetch notes
        let notes = store.get_notes("general").expect("failed to get notes");
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].content, "Hello #antigravity secure world!");

        // Search notes
        let search_results = store.search_notes("antigravity", None).expect("search failed");
        assert_eq!(search_results.len(), 1);
        assert_eq!(search_results[0].id, note.id);

        // Lock vault
        store.lock().expect("lock failed");
        assert!(!store.is_unlocked());
        assert!(store.get_notes("general").is_err());

        // Unlock with wrong password fails
        assert!(store.unlock_or_init("wrong_password").is_err());
        assert!(!store.is_unlocked());

        // Unlock with correct password succeeds
        store.unlock_or_init("master_secret_pass").expect("re-unlock failed");
        assert!(store.is_unlocked());
        let notes_after = store.get_notes("general").expect("get notes after re-unlock");
        assert_eq!(notes_after.len(), 1);
    }

    #[test]
    fn test_todo_interaction_and_pinning() {
        let mut store = EncryptedStore::open_in_memory().expect("open memory");
        store.unlock_or_init("pass123").unwrap();

        // Create todo note
        let note = store.save_note("personal", "[ ] Buy groceries").unwrap();
        assert!(note.is_todo);
        assert!(!note.is_completed);

        // Toggle todo to completed
        let updated = store.toggle_todo(&note.id, true).unwrap();
        assert!(updated.is_completed);
        assert!(updated.content.starts_with("[x]"));

        // Pin note
        let pinned = store.pin_note(&note.id, true).unwrap();
        assert!(pinned.is_pinned);

        // Toggle todo back to uncompleted
        let uncompleted = store.toggle_todo(&note.id, false).unwrap();
        assert!(!uncompleted.is_completed);
        assert!(uncompleted.content.starts_with("[ ]"));
    }

    #[test]
    fn test_change_passphrase_flow() {
        let mut store = EncryptedStore::open_in_memory().expect("open memory");
        store.unlock_or_init("initial_password").unwrap();

        store.save_note("general", "Secret message to be re-encrypted").unwrap();

        // Change password
        store.change_passphrase("initial_password", "new_super_secret").unwrap();

        // Lock and verify old password fails
        store.lock().unwrap();
        assert!(store.unlock_or_init("initial_password").is_err());

        // Verify new password succeeds and data intact
        store.unlock_or_init("new_super_secret").unwrap();
        let notes = store.get_notes("general").unwrap();
        assert_eq!(notes.len(), 1);
        assert_eq!(notes[0].content, "Secret message to be re-encrypted");
    }
}
