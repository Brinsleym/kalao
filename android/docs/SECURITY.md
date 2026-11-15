# Security

## Lessons from the POC
- **The POC committed `.env` with live secrets** (DB, NextAuth, Google, Spotify, Genius, Meilisearch, host-metrics token). Rotate all of them. Kalao `.gitignore`s `.env*`, `key.properties`, `*.jks` and `extensions/`. CI runs `gitleaks` on every push. **The Kalao repo is public**, so a leaked secret is immediately exposed. `poc-webapp/` is never published.
- The POC committed copyrighted MP3s. No media goes in git.
- Private extensions live outside the public repo (a separate private repo, or the git-ignored `android/extensions/`). CI fails if any `*.kalaoext` or `extensions/**` file is tracked.
- With no accounts, Kalao stores no personal data on any server. The attack surface is the device, extensions, the stem server and the release pipeline.

## Threat model
| Asset | Threat | Control |
| --- | --- | --- |
| Device and user data | A malicious or buggy extension | QuickJS sandbox, no FS/process access, host allowlist checked after every redirect, memory/time/response caps, per-extension storage, secrets redacted from logs, an install prompt showing hosts and permissions, signed repositories with pinned keys (EXTENSIONS.md §5, §7) |
| Extension supply chain | A tampered package or repo | SHA-256 + ed25519 signature per package; trust-on-first-add of the repo key; a key change requires re-trust; no remote code loading at runtime |
| User-entered keys (Azure, stem, extension secrets) | Extraction from the device or a backup | Keystore-backed secure storage; never logged; never written to backups; `allowBackup="false"` |
| Backup files | Tampering, or a malicious file opened by the user | Zip limits as for extensions (entry count, size, no `..`/absolute paths/symlinks); per-entry SHA-256 checked before applying; SQLite opened read-only and validated (`PRAGMA integrity_check`, schema version) before merge; restore in one transaction after a safety copy |
| Backup privacy | A backup shared by mistake | Contains no credentials; the export screen says backups are unencrypted |
| Stem API keys | Sharing / leaking | argon2-hashed at rest; bound to 1 device hash; per-key rate and size limits; revocation and device reset via the admin CLI |
| Uploaded audio (remote stems) | Retention / leak | TLS; deleted after download or after 24 h at most; no audio in logs; worker containers with no outbound network access |
| Stem server | Injection, abuse | `sqlx` typed queries, validation at the boundary, Redis rate limits, body and upload size limits; `/metrics` behind an admin token |
| Party (LAN) | A rogue joiner | Join code + host approval; per-room token in the QR; guests can only queue, never control playback settings |
| Releases | A tampered APK | Signed with one release key kept outside the repo (CI secret); SHA-256 checksums published with every GitHub Release; the update check only links to the release page |
| Lyrics from extensions | Markup injection | Normalised to plain text in `kalao-core::text`; never rendered as HTML |

## Android specifics
- `allowBackup="false"`; network security config: HTTPS only, no user CAs in release builds (developer mode allows `localhost` for extension development only).
- R8 enabled; the Rust `.so` is stripped; 16 KB page alignment.
- The microphone permission is requested only when scoring or monitoring is enabled. Nothing is recorded or uploaded without an explicit user action.
- Remote stem processing uploads the user's audio, so the first use shows a one-time explanation of what is sent and how long it is kept.
- No analytics, telemetry or crash-reporting SDKs.
