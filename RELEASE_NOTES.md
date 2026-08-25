### What's New in v0.2.1

#### ⚡ Rust Engine & Tokio Runtime Stability
- **Static Multi-Threaded Tokio Runtime**: Lazily initialized Tokio runtime (`crate::get_runtime()`) to safely drive asynchronous P2P network listeners, QUIC connection handlers, and peer note broadcasting.
- **Safe Note Persistence**: Decoupled database note saving from async P2P broadcasts to completely eliminate `there is no reactor running` panics.

#### 💬 Chat UI & Typing Indicator Decoupling
- **Decoupled Local Input Bar**: The local `MessageInputBar` no longer renders a ghost "Drafting note..." typing bubble for the active user.
- **Remote Peer Typing Indicators**: The typing indicator bubble now only activates when receiving verified incoming typing events from remote peers whose client ID differs from the local device ID.
- **Auto-Reset & Room Isolation**: Remote typing indicators automatically dismiss on message receipt, peer disconnect, room change, or a 3-second inactivity timeout.

#### 🛠️ Android Release & Build System Enhancements
- **ProGuard / R8 Optimization**: Added `-dontwarn` rules for OkHttp and security providers to guarantee seamless release compilation and APK packaging.
- **AGP 8+ Compatibility**: Dynamic subproject namespace enforcement and minimum compileSdk 34 boost for legacy plugins (`ota_update`).
