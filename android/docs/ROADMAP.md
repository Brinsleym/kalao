# Roadmap

Milestones are ordered by dependency. Each one ends with a working, tested build. Feature numbers refer to FEATURES.md.

| M | Name | Scope | Exit criteria |
| --- | --- | --- | --- |
| **M0** | Foundations | Top-level `rust_backend/` in the Mornye template (`core`, `network`, `mobile`, `bindgen`), `scripts/build_rust_backend.sh` and `check_rust_backend.sh`; Flutter project (`com.brinsley.kalao`) with the `kalao/backend` channel and Kotlin UniFFI handler; `libkalao_mobile.so` for arm64-v8a/armeabi-v7a/x86_64; CI (fmt, clippy, cargo test, flutter analyze/test, APK build, gitleaks, no-extensions-tracked check); l10n scaffold, theme | A Dart → Kotlin → Rust call on an emulator; CI green |
| **M1** | Local player | 1.1–1.3, 1.5–1.7; 2.1–2.3, 2.7; 6.1, 6.2 (local); 9.1 (4 languages), 9.2, 9.4 | Imported local songs (original + instrumental) play with all lyric layers; POC pinyin/bracket/section fixtures pass |
| **M2** | Timed lyrics | 2.6, 2.8, 2.9, 2.13 | LRC import; auto-follow within ±30 ms; the tap-to-time editor produces enhanced LRC |
| **M3** | Modes | 3.1, 3.2, 1.4, 6.5, 9.3, 2.4, 2.5 | Learn mode and OG Karaoke mode usable end to end; **first GitHub Release** |
| **M4** | Library, backup, about | 6.3, 6.7; 7.1–7.6; 9.5–9.8 | A backup made on one device restores on another (merge and replace), with no secrets inside; scheduled backup runs; update check links to the latest release |
| **M5** | Extensions | 5.1–5.5, 2.10, 2.11, 1.8, 6.2 (extensions), 6.4, 6.6; `kalao-ext` CLI | The owner's private lyrics and metadata extensions install from a signed repo and work; the public sample extension and EXTENSIONS.md are published |
| **M6** | Stems + translation | 4.1–4.4, `stem-server/` (gateway, worker, key CLI, metrics); 2.12 (`kalao-providers`: MyMemory + Azure, after Q12); more UI languages | On-device separation benchmarked on 3 reference devices; a remote key binds to one device and falls back cleanly; translation respects the user's monthly budget and falls back to MyMemory |
| **M7** | Scoring | 3.3, 3.4 | Real-time pitch line and score; monitoring latency measured |
| **M8** | Parties | 8.1–8.4, 3.5, 8.5 | A 5-guest party over LAN. Then start `desktop/` (`kalao-desktop` C ABI) and `web/` |

**Distribution:** GitHub Releases only, from M3 onwards. Each release has signed per-ABI and universal APKs, SHA-256 checksums and a changelog. There are no store builds.
