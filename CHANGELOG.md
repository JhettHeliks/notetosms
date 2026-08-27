# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Material 3 Expressive Note Bubbles (`NoteBubble`)**: Redesigned chat bubbles with asymmetrical corner radii (22px with 4px corner notch / 12px smooth grouped corner), `primaryContainer` outgoing styling, `surfaceContainerHighest` incoming styling with sender header, and inline timestamp with lock icon badge.
- **Platform-Specific Message Interactions & Zero Long-Press**:
  - **Desktop (Windows/macOS/Linux)**: Swiping is disabled; right-clicking triggers a native cursor-anchored context menu (`showMenu`) for Pinning, Copying, Editing, and Deleting notes.
  - **Mobile (Android/iOS)**: Exclusive swipe-to-action gestures enclosed in `ClipRect` with bounded background styling (no drawer bleeding):
    - **Swipe Right**: Quick-pin / unpin toggle with haptic feedback tick (`HapticFeedback.mediumImpact()`).
    - **Swipe Left**: Reveals inline Copy, Edit, and Delete action triggers with auto-snap back.
  - **Zero Long-Press**: Removed all long-press listeners and modal bottom sheets across all platforms.
- **Consecutive Message Grouping**: In-timeline clustering compares author and timestamp within 120 seconds, automatically collapsing vertical spacing from 8.0px to 2.0px, hiding redundant remote sender headers, and smoothing bubble notch radii.
- **Material You Dynamic Theming & Wallpaper Extraction**: Added `dynamic_color` support in `main.dart` with `DynamicColorBuilder`, adapting theme colors from device wallpaper on Android 12+ or custom user-selected palette presets.
- **Custom Accent Palette Presets & Settings Screen**: Created `AppearanceScreen` (`lib/ui/screens/appearance_screen.dart`) and `ThemeProvider` with 5 custom presets (Deep Ocean, Emerald, Sunset Amber, Obsidian Violet, Crimson), ThemeMode selection (System/Light/Dark), and persistence via `SharedPreferences`.
- **Zlib Compressed P2P Invitation Tickets**: Compressed `RoomShareTicket` JSON payloads in Rust using `flate2::write::ZlibEncoder` and URL-safe Base64 encoding, shortening ticket lengths by ~40% and making QR codes much easier to scan at distance.
- **De-densified Aesthetic Squircle QR Codes**: Upgraded QR code rendering across cards and dialogs to `pretty_qr_code` (`PrettyQrView.data`) with `PrettyQrSmoothSymbol(roundFactor: 0.8)` that dynamically harmonizes with the active Material 3 primary color.
- **`BouncyPressable` Motion Widget**: Reusable spring-physics press wrapper (`lib/ui/widgets/motion/bouncy_pressable.dart`) — scales to 0.96 on touch-down (100ms, `easeOutCubic`) and springs back with overshoot on release (200ms, `easeOutBack`). Fires `HapticFeedback.lightImpact` on tap.
- **`FadeSlideTransition` Motion Widget**: Entry animation wrapper (`lib/ui/widgets/motion/fade_slide_transition.dart`) — slides child up 16 px and fades from 0→1 over 260ms with `easeOutQuart`. Supports a configurable `delay` for staggered list entrances.
- **Bouncing Scroll Physics**: `ChatScreen` message list now uses `BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())` for rubbery overscroll consistent with 120Hz displays.
- **Staggered Bubble Entrance Animations**: Each `ChatBubble` in the timeline is wrapped in `FadeSlideTransition` with an 18ms-per-index stagger (capped at 300ms), so the initial note list glides into view.
- **Spring-Physics AppBar & Send Buttons**: Search, QR invite, and send buttons are all wrapped in `BouncyPressable`; tool palette buttons in `MessageInputBar` upgraded from `InkWell` to `BouncyPressable`.
- **Frosted Glass Bottom Sheet (`BackupRestoreDialog`)**: `BackdropFilter(ImageFilter.blur(sigmaX: 8, sigmaY: 8))` applied behind the modal, paired with a 350ms `easeInOutCubicEmphasized` slide-up transition.
- **Animated QR Plate (`ShareThreadDialog`)**: `AnimatedSwitcher` wraps the `FutureBuilder` states — when the invite ticket resolves, the QR card scales from 0.85→1.0 with `easeOutBack` and fades in.
- **Predictive Back Page Transitions**: `pageTransitionsTheme` in `AppTheme` sets `PredictiveBackPageTransitionsBuilder` on Android (Android 14 native spring gesture), `CupertinoPageTransitionsBuilder` on iOS, and `ZoomPageTransitionsBuilder` on Fuchsia.
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
- **Android OS Error 1 (Operation Not Permitted) & Iroh Netcheck SELinux**: Added required Android network permissions (`ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_NETWORK_STATE`) in `AndroidManifest.xml`, allowing unprivileged untrusted apps (SDK 34) to query network state and resolve STUN/DERP without SELinux `/proc/net/route` permission crashes.
- **In-App APK Updater & Android 11-14 Installation Flow**: Configured `FileProvider` (`${applicationId}.fileprovider` with `file_paths.xml`), added `android.permission.REQUEST_INSTALL_PACKAGES`, implemented native Kotlin installer bridge in `MainActivity.kt` (`com.notetosms/updater`), and added interactive permission prompts in `UpdateDialog` to gracefully guide users to enable "Install unknown apps" before triggering package installations.
- **Android Recents Duplicate Cards**: Removed `android:documentLaunchMode="always"` and configured `android:launchMode="singleTask"` in `AndroidManifest.xml` so the app reuses existing tasks in the Android switcher.
- **Empty Chat Share & QR Rendering**: Replaced static placeholders with asynchronous `FutureBuilder` QR code generator, interactive action buttons, and top-right app bar quick toggle.
- **Cross-Device P2P Dialing & Sync Connection**: Enabled `RelayMode::Default` on endpoint initialization for WAN DERP relay traversal, fixed bi-stream reader drop on history sync request, and implemented immediate local SQLite persistence and live stream notification on ticket import.
- **AppBar Layout Overflow**: Wrapped the member status subtitle in an `Expanded` widget with `maxLines: 1` and `TextOverflow.ellipsis` to permanently eliminate the 51 px yellow/black layout overflow banner.
- **Deduplicate Peer Join Events**: Join announcements are now gated by a `_announcedPeerIds` set in `_ChatScreenState` (and `known_members` in Rust) so a peer emits exactly one "joined the thread" pill per session, regardless of reconnects or duplicate `PeerJoin` packets.

### Changed
- **Local vs Remote Chat Bubbles**: Notes authored by the local device now align right with `colorScheme.primaryContainer`; notes from remote peers align left with `colorScheme.surfaceContainerHighest` and display the sender's nickname above the first bubble in each cluster, matching the visual language of major encrypted-messaging apps.


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
