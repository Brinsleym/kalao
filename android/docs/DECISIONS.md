# Decisions

## Owner decisions (2026-11-15)

| # | Question | Decision |
| --- | --- | --- |
| Q1 | Backend | **Rust.** Originally a Rust account server; superseded by Q13: there is no account server. The only server is the optional stem server (Rust gateway) |
| Q2 | Identity | Product **Kalao** (ka-la-oh); application ID **`com.brinsley.kalao`** |
| Q3 | Content sourcing / scraping | **Mornye-style extensions.** All scrapers are user-installable extensions made by the owner, kept **private**, never in the public repo. The extension framework and the authoring docs are public (EXTENSIONS.md) |
| Q4 | Stem separation | **On-device** by default. A separate **stem server** (Docker) accepts unique, 1-device-limited API keys, which are given to donors. No paywall, and no in-app donation checks |
| Q5 | Translation | **Azure AI Translator** (F0, 2M chars/month), **MyMemory** fallback. With no server (Q13), both are called from the device; Azure uses a key the user enters (see Q12) |
| Q6 | Repo layout | `desktop/` and `web/` get their own top-level folders, separate from `poc-webapp/` |
| Q7 | Pricing | **None.** One non-intrusive "Support Kalao" link; no popups or prompts. Tiers and licensing from the POC roadmap are dropped |
| Q8 | Shared Rust code | **Mornye's `rust_backend/` template**, at the top level (`karaoke/rust_backend/`), shared by `android/`, `desktop/` and `web/` (ARCHITECTURE.md §3) |
| Q9 | Server song catalog | **Dropped** |
| Q10 | Region limiting | **Dropped** |
| Q11 | Distribution and payments | **GitHub Releases only.** No Google Play, no other stores. Donations only through the external link `https://ko-fi.com/brinsley`, never in-app |
| Q13 | Accounts | **None.** No sign-in (Google or otherwise), no account server, no sync. Everything runs on-device; libraries move between devices with backup and restore (FEATURES.md §7) |
| Q14 | Licence | **GPL-3.0** (the `LICENSE` in `Brinsleym/kalao`); `[workspace.package] license = "GPL-3.0-only"`. Dependencies and stem models must be GPL-3.0-compatible |

## Open questions

| # | Question | Recommendation | Blocks |
| --- | --- | --- | --- |
| Q12 | **Whose Azure quota?** Without a server, the owner's Azure key can't be kept secret (anything in a public app can be extracted). So Azure needs a key from each user, and the default is MyMemory | Ship as written: MyMemory by default with no setup, plus an optional "Azure Translator key" field (each user can create their own free F0 resource). If you'd rather share your own 2M-char quota with everyone, the only safe way is a tiny stateless translation proxy: no accounts and no user data, just a cache and a rate limit. Say if you want that | M6 |

## Architecture decision records

**ADR-001 Flutter + Rust, Mornye `rust_backend/` template.** *Accepted (Q8).*

**ADR-002 No Kalao account server.** All app data is local, owned by `kalao-mobile`. The only Kalao-run service is the stem server, which knows API keys and device hashes, never people. *Accepted (Q13).*

**ADR-003 (revised) Bindings follow Mornye:** UniFFI Kotlin bindings from `kalao-mobile`, reached from Flutter through a MethodChannel/EventChannel; a C ABI `kalao-desktop` crate reached through `dart:ffi`; one JSON method table shared by both. This replaces the earlier flutter_rust_bridge plan. *Accepted (Q8).*

**ADR-004 Audio engine in Rust (cpal/AAudio).** Needed for synchronised stems, crossfade, key/tempo and mic pitch; `audio_service` still owns the media session. *Accepted.*

**ADR-005 Time-stretch: Signalsmith Stretch (MIT) preferred over Rubber Band.** Both are GPL-3.0-compatible; Signalsmith is lighter and keeps licensing simple. *Confirm at M3.*

**ADR-006 SQLite owned by Rust (`rusqlite`, in `kalao-mobile`, as in Mornye).** *Accepted.*

**ADR-007 No DRM.** There is no first-party hosted content to protect. *Accepted.*

**ADR-008 Content access happens on the device through extensions.** Kalao ships no scrapers. Extensions run in a QuickJS sandbox (`rquickjs`, as in Mornye) with declared host allowlists. Each extension's author is responsible for its terms of use. *Accepted (Q3).*

**ADR-009 Stem separation via ONNX Runtime on-device; Demucs on the GPU server.** One output format (Opus stems keyed by the source SHA-256), whichever path produced them. Remote always falls back to local. *Accepted (Q4).*

**ADR-010 (revised) Translation is called from the device by `kalao-providers`.** Azure with the user's own key and a user-set monthly budget, MyMemory otherwise; a device-local cache per line text. *Accepted (Q5, Q13); the quota owner is open (Q12).*

**ADR-011 Backup and restore instead of sync.** A versioned `.kalaobackup` zip (SQLite snapshot + manifest, optional media), merge or replace on restore, never containing secrets. *Accepted (Q13).*

**ADR-012 GitHub Releases is the only distribution channel.** Signed APKs (per-ABI and universal) with published SHA-256 checksums; an optional in-app update check that only links to the release page. *Accepted (Q11).*
