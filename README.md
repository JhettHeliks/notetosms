# notetosms

<p align="center">
  <img src="web/icons/Icon-192.png" alt="notetosms Logo" width="96" height="96" />
</p>

<p align="center">
  <b>A private, encrypted, chat-style note-taking app powered by Flutter and Rust.</b>
</p>

<p align="center">
  <a href="https://github.com/JhettHeliks/notetosms/actions"><img src="https://img.shields.io/github/actions/workflow/status/JhettHeliks/notetosms/release.yml?branch=main&style=flat-square" alt="Build Status" /></a>
  <a href="https://github.com/JhettHeliks/notetosms/releases"><img src="https://img.shields.io/github/v/release/JhettHeliks/notetosms?include_prereleases&style=flat-square&color=blue" alt="Latest Release" /></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter" alt="Flutter" /></a>
  <a href="https://www.rust-lang.org"><img src="https://img.shields.io/badge/Rust-2021_Edition-DEA584?style=flat-square&logo=rust" alt="Rust" /></a>
  <a href="#license"><img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License" /></a>
</p>

---

## 📖 Overview

**notetosms** is an ultra-private, chat-inspired note-taking mobile application designed to mimic the intuitive flow of texting yourself while providing military-grade zero-knowledge encryption and offline-first peer-to-peer thread sharing.

Built with **Flutter (Material 3)** for fluid, dynamic user experience and a high-performance **Rust engine** connected via `flutter_rust_bridge` v2, **notetosms** ensures that your thoughts, checklists, secrets, and tags remain 100% encrypted, private, and under your control.

---

## ✨ Key Features

### 💬 Google Messages (Material 3) Chat UX
- **Dynamic Asymmetric Bubbles**: Styled with M3 container tokens (`primaryContainer`, `secondaryContainer`) and adaptive corner rounding (`BorderRadius.circular(20)` with flattened inner corners for clustered notes within 2 minutes).
- **Inline Pill Action Bar**: Expandable text input with a `+` quick tool modal for checklists (`[ ] `), tags (`#tag`), bullet lists (`- `), and a detached 48x48 animated microphone/send button.
- **Floating Date Pills**: Date separators with soft elevation (`Material(elevation: 1.5)`) and Material 3 typography.
- **Animated Typing Indicator**: 3-dot staggered bouncing wave indicator rendered in real-time when drafting notes.
- **Responsive Layout**: Seamless Master-Detail split pane on tablets and desktop screens (`>= 700px`), with bottom sheets and drawers on mobile screens.

### 🛡️ Zero-Knowledge Security & Storage
- **Argon2id Key Derivation**: Hardened password-based key derivation function protecting against brute-force attacks.
- **ChaCha20-Poly1305 AEAD**: Authenticated encryption for all note contents and P2P payloads.
- **Encrypted SQLite (SQLCipher)**: Offline-first storage powered by `rusqlite` with bundled SQLCipher.
- **FTS5 Encrypted Search**: Blazing-fast full-text search across all notes with tokenization and tag filtering.
- **`zeroize` Memory Scrubbing**: Secure wiping of cryptographic keys and passphrases in memory immediately after usage.

### 🌐 Peer-to-Peer Thread Sharing (Iroh QUIC)
- **Direct P2P Sync**: Real-time note thread synchronization over QUIC protocol with NAT traversal via `iroh-net`.
- **Zero-Cloud Architecture**: No central servers, accounts, or telemetry required.
- **Ticket & QR Code Invitations**: Generate secure base64 room tickets or scan QR codes using `mobile_scanner` to join shared threads.

### 🫧 Android 11+ System Bubbles (Floating Chat Heads)
- **Native Bubble Activity**: Open any room into a floating Android system chat head for rapid multitasking.
- **Deep Linking**: Full support for `notetosms://room/{roomId}` and `chatnotes://room/{roomId}` deep link routes.
- **Dynamic Shortcuts**: Native integration with `ShortcutManagerCompat` and `NotificationCompat.BubbleMetadata`.

### 🔄 In-App Self-Updater (Sideloaded APKs)
- **Direct GitHub Releases Sync**: Check for new beta and stable releases directly within the app without needing a computer.
- **Over-The-Air (OTA) Sideloading**: Streamlined download and native Android package installation (`REQUEST_INSTALL_PACKAGES`) powered by `ota_update`.
- **Live Progress & Release Notes**: Full visibility into update changelogs, download progress percentage, and package size.

---

## 🏗️ Architecture

```
notetosms/
├── lib/                             # Flutter Frontend (Dart)
│   ├── core/                        # Theme system & constants
│   ├── services/                    # Vault & Bubble method channels
│   ├── src/rust/                    # Generated flutter_rust_bridge bindings
│   ├── ui/
│   │   ├── dialogs/                 # Room creation, P2P tickets, QR scanner
│   │   ├── screens/                 # Main chat screen & responsive layouts
│   │   ├── views/                   # Conversation list, bubble view
│   │   └── widgets/                 # Chat bubbles, date headers, input bar
│   └── main.dart                    # Application entrypoint & routing
│
├── rust/                            # Core Backend Engine (Rust)
│   ├── src/
│   │   ├── api/notes.rs             # FRB v2 bridge interface
│   │   ├── db.rs                    # SQLCipher database manager & FTS5 search
│   │   ├── crypto.rs                # Argon2id & ChaCha20-Poly1305 AEAD
│   │   ├── p2p.rs                   # Iroh QUIC peer-to-peer sync engine
│   │   └── lib.rs                   # Module declarations
│   └── Cargo.toml                   # Rust dependencies
│
├── android/                         # Android Native Wrapper (Kotlin)
│   ├── app/src/main/kotlin/         # MainActivity & Bubble Notification channels
│   └── app/build.gradle.kts         # Custom APK naming & AAPT rules
│
├── scripts/                         # Build, packaging & release automation
│   ├── build_dist.ps1 / .sh         # Local APK compiler & SHA-256 sorter
│   └── release.ps1 / .sh            # SemVer tag & release manager
│
└── .github/workflows/               # GitHub Actions CI/CD pipeline
    └── release.yml                  # Automated release & APK packaging
```

---

## 🚀 Getting Started

### Prerequisites

Make sure you have the following installed on your development machine:

1. **Flutter SDK** (v3.11.4+ / stable channel)
   ```bash
   flutter doctor
   ```
2. **Rust Toolchain** (v1.75+ / stable)
   ```bash
   rustup default stable
   ```
3. **Android NDK & CMake** (for Android cross-compilation):
   - In Android Studio: *SDK Manager -> SDK Tools -> NDK & CMake*
   - Add Android targets to Rust:
     ```bash
     rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
     ```
4. **flutter_rust_bridge_codegen** (v2.12.0):
   ```bash
   cargo install flutter_rust_bridge_codegen --version 2.12.0
   ```

---

### Installation & Running Locally

1. **Clone the repository:**
   ```bash
   git clone https://github.com/JhettHeliks/notetosms.git
   cd notetosms
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Generate Flutter-Rust Bridge code:**
   ```bash
   flutter_rust_bridge_codegen generate
   ```

4. **Run on a connected device or emulator:**
   ```bash
   flutter run
   ```

---

## 🧪 Testing

Run the full automated testing suite across both Dart and Rust layers:

```bash
# Run Flutter unit & widget tests
flutter test

# Run Rust engine unit tests (Crypto, SQLCipher DB, P2P sync)
cargo test --manifest-path rust/Cargo.toml

# Run static analysis
flutter analyze
```

---

## 📦 Building & Distribution

We provide cross-platform packaging scripts to compile, sort, and calculate SHA-256 checksums for local release artifacts.

### Building APKs Locally

**PowerShell (Windows):**
```powershell
# Build Beta APK (universal)
.\scripts\build_dist.ps1 -Mode beta

# Build Production Release APK with split per ABI
.\scripts\build_dist.ps1 -Mode release -SplitPerAbi
```

**Bash (Linux / macOS):**
```bash
# Build Beta APK
./scripts/build_dist.sh --mode beta

# Build Production Release APK with split per ABI
./scripts/build_dist.sh --mode release --split-per-abi
```

Compiled APKs are organized directly into:
- `dist/betas/`
- `dist/releases/`

---

## 🏷️ Releasing & CI/CD

To cut a new release and trigger GitHub Actions automated multi-architecture packaging:

**Using Release Script:**
```powershell
# Bump version and push tag to GitHub
.\scripts\release.ps1 1.0.0-beta.1 -Push
```

GitHub Actions will automatically:
1. Verify static analysis and run unit tests.
2. Compile universal and split-per-ABI release APKs (`arm64-v8a`, `armeabi-v7a`, `x86_64`).
3. Generate SHA-256 checksums.
4. Publish a **GitHub Release** with all artifacts attached.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
