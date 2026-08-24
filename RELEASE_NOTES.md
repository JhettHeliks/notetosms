### What's New in v0.2.0

#### 🔗 Shared Threads & Channel Invitations
- **Share Thread Dialog**: Generate shareable encrypted channel invite tokens (`notetosms://join?data=...`) with embedded QR code previews and quick clipboard copy.
- **Join Thread Dialog**: Import encrypted channels with instant thread preview (channel name, icon, color, creation date), clipboard auto-paste, and camera QR code scanning.
- **Deep Link Integration**: Added routing support for `notetosms://join` and `chatnotes://join` deep links.

#### 🔄 In-App Self-Updates & Version History
- **App Updates & Version History Modal**: Browse GitHub release history, read changelogs, and view build details directly in the app.
- **Sideload Self-Updating**: Direct in-app APK download and package installation for Android with live progress indicator.

#### 💬 Chat UI & Android System Bubbles
- **Android System Bubbles**: Launch conversations into floating chat heads on Android 11+.
- **Google Messages (Material 3) Overhaul**: Sleek dark slate theme, asymmetrical bubble corners, and animated typing indicators.

#### 🔐 Security & Core Engine
- **Zero-Knowledge Storage**: Rust-powered SQLite with Argon2id key derivation, ChaCha20-Poly1305 AEAD, and memory zeroization.
- **Automated CI/CD Pipeline**: GitHub Actions release automation with SHA-256 checksums and automated release changelog extraction.
