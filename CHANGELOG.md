# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Encrypted Vault Backup & Restore**: Export full Argon2id and ChaCha20-Poly1305 encrypted SQLite snapshot backups (`.vault`) using WAL checkpointing and SQLite `VACUUM INTO`.
- **Plaintext JSON Backup & Export**: Option to export decrypted notes and channels as human-readable JSON (`.json`) with an interactive security confirmation warning.
- **Storage Access Framework (SAF) & Native Sharing**: Integrated `file_picker` and `share_plus` for direct file saving and native Android share sheet workflows without requiring legacy `WRITE_EXTERNAL_STORAGE` permissions.
- **Bidirectional Live P2P Note Sync via Iroh**: Real-time note exchange across devices over QUIC bi-streams (`SyncPacket`), automatic catch-up history sync upon peer handshake, and live broadcasting of newly created, edited, and completed notes without requiring manual reload.
- **Live Presence Tracking & Room Membership**: 5-second background heartbeat loop, 15-second peer silence timeout sweeps, and dynamic top app bar subtitle displaying `"$totalCount members • $onlineCount online • E2E Encrypted"` with active online status indicator.
- **Remote Typing Indicators & Join Announcements**: Real-time typing status broadcast across connected room members and centered notification pills in the chat timeline when devices join.
- **Backup & Restore UI**: Modern Material 3 Dark Slate bottom sheet accessible from both the channel list and conversation detail menus with multi-passphrase support.
- **Dedicated Auth Screens & Gate**: Split startup flow into `CreateVaultScreen` (for fresh database setup) and `UnlockVaultScreen` (focused single password input with biometric option), routed by on-disk `is_vault_initialized()` validation.
- **Combined Invitation Tickets (`RoomShareTicket`)**: Thread invitations now bundle cryptographic keys (`ChaCha20-Poly1305`) and active Iroh network dialing addresses (`NodeAddr` with Relay URLs and Direct SocketAddrs) into `notetosms://join?ticket=...` for seamless NAT-traversing multi-device pairing.
- **Dedicated P2P Service Layer (`P2pService`)**: Extracted clean, singleton Dart service for ticket export/import, room events streaming, and direct QUIC stream typing broadcasts.

### Fixed
- **Android Recents Duplicate Cards**: Removed `android:documentLaunchMode="always"` and configured `android:launchMode="singleTask"` in `AndroidManifest.xml` so the app reuses existing tasks in the Android switcher.
- **Empty Chat Share & QR Rendering**: Replaced static placeholders with asynchronous `FutureBuilder` QR code generator, interactive action buttons, and top-right app bar quick toggle.
- **Cross-Device P2P Dialing & Sync Connection**: Enabled `RelayMode::Default` on endpoint initialization for WAN DERP relay traversal, fixed bi-stream reader drop on history sync request, and implemented immediate local SQLite persistence and live stream notification on ticket import.

## [0.2.1] - 2026-08-25

### Added
- Static global Tokio multi-thread runtime (`OnceLock<Runtime>`) preventing reactor panics across async Iroh P2P channels.
- Remote peer typing state tracking with auto-reset decay (3s).

### Fixed
- Local self-typing indicator glitching decoupled from incoming note bubbles.
- Release automation script argument splitting for multi-word tag release notes.

## [0.2.0] - 2026-08-25

### Added
- Android 11+ System Bubbles support for floating conversation chat heads (`notetosms://room/{roomId}`).
- Live P2P encrypted chat synchronization using Iroh and ChaCha20-Poly1305.
- Direct sideloaded in-app update installer via GitHub Releases API and `ota_update`.
