# AGENTS.md - Antigravity Agent Guidelines for notetosms

This document outlines persistent operating instructions and automated workflows for AI agents working in this repository.

---

## 🚀 Release Automation Workflow

Whenever the user requests:
- **"Release version X.Y.Z"** (or `X.Y.Z-beta.N`)
- **"Ship an update"**
- **"Publish a release"**

### Automatic Execution Steps:
1. **Prepare Release Notes**:
   - Write a concise bulleted summary of UI, engine, security, and feature changes.
   - Either pass the summary string directly to the release script, or write it into `RELEASE_NOTES.md` at the project root.
2. **Execute the Release Automation Script**:
   - On Bash / macOS / Linux:
     ```bash
     bash scripts/release.sh <version> "[optional release summary]"
     ```
   - On Windows (PowerShell):
     ```powershell
     powershell -ExecutionPolicy Bypass -File scripts/release.ps1 <version> "[optional release summary]"
     ```
3. **Automated Pipeline Execution**:
   - Updates `version: <version>+<build>` in `pubspec.yaml`.
   - Runs `flutter analyze lib/` to ensure 0 lint or compilation issues.
   - Stages `pubspec.yaml` and `RELEASE_NOTES.md`.
   - Commits with message `chore(release): bump version to v<version>`.
   - Creates annotated git tag `v<version>` embedding the release notes.
   - Pushes both the active branch and the new git tag to `origin`.
4. **CI/CD Changelog Generation**:
   - GitHub Actions workflow (`.github/workflows/release.yml`) automatically extracts commit subjects between tags, embeds release highlights, and publishes the full changelog body to GitHub Releases.
5. **Confirm and Report**:
   - Report the release status to the user and confirm that the GitHub Actions CI/CD release workflow has been triggered.

---

## 🛠️ Project Stack & Architecture Summary

- **App Name**: `notetosms` (`com.notetosms.app`)
- **Frontend**: Flutter (Material 3 Dark Slate Palette)
- **Engine**: Rust (SQLCipher, Argon2id, ChaCha20-Poly1305, Iroh QUIC P2P) connected via `flutter_rust_bridge` v2.
- **OTA Updates**: Sideloaded direct updates via GitHub Releases API and `ota_update`.
- **System Bubbles**: Android 11+ floating chat head support via custom method channels and deep links (`notetosms://room/{roomId}`).
