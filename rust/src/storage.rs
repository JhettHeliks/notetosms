use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Context, Result};
use base64::Engine;
use rand::RngCore;
use rusqlite::{params, Connection, OpenFlags, OptionalExtension};
use zeroize::Zeroizing;

use crate::crypto::{
    decrypt_payload, derive_key, encrypt_payload, generate_salt, KEY_LEN, NONCE_LEN, SALT_LEN,
};

const VERIFY_MAGIC_PLAINTEXT: &[u8] = b"CHATNOTES_ENCRYPTED_VAULT_V1_OK";
const CURRENT_SCHEMA_VERSION: i32 = 1;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct UserProfile {
    pub display_name: String,
    pub avatar_color: u32,
    pub avatar_icon: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct SharedRoomInfo {
    pub room_id: String,
    pub encryption_key: String,
    pub is_background_sync_enabled: bool,
    pub share_ticket: Option<String>,
}

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
    pub author_id: Option<String>,
    pub author_name: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RoomItem {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color: u32,
    pub created_at: i64,
    pub sort_order: i32,
    pub encryption_key: Option<String>,
    pub share_ticket: Option<String>,
    pub is_background_sync_enabled: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RoomInvite {
    pub version: u32,
    pub room_id: String,
    pub name: String,
    pub icon: String,
    pub color: u32,
    pub room_key_base64: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VaultStatus {
    pub is_initialized: bool,
    pub is_unlocked: bool,
    pub db_path: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct UnencryptedBackupNote {
    pub id: String,
    pub room_id: String,
    pub content: String,
    pub timestamp_ms: i64,
    pub is_todo: bool,
    pub is_completed: bool,
    pub is_pinned: bool,
    pub tags: Vec<String>,
    pub author_id: Option<String>,
    pub author_name: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct UnencryptedBackup {
    pub format: String,
    pub version: u32,
    pub exported_at: i64,
    pub rooms: Vec<RoomItem>,
    pub notes: Vec<UnencryptedBackupNote>,
}

/// Check if a database file exists on disk and has valid initialized vault metadata with salt.
pub fn check_vault_file_initialized(path: &str) -> bool {
    let path_obj = Path::new(path);
    if !path_obj.exists() {
        return false;
    }
    if let Ok(meta) = path_obj.metadata() {
        if meta.len() == 0 {
            return false;
        }
    }

    let Ok(conn) = Connection::open_with_flags(
        path,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    ) else {
        return false;
    };

    let count: Result<i64, _> = conn.query_row(
        "SELECT COUNT(*) FROM vault_metadata WHERE id = 1 AND LENGTH(salt) >= 16",
        [],
        |r| r.get(0),
    );
    matches!(count, Ok(c) if c > 0)
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
                sort_order INTEGER NOT NULL DEFAULT 0,
                encryption_key TEXT,
                share_ticket TEXT,
                is_background_sync_enabled INTEGER NOT NULL DEFAULT 1
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
                author_id TEXT,
                author_name TEXT,
                FOREIGN KEY (room_id) REFERENCES rooms(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS user_profile (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                display_name TEXT NOT NULL DEFAULT 'NoteToSMS User',
                avatar_color INTEGER NOT NULL DEFAULT 4280424424,
                avatar_icon TEXT NOT NULL DEFAULT 'person',
                updated_at INTEGER NOT NULL DEFAULT 0
            );

            CREATE INDEX IF NOT EXISTS idx_notes_room_timestamp ON notes(room_id, timestamp_ms);
            CREATE INDEX IF NOT EXISTS idx_notes_pinned ON notes(is_pinned);
            "#,
        )?;

        // Auto-migrate tables in case database was created under previous schema
        let _ = self.conn.execute("ALTER TABLE notes ADD COLUMN author_id TEXT", []);
        let _ = self.conn.execute("ALTER TABLE notes ADD COLUMN author_name TEXT", []);
        let _ = self.conn.execute("ALTER TABLE rooms ADD COLUMN encryption_key TEXT", []);
        let _ = self.conn.execute("ALTER TABLE rooms ADD COLUMN share_ticket TEXT", []);
        let _ = self.conn.execute("ALTER TABLE rooms ADD COLUMN is_background_sync_enabled INTEGER NOT NULL DEFAULT 1", []);

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

    pub fn get_user_profile(&self) -> Result<UserProfile> {
        let res = self.conn.query_row(
            "SELECT display_name, avatar_color, avatar_icon FROM user_profile WHERE id = 1",
            [],
            |r| {
                Ok(UserProfile {
                    display_name: r.get(0)?,
                    avatar_color: r.get::<_, i64>(1)? as u32,
                    avatar_icon: r.get(2)?,
                })
            },
        ).optional()?;

        Ok(res.unwrap_or(UserProfile {
            display_name: "NoteToSMS User".to_string(),
            avatar_color: 0xFF1A73E8,
            avatar_icon: "person".to_string(),
        }))
    }

    pub fn save_user_profile(&mut self, profile: &UserProfile) -> Result<()> {
        let now = current_time_ms();
        self.conn.execute(
            r#"
            INSERT INTO user_profile (id, display_name, avatar_color, avatar_icon, updated_at)
            VALUES (1, ?1, ?2, ?3, ?4)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                avatar_color = excluded.avatar_color,
                avatar_icon = excluded.avatar_icon,
                updated_at = excluded.updated_at
            "#,
            params![profile.display_name, profile.avatar_color as i64, profile.avatar_icon, now],
        )?;
        Ok(())
    }

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
        let my_profile = self.get_user_profile().unwrap_or(UserProfile {
            display_name: "You".to_string(),
            avatar_color: 0xFF1A73E8,
            avatar_icon: "person".to_string(),
        });

        // Ensure room exists in rooms table so foreign key constraint never fails
        let room_exists: bool = self.conn.query_row(
            "SELECT COUNT(*) FROM rooms WHERE id = ?1",
            params![room_id],
            |r| Ok(r.get::<_, i64>(0)? > 0),
        ).unwrap_or(false);

        if !room_exists {
            let now = current_time_ms();
            let _ = self.conn.execute(
                "INSERT OR IGNORE INTO rooms (id, name, icon, color, created_at, sort_order, is_background_sync_enabled)
                 VALUES (?1, ?2, 'chat_bubble', 4284704511, ?3, 0, 1)",
                params![room_id, room_id, now],
            );
        }

        self.conn.execute(
            r#"
            INSERT INTO notes (id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0, ?8, NULL, ?9)
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
                my_profile.display_name,
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
            author_id: None,
            author_name: Some(my_profile.display_name),
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

        let (room_id, timestamp_ms, is_pinned, author_id, author_name): (
            String,
            i64,
            i32,
            Option<String>,
            Option<String>,
        ) = self.conn.query_row(
            "SELECT room_id, timestamp_ms, is_pinned, author_id, author_name FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?)),
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
            author_id,
            author_name,
        })
    }

    pub fn toggle_todo(&mut self, note_id: &str, is_completed: bool) -> Result<NoteItem> {
        let key = self.get_active_key()?;
        
        let (room_id, cipher, nonce_vec, timestamp_ms, is_pinned, tags_str, author_id, author_name): (
            String,
            Vec<u8>,
            Vec<u8>,
            i64,
            i32,
            String,
            Option<String>,
            Option<String>,
        ) = self.conn.query_row(
            "SELECT room_id, ciphertext, nonce, timestamp_ms, is_pinned, tags, author_id, author_name FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?)),
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
            author_id,
            author_name,
        })
    }

    pub fn pin_note(&mut self, note_id: &str, is_pinned: bool) -> Result<NoteItem> {
        let key = self.get_active_key()?;

        let (room_id, cipher, nonce_vec, timestamp_ms, is_todo, is_completed, tags_str, author_id, author_name): (
            String,
            Vec<u8>,
            Vec<u8>,
            i64,
            i32,
            i32,
            String,
            Option<String>,
            Option<String>,
        ) = self.conn.query_row(
            "SELECT room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, tags, author_id, author_name FROM notes WHERE id = ?1",
            params![note_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?, r.get(7)?, r.get(8)?)),
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
            author_id,
            author_name,
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
            SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name
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
                r.get::<_, Option<String>>(9)?,
                r.get::<_, Option<String>>(10)?,
            ))
        })?;

        let mut notes = Vec::new();
        for row in rows {
            let (id, r_id, cipher, nonce_vec, timestamp_ms, is_todo, is_completed, is_pinned, tags_str, author_id, author_name) = row?;
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
                        author_id,
                        author_name,
                    });
                }
            }
        }

        Ok(notes)
    }

    pub fn upsert_remote_note(
        &mut self,
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
        let key = self.get_active_key()?;
        let tags = extract_tags(content);
        let tags_str = tags.join(",");

        // Ensure room exists in rooms table so foreign key constraint never fails
        let room_exists: bool = self.conn.query_row(
            "SELECT COUNT(*) FROM rooms WHERE id = ?1",
            params![room_id],
            |r| Ok(r.get::<_, i64>(0)? > 0),
        ).unwrap_or(false);

        if !room_exists {
            let now = current_time_ms();
            let _ = self.conn.execute(
                "INSERT OR IGNORE INTO rooms (id, name, icon, color, created_at, sort_order, is_background_sync_enabled)
                 VALUES (?1, ?2, 'chat_bubble', 4284704511, ?3, 0, 1)",
                params![room_id, room_id, now],
            );
        }

        let (ciphertext, nonce) = encrypt_payload(key, content.as_bytes())?;

        self.conn.execute(
            r#"
            INSERT INTO notes (id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
            ON CONFLICT(id) DO UPDATE SET
                ciphertext = excluded.ciphertext,
                nonce = excluded.nonce,
                timestamp_ms = excluded.timestamp_ms,
                is_todo = excluded.is_todo,
                is_completed = excluded.is_completed,
                is_pinned = excluded.is_pinned,
                tags = excluded.tags,
                author_id = excluded.author_id,
                author_name = excluded.author_name
            "#,
            params![
                id,
                room_id,
                ciphertext,
                nonce.to_vec(),
                timestamp_ms,
                if is_todo { 1 } else { 0 },
                if is_completed { 1 } else { 0 },
                if is_pinned { 1 } else { 0 },
                tags_str,
                author_id,
                author_name,
            ],
        )?;

        // Update temporary FTS table
        let _ = self.conn.execute("DELETE FROM temp.notes_fts WHERE id = ?1", params![id]);
        let _ = self.conn.execute(
            "INSERT INTO temp.notes_fts (id, room_id, content) VALUES (?1, ?2, ?3)",
            params![id, room_id, content],
        );

        Ok(NoteItem {
            id: id.to_string(),
            room_id: room_id.to_string(),
            content: content.to_string(),
            timestamp_ms,
            is_todo,
            is_completed,
            is_pinned,
            tags,
            author_id: author_id.map(|s| s.to_string()),
            author_name: author_name.map(|s| s.to_string()),
        })
    }

    pub fn get_notes_since(&self, room_id: &str, since_timestamp_ms: i64) -> Result<Vec<NoteItem>> {
        let key = self.get_active_key()?;

        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name
            FROM notes
            WHERE room_id = ?1 AND timestamp_ms >= ?2
            ORDER BY is_pinned DESC, timestamp_ms ASC
            "#,
        )?;

        let rows = stmt.query_map(params![room_id, since_timestamp_ms], |r| {
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
                r.get::<_, Option<String>>(9)?,
                r.get::<_, Option<String>>(10)?,
            ))
        })?;

        let mut notes = Vec::new();
        for row in rows {
            let (id, r_id, cipher, nonce_vec, timestamp_ms, is_todo, is_completed, is_pinned, tags_str, author_id, author_name) = row?;
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
                        author_id,
                        author_name,
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
                    SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name
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
                            r.get::<_, Option<String>>(9)?,
                            r.get::<_, Option<String>>(10)?,
                        ))
                    },
                ).optional()?;

                if let Some((nid, rid, cipher, nonce_vec, ts, is_todo, is_completed, is_pinned, tags_str, author_id, author_name)) = note_res {
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
                                    author_id,
                                    author_name,
                                });
                            }
                        }
                    }
                }
            }
        } else {
            // Fallback: in-memory substring match across notes
            let mut stmt = self.conn.prepare(
                "SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name FROM notes ORDER BY timestamp_ms DESC",
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
                    r.get::<_, Option<String>>(9)?,
                    r.get::<_, Option<String>>(10)?,
                ))
            })?;

            let q_lower = trimmed_query.to_lowercase();
            for row in rows {
                let (nid, rid, cipher, nonce_vec, ts, is_todo, is_completed, is_pinned, tags_str, author_id, author_name) = row?;
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
                                    author_id,
                                    author_name,
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
            .prepare("SELECT id, name, icon, color, created_at, sort_order, encryption_key, share_ticket, is_background_sync_enabled FROM rooms ORDER BY sort_order ASC, name ASC")?;

        let rows = stmt.query_map([], |r| {
            Ok(RoomItem {
                id: r.get(0)?,
                name: r.get(1)?,
                icon: r.get(2)?,
                color: r.get::<_, i64>(3)? as u32,
                created_at: r.get(4)?,
                sort_order: r.get(5)?,
                encryption_key: r.get(6)?,
                share_ticket: r.get(7)?,
                is_background_sync_enabled: r.get::<_, i32>(8).unwrap_or(1) > 0,
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
            "INSERT INTO rooms (id, name, icon, color, created_at, sort_order, is_background_sync_enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)",
            params![trimmed_id, trimmed_name, icon, color as i64, now, max_sort],
        )?;

        Ok(RoomItem {
            id: trimmed_id,
            name: trimmed_name.to_string(),
            icon: icon.to_string(),
            color,
            created_at: now,
            sort_order: max_sort,
            encryption_key: None,
            share_ticket: None,
            is_background_sync_enabled: true,
        })
    }

    pub fn upsert_room(&mut self, id: &str, name: &str, icon: &str, color: u32) -> Result<RoomItem> {
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
            r#"
            INSERT INTO rooms (id, name, icon, color, created_at, sort_order, is_background_sync_enabled)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, 1)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                icon = CASE WHEN rooms.icon IS NULL OR rooms.icon = '' THEN excluded.icon ELSE rooms.icon END,
                color = CASE WHEN rooms.color = 0 THEN excluded.color ELSE rooms.color END
            "#,
            params![trimmed_id, trimmed_name, icon, color as i64, now, max_sort],
        )?;

        self.get_room(&trimmed_id)
    }

    pub fn get_room(&self, room_id: &str) -> Result<RoomItem> {
        self.conn
            .query_row(
                "SELECT id, name, icon, color, created_at, sort_order, encryption_key, share_ticket, is_background_sync_enabled FROM rooms WHERE id = ?1",
                params![room_id],
                |r| {
                    Ok(RoomItem {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        icon: r.get(2)?,
                        color: r.get::<_, i64>(3)? as u32,
                        created_at: r.get(4)?,
                        sort_order: r.get(5)?,
                        encryption_key: r.get(6)?,
                        share_ticket: r.get(7)?,
                        is_background_sync_enabled: r.get::<_, i32>(8).unwrap_or(1) > 0,
                    })
                },
            )
            .map_err(|e| anyhow!("Room '{room_id}' not found: {e}"))
    }

    pub fn set_room_background_sync(&mut self, room_id: &str, enabled: bool) -> Result<()> {
        self.conn.execute(
            "UPDATE rooms SET is_background_sync_enabled = ?1 WHERE id = ?2",
            params![if enabled { 1 } else { 0 }, room_id],
        )?;
        Ok(())
    }

    pub fn save_room_encryption_details(&mut self, room_id: &str, encryption_key: &str, share_ticket: Option<&str>) -> Result<()> {
        self.conn.execute(
            "UPDATE rooms SET encryption_key = ?1, share_ticket = COALESCE(?2, share_ticket) WHERE id = ?3",
            params![encryption_key, share_ticket, room_id],
        )?;
        Ok(())
    }

    pub fn get_shared_rooms_with_keys(&self) -> Result<Vec<SharedRoomInfo>> {
        let mut stmt = self.conn.prepare(
            "SELECT id, encryption_key, is_background_sync_enabled, share_ticket FROM rooms WHERE encryption_key IS NOT NULL AND encryption_key != ''"
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(SharedRoomInfo {
                room_id: r.get(0)?,
                encryption_key: r.get(1)?,
                is_background_sync_enabled: r.get::<_, i32>(2).unwrap_or(1) > 0,
                share_ticket: r.get(3)?,
            })
        })?;
        let mut list = Vec::new();
        for r in rows {
            list.push(r?);
        }
        Ok(list)
    }

    pub fn delete_room(&mut self, room_id: &str) -> Result<()> {
        if room_id == "general" {
            return Err(anyhow!("The default #general room cannot be deleted"));
        }
        self.conn.execute("DELETE FROM rooms WHERE id = ?1", params![room_id])?;
        Ok(())
    }

    /// Exports a shareable invite URI containing the room metadata and symmetric key payload.
    pub fn export_room_invite(&self, room_id: &str) -> Result<String> {
        let _ = self.get_active_key()?;
        let room = self.get_room(room_id)?;

        let mut key_bytes = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut key_bytes);
        let room_key_base64 = base64::engine::general_purpose::STANDARD.encode(&key_bytes);

        let invite = RoomInvite {
            version: 1,
            room_id: room.id,
            name: room.name,
            icon: room.icon,
            color: room.color,
            room_key_base64,
            created_at: current_time_ms(),
        };

        let json_bytes = serde_json::to_vec(&invite)?;
        let b64 = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&json_bytes);
        Ok(format!("notetosms://join?data={b64}"))
    }

    /// Parses and validates a room invite payload from a URI, deep link, or raw Base64/Base58 string.
    pub fn parse_room_invite_data(invite_data: &str) -> Result<RoomInvite> {
        let trimmed = invite_data.trim();
        let payload_str = if let Some(idx) = trimmed.find("ticket=") {
            &trimmed[idx + 7..]
        } else if let Some(idx) = trimmed.find("data=") {
            &trimmed[idx + 5..]
        } else if let Some(idx) = trimmed.find("/join/") {
            &trimmed[idx + 6..]
        } else {
            trimmed
        };

        let clean_payload = payload_str.split('&').next().unwrap_or(payload_str);

        if let Ok(ticket) = crate::p2p_protocol::decode_ticket_payload(clean_payload) {
            return Ok(RoomInvite {
                version: 1,
                room_id: ticket.room_id,
                name: ticket.room_name,
                icon: "chat_bubble".into(),
                color: 0xFF1A73E8,
                room_key_base64: ticket.encryption_key,
                created_at: 0,
            });
        }

        let decoded = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(clean_payload)
            .or_else(|_| base64::engine::general_purpose::URL_SAFE.decode(clean_payload))
            .or_else(|_| base64::engine::general_purpose::STANDARD.decode(clean_payload))
            .or_else(|_| base64::engine::general_purpose::STANDARD_NO_PAD.decode(clean_payload))
            .context("Failed to decode base64 room invite payload")?;

        let invite: RoomInvite = serde_json::from_slice(&decoded)
            .context("Invalid room invite JSON structure")?;

        if invite.room_id.trim().is_empty() || invite.name.trim().is_empty() {
            return Err(anyhow!("Room invite is missing required fields"));
        }

        Ok(invite)
    }

    /// Parses a room invite string without modifying the store.
    pub fn parse_room_invite(&self, invite_data: &str) -> Result<RoomInvite> {
        Self::parse_room_invite_data(invite_data)
    }

    /// Imports a room from an invite payload, creating it if it doesn't already exist.
    pub fn import_room_invite(&mut self, invite_data: &str) -> Result<RoomItem> {
        let _ = self.get_active_key()?;
        let invite = Self::parse_room_invite_data(invite_data)?;

        // If room already exists, return it
        if let Ok(existing) = self.get_room(&invite.room_id) {
            return Ok(existing);
        }

        self.create_room(&invite.room_id, &invite.name, &invite.icon, invite.color)
    }

    /// Export a clean, consolidated encrypted SQLite backup to the specified destination path.
    pub fn export_encrypted_backup(&self, destination_path: &str) -> Result<()> {
        let _ = self.conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);");

        let dest = Path::new(destination_path);
        if dest.exists() {
            let _ = std::fs::remove_file(dest);
        }

        self.conn
            .execute("VACUUM INTO ?1", params![destination_path])
            .context("Failed to export encrypted vault backup via VACUUM INTO")?;

        Ok(())
    }

    /// Export decrypted plaintext notes and room metadata as structured JSON to destination path.
    pub fn export_unencrypted_backup(&self, destination_path: &str) -> Result<()> {
        let key = self.get_active_key()?;
        let rooms = self.list_rooms()?;

        let mut unencrypted_notes = Vec::new();
        let mut stmt = self.conn.prepare(
            "SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags, author_id, author_name FROM notes ORDER BY timestamp_ms ASC"
        )?;

        let rows = stmt.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Vec<u8>>(2)?,
                r.get::<_, Vec<u8>>(3)?,
                r.get::<_, i64>(4)?,
                r.get::<_, i32>(5)? != 0,
                r.get::<_, i32>(6)? != 0,
                r.get::<_, i32>(7)? != 0,
                r.get::<_, String>(8)?,
                r.get::<_, Option<String>>(9)?,
                r.get::<_, Option<String>>(10)?,
            ))
        })?;

        for row in rows {
            let (id, room_id, ciphertext, nonce_vec, timestamp_ms, is_todo, is_completed, is_pinned, tags_str, author_id, author_name) = row?;
            if nonce_vec.len() < NONCE_LEN {
                continue;
            }
            let mut nonce = [0u8; NONCE_LEN];
            nonce.copy_from_slice(&nonce_vec[..NONCE_LEN]);

            let decrypted_bytes = decrypt_payload(key, &ciphertext, &nonce)?;
            let content = String::from_utf8(decrypted_bytes.to_vec())
                .map_err(|e| anyhow!("Corrupted UTF-8 in note {id}: {e}"))?;

            let tags = if tags_str.trim().is_empty() {
                Vec::new()
            } else {
                tags_str.split(',').map(|s| s.trim().to_string()).filter(|s| !s.is_empty()).collect()
            };

            unencrypted_notes.push(UnencryptedBackupNote {
                id,
                room_id,
                content,
                timestamp_ms,
                is_todo,
                is_completed,
                is_pinned,
                tags,
                author_id,
                author_name,
            });
        }

        let backup = UnencryptedBackup {
            format: "notetosms_plaintext_backup_v1".to_string(),
            version: 1,
            exported_at: current_time_ms(),
            rooms,
            notes: unencrypted_notes,
        };

        let json_string = serde_json::to_string_pretty(&backup)?;
        std::fs::write(destination_path, json_string.as_bytes())
            .context("Failed to write unencrypted backup file")?;

        Ok(())
    }

    /// Import a backup (either encrypted SQLite .vault or plaintext JSON) with transaction safety.
    pub fn import_backup(&mut self, source_path: &str, passphrase: Option<String>) -> Result<()> {
        let dest_key = self.get_active_key()?;

        let file_bytes = std::fs::read(source_path)
            .context(format!("Failed to read backup file at {source_path}"))?;

        let is_sqlite = file_bytes.len() >= 16 && &file_bytes[..16] == b"SQLite format 3\0";

        if is_sqlite {
            let src_conn = Connection::open(source_path)
                .context("Failed to open source SQLite backup database")?;

            let (salt_vec, verify_ciphertext, verify_nonce_vec): (Vec<u8>, Vec<u8>, Vec<u8>) = src_conn
                .query_row(
                    "SELECT salt, verify_ciphertext, verify_nonce FROM vault_metadata WHERE id = 1",
                    [],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .context("Failed to read vault_metadata from backup database. Is this a valid notetosms backup?")?;

            if salt_vec.len() < SALT_LEN || verify_nonce_vec.len() < NONCE_LEN {
                return Err(anyhow!("Corrupt vault metadata in backup database"));
            }

            let mut src_nonce = [0u8; NONCE_LEN];
            src_nonce.copy_from_slice(&verify_nonce_vec[..NONCE_LEN]);

            let src_key = if let Some(ref pass) = passphrase {
                if pass.trim().is_empty() {
                    return Err(anyhow!("Passphrase cannot be empty"));
                }
                let derived = derive_key(pass, &salt_vec)?;
                let decrypted = decrypt_payload(&derived, &verify_ciphertext, &src_nonce)
                    .map_err(|_| anyhow!("Incorrect passphrase for backup vault"))?;
                if decrypted.as_slice() != VERIFY_MAGIC_PLAINTEXT {
                    return Err(anyhow!("Verification magic failed for backup vault"));
                }
                derived
            } else {
                if let Ok(decrypted) = decrypt_payload(dest_key, &verify_ciphertext, &src_nonce) {
                    if decrypted.as_slice() == VERIFY_MAGIC_PLAINTEXT {
                        dest_key.clone()
                    } else {
                        return Err(anyhow!("Backup was encrypted with a different passphrase. Please provide the backup passphrase."));
                    }
                } else {
                    return Err(anyhow!("Backup was encrypted with a different passphrase. Please provide the backup passphrase."));
                }
            };

            let mut src_rooms = Vec::new();
            {
                let mut stmt = src_conn.prepare("SELECT id, name, icon, color, created_at, sort_order FROM rooms")?;
                let rows = stmt.query_map([], |r| {
                    Ok(RoomItem {
                        id: r.get(0)?,
                        name: r.get(1)?,
                        icon: r.get(2)?,
                        color: r.get::<_, i64>(3)? as u32,
                        created_at: r.get(4)?,
                        sort_order: r.get(5)?,
                        encryption_key: None,
                        share_ticket: None,
                        is_background_sync_enabled: true,
                    })
                })?;
                for r in rows {
                    src_rooms.push(r?);
                }
            }

            let mut notes_to_import = Vec::new();
            {
                let mut stmt = src_conn.prepare(
                    "SELECT id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags FROM notes"
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

                for row in rows {
                    let (id, room_id, cipher, n_vec, timestamp_ms, is_todo, is_completed, is_pinned, tags) = row?;
                    if n_vec.len() < NONCE_LEN {
                        continue;
                    }
                    let mut n = [0u8; NONCE_LEN];
                    n.copy_from_slice(&n_vec[..NONCE_LEN]);

                    let decrypted = decrypt_payload(&src_key, &cipher, &n)?;
                    let content = String::from_utf8(decrypted.to_vec())
                        .map_err(|e| anyhow!("Corrupt UTF-8 note content in backup: {e}"))?;

                    notes_to_import.push((id, room_id, content, timestamp_ms, is_todo, is_completed, is_pinned, tags));
                }
            }

            let current_dest_key = self.get_active_key()?.clone();
            let tx = self.conn.transaction()?;

            for room in src_rooms {
                tx.execute(
                    "INSERT OR IGNORE INTO rooms (id, name, icon, color, created_at, sort_order)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![room.id, room.name, room.icon, room.color as i64, room.created_at, room.sort_order],
                )?;
            }

            for (id, room_id, content, timestamp_ms, is_todo, is_completed, is_pinned, tags) in notes_to_import {
                let (cipher, nonce) = encrypt_payload(&current_dest_key, content.as_bytes())?;
                tx.execute(
                    "INSERT OR REPLACE INTO notes (id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                    params![id, room_id, cipher, nonce.to_vec(), timestamp_ms, is_todo, is_completed, is_pinned, tags],
                )?;
            }

            tx.commit()?;
            self.rebuild_temp_fts()?;
            Ok(())
        } else {
            let backup: UnencryptedBackup = serde_json::from_slice(&file_bytes)
                .context("Invalid backup file: File is not an encrypted SQLite database or recognized JSON format")?;

            let current_dest_key = self.get_active_key()?.clone();
            let tx = self.conn.transaction()?;

            for room in backup.rooms {
                tx.execute(
                    "INSERT OR IGNORE INTO rooms (id, name, icon, color, created_at, sort_order)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                    params![room.id, room.name, room.icon, room.color as i64, room.created_at, room.sort_order],
                )?;
            }

            for note in backup.notes {
                let (cipher, nonce) = encrypt_payload(&current_dest_key, note.content.as_bytes())?;
                let tags_str = note.tags.join(",");
                tx.execute(
                    "INSERT OR REPLACE INTO notes (id, room_id, ciphertext, nonce, timestamp_ms, is_todo, is_completed, is_pinned, tags)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
                    params![
                        note.id,
                        note.room_id,
                        cipher,
                        nonce.to_vec(),
                        note.timestamp_ms,
                        if note.is_todo { 1 } else { 0 },
                        if note.is_completed { 1 } else { 0 },
                        if note.is_pinned { 1 } else { 0 },
                        tags_str
                    ],
                )?;
            }

            tx.commit()?;
            self.rebuild_temp_fts()?;
            Ok(())
        }
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

    #[test]
    fn test_export_and_import_room_invite() {
        let mut store_a = EncryptedStore::open_in_memory().expect("open memory a");
        store_a.unlock_or_init("secret_a").unwrap();

        // Create a custom room in store A
        let custom_room = store_a
            .create_room("project-alpha", "Project Alpha", "rocket_launch", 0xFF10B981)
            .unwrap();

        // Export invite from store A
        let invite_uri = store_a.export_room_invite(&custom_room.id).unwrap();
        assert!(invite_uri.starts_with("notetosms://join?data="));

        // Parse invite without modifying
        let parsed = EncryptedStore::parse_room_invite_data(&invite_uri).unwrap();
        assert_eq!(parsed.room_id, "project-alpha");
        assert_eq!(parsed.name, "Project Alpha");
        assert_eq!(parsed.icon, "rocket_launch");
        assert_eq!(parsed.color, 0xFF10B981);

        // Store B imports the invite
        let mut store_b = EncryptedStore::open_in_memory().expect("open memory b");
        store_b.unlock_or_init("secret_b").unwrap();

        let imported_room = store_b.import_room_invite(&invite_uri).unwrap();
        assert_eq!(imported_room.id, "project-alpha");
        assert_eq!(imported_room.name, "Project Alpha");

        // Re-importing should return existing room idempotently
        let reimported = store_b.import_room_invite(&invite_uri).unwrap();
        assert_eq!(reimported.id, "project-alpha");
    }

    #[test]
    fn test_encrypted_and_plaintext_backup_and_restore_roundtrip() {
        let temp_dir = std::env::temp_dir();
        let src_db_path = temp_dir.join(format!("test_src_{}.db", generate_random_id()));
        let encrypted_backup_path = temp_dir.join(format!("test_backup_{}.vault", generate_random_id()));
        let plaintext_backup_path = temp_dir.join(format!("test_backup_{}.json", generate_random_id()));
        let dest_db_path_1 = temp_dir.join(format!("test_dest1_{}.db", generate_random_id()));
        let dest_db_path_2 = temp_dir.join(format!("test_dest2_{}.db", generate_random_id()));

        // Setup store A with data
        let mut store_a = EncryptedStore::open(&src_db_path).unwrap();
        store_a.unlock_or_init("vault_password_123").unwrap();
        store_a.create_room("work", "Work Room", "work", 0xFF6366F1).unwrap();
        let note1 = store_a.save_note("general", "General Note 1").unwrap();
        let note2 = store_a.save_note("work", "Secret Project Plan").unwrap();

        // 1. Test Encrypted Backup Export
        store_a.export_encrypted_backup(encrypted_backup_path.to_str().unwrap()).unwrap();
        assert!(encrypted_backup_path.exists());

        // 2. Test Plaintext JSON Backup Export
        store_a.export_unencrypted_backup(plaintext_backup_path.to_str().unwrap()).unwrap();
        assert!(plaintext_backup_path.exists());

        // 3. Restore Encrypted Backup into fresh Store B (providing backup passphrase)
        let mut store_b = EncryptedStore::open(&dest_db_path_1).unwrap();
        store_b.unlock_or_init("vault_password_123").unwrap();
        store_b.import_backup(encrypted_backup_path.to_str().unwrap(), Some("vault_password_123".into())).unwrap();

        let b_general_notes = store_b.get_notes("general").unwrap();
        assert!(b_general_notes.iter().any(|n| n.id == note1.id && n.content == "General Note 1"));
        let b_work_notes = store_b.get_notes("work").unwrap();
        assert!(b_work_notes.iter().any(|n| n.id == note2.id && n.content == "Secret Project Plan"));

        // 4. Restore Encrypted Backup into fresh Store C (different master password)
        let mut store_c = EncryptedStore::open(&dest_db_path_2).unwrap();
        store_c.unlock_or_init("different_master_pass_999").unwrap();
        // Mismatched passphrase should fail when None or wrong password
        assert!(store_c.import_backup(encrypted_backup_path.to_str().unwrap(), Some("wrong_pass".into())).is_err());
        // Providing original backup password succeeds
        store_c.import_backup(encrypted_backup_path.to_str().unwrap(), Some("vault_password_123".into())).unwrap();
        let c_work_notes = store_c.get_notes("work").unwrap();
        assert!(c_work_notes.iter().any(|n| n.id == note2.id && n.content == "Secret Project Plan"));

        // 5. Restore Plaintext JSON Backup into fresh memory store
        let mut store_d = EncryptedStore::open_in_memory().unwrap();
        store_d.unlock_or_init("memory_pass").unwrap();
        store_d.import_backup(plaintext_backup_path.to_str().unwrap(), None).unwrap();
        let d_work_notes = store_d.get_notes("work").unwrap();
        assert!(d_work_notes.iter().any(|n| n.id == note2.id && n.content == "Secret Project Plan"));

        // Clean up temp files
        let _ = std::fs::remove_file(src_db_path);
        let _ = std::fs::remove_file(encrypted_backup_path);
        let _ = std::fs::remove_file(plaintext_backup_path);
        let _ = std::fs::remove_file(dest_db_path_1);
        let _ = std::fs::remove_file(dest_db_path_2);
    }

    #[test]
    fn test_vault_initialization_check() {
        let temp_dir = std::env::temp_dir();
        let db_path = temp_dir.join(format!("test_init_check_{}.db", current_time_ms()));
        let db_path_str = db_path.to_str().unwrap();

        // 1. Before file exists
        assert!(!check_vault_file_initialized(db_path_str));

        // 2. Open but not yet initialized (fresh schema only)
        {
            let store = EncryptedStore::open(&db_path).unwrap();
            assert!(!store.is_vault_initialized().unwrap());
        }
        assert!(!check_vault_file_initialized(db_path_str));

        // 3. Initialize with passphrase
        {
            let mut store = EncryptedStore::open(&db_path).unwrap();
            store.unlock_or_init("master_passphrase_456").unwrap();
            assert!(store.is_vault_initialized().unwrap());
        }

        // 4. File on disk is now initialized
        assert!(check_vault_file_initialized(db_path_str));

        let _ = std::fs::remove_file(db_path);
    }
}
