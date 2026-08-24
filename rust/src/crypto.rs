use anyhow::{anyhow, Result};
use argon2::{Argon2, Params};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Key, Nonce,
};
use rand::RngCore;
use zeroize::Zeroizing;

pub const SALT_LEN: usize = 16;
pub const NONCE_LEN: usize = 12;
pub const KEY_LEN: usize = 32;

/// Derive a 256-bit key from a user passphrase and salt using Argon2id.
/// Wrapped in Zeroizing to securely clear key memory upon drop.
pub fn derive_key(passphrase: &str, salt: &[u8]) -> Result<Zeroizing<[u8; KEY_LEN]>> {
    if passphrase.trim().is_empty() {
        return Err(anyhow!("Passphrase cannot be empty"));
    }
    if salt.len() < SALT_LEN {
        return Err(anyhow!("Salt must be at least {} bytes", SALT_LEN));
    }

    let mut key = [0u8; KEY_LEN];
    // Argon2id with recommended OWASP parameters for mobile/desktop security
    // Memory: 64MB (65536 KiB), Iterations: 3, Parallelism: 2
    let params = Params::new(65536, 3, 2, Some(KEY_LEN))
        .map_err(|e| anyhow!("Invalid Argon2 params: {e}"))?;
    let argon2 = Argon2::new(argon2::Algorithm::Argon2id, argon2::Version::V0x13, params);

    argon2
        .hash_password_into(passphrase.as_bytes(), salt, &mut key)
        .map_err(|e| anyhow!("Key derivation failed: {e}"))?;

    Ok(Zeroizing::new(key))
}

/// Generate cryptographically secure random salt (16 bytes).
pub fn generate_salt() -> [u8; SALT_LEN] {
    let mut salt = [0u8; SALT_LEN];
    rand::thread_rng().fill_bytes(&mut salt);
    salt
}

/// Generate cryptographically secure random nonce (12 bytes for ChaCha20-Poly1305).
pub fn generate_nonce() -> [u8; NONCE_LEN] {
    let mut nonce = [0u8; NONCE_LEN];
    rand::thread_rng().fill_bytes(&mut nonce);
    nonce
}

/// Encrypt plaintext using ChaCha20-Poly1305 AEAD.
/// Returns (ciphertext_with_tag, nonce).
pub fn encrypt_payload(key: &[u8; KEY_LEN], plaintext: &[u8]) -> Result<(Vec<u8>, [u8; NONCE_LEN])> {
    let cipher_key = Key::from_slice(key);
    let cipher = ChaCha20Poly1305::new(cipher_key);
    let nonce_bytes = generate_nonce();
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, plaintext)
        .map_err(|e| anyhow!("Encryption failed: {e}"))?;

    Ok((ciphertext, nonce_bytes))
}

/// Decrypt ciphertext using ChaCha20-Poly1305 AEAD.
/// Returns decrypted plaintext bytes wrapped in Zeroizing.
pub fn decrypt_payload(
    key: &[u8; KEY_LEN],
    ciphertext: &[u8],
    nonce_bytes: &[u8; NONCE_LEN],
) -> Result<Zeroizing<Vec<u8>>> {
    let cipher_key = Key::from_slice(key);
    let cipher = ChaCha20Poly1305::new(cipher_key);
    let nonce = Nonce::from_slice(nonce_bytes);

    let plaintext = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| anyhow!("Decryption failed: corrupted data or invalid key"))?;

    Ok(Zeroizing::new(plaintext))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_argon2_key_derivation_deterministic() {
        let pass = "correct horse battery staple";
        let salt = generate_salt();

        let key1 = derive_key(pass, &salt).expect("derivation 1 failed");
        let key2 = derive_key(pass, &salt).expect("derivation 2 failed");

        assert_eq!(*key1, *key2);

        let key_diff_pass = derive_key("different password", &salt).expect("derivation diff pass");
        assert_ne!(*key1, *key_diff_pass);
    }

    #[test]
    fn test_chacha20_encryption_decryption_roundtrip() {
        let key = [42u8; KEY_LEN];
        let original_data = b"Secret note to self: remember to buy milk & encrypt everything!";

        let (ciphertext, nonce) = encrypt_payload(&key, original_data).expect("encryption failed");
        assert_ne!(ciphertext, original_data);

        let decrypted = decrypt_payload(&key, &ciphertext, &nonce).expect("decryption failed");
        assert_eq!(*decrypted, original_data);
    }

    #[test]
    fn test_chacha20_decryption_tamper_fails() {
        let key = [42u8; KEY_LEN];
        let original_data = b"Private secret data";

        let (mut ciphertext, nonce) = encrypt_payload(&key, original_data).expect("encryption failed");
        
        // Tamper with ciphertext
        if let Some(first) = ciphertext.first_mut() {
            *first ^= 0xFF;
        }

        let result = decrypt_payload(&key, &ciphertext, &nonce);
        assert!(result.is_err());
    }

    #[test]
    fn test_chacha20_wrong_key_fails() {
        let key1 = [1u8; KEY_LEN];
        let key2 = [2u8; KEY_LEN];
        let original_data = b"Confidential memo";

        let (ciphertext, nonce) = encrypt_payload(&key1, original_data).expect("encryption failed");
        let result = decrypt_payload(&key2, &ciphertext, &nonce);
        assert!(result.is_err());
    }
}
