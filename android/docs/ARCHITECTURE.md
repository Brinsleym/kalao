# Architecture

## 1. System overview

```
┌──────────────────────── Android device ─────────────────────────────────┐
│  Flutter UI (Dart)                                                      │
│   screens · widgets · Riverpod · go_router · l10n (ARB)                 │
│   plugins: audio_service, secure storage, camera (QR), url_launcher     │
│                    │  MethodChannel / EventChannel ("kalao/backend")    │
│  Kotlin host (android/app): channel handler → UniFFI Kotlin bindings    │
│                    │  JNI                                               │
│  Rust backend (rust_backend/ → libkalao_mobile.so per ABI)              │
│   audio · stems (ONNX) · extensions (QuickJS) · library/SQLite · backup │
│   providers (translation) · network · party (LAN)                       │
└──────┬──────────────────────┬───────────────────────┬───────────────────┘
       │ extension fetch      │ translation           │ HTTPS (optional, donor API key)
       ▼ (allowlisted hosts)  ▼ Azure (user key) /    ▼
   third-party sites            MyMemory           ┌──────── Kalao stem server ──────────┐
                                                   │ Rust (axum) gateway: key check,     │
                                                   │ device binding, rate limit, jobs    │
                                                   │ Python worker (Demucs, GPU) via Redis│
                                                   │ Postgres (keys) · Redis · temp files│
                                                   └─────────────────────────────────────┘
```

There is **no Kalao account server**. The only Kalao-run service is the optional stem server. With no network, Kalao plays local and downloaded songs, separates stems on-device, and renders all annotations.

## 2. Folder layout

```
karaoke/                       # public Kalao repo root (poc-webapp/ excluded; see DEV_SETUP.md)
├── poc-webapp/                # old Next.js POC (reference only, never published)
├── rust_backend/              # shared Cargo workspace, Mornye template (§3)
├── scripts/                   # build_rust_backend.sh, check_rust_backend.sh
├── android/                   # THIS project: Flutter app for Android
├── desktop/                   # future: Windows/Linux/macOS Flutter client (uses crates/desktop)
├── web/                       # future: web client
└── stem-server/               # remote stem server: Rust gateway + Python worker (Docker)
```

### `android/`

```
android/
├── lib/
│   ├── main.dart · app.dart
│   ├── router/            # go_router routes
│   ├── l10n/arb/          # app_en, app_zh_Hans, app_zh_Hant, app_ja …
│   ├── backend/           # typed Dart client over the "kalao/backend" channel (hand-written,
│   │                      # one method per Rust API call; the same method names as crates/desktop)
│   ├── providers/         # Riverpod: thin wrappers over backend calls and event streams
│   ├── controllers/       # multi-step flows (sync editor, party host, extension install, restore)
│   ├── services/          # audio_service handler, QR, stem foreground job, file import, backup schedule
│   ├── features/          # home/ search/ library/ player/ learn/ karaoke/ queue/ stems/ stats/
│   │                      # extensions/ party/ backup/ settings/ sync_editor/ about/
│   └── widgets/           # shared design-system components
├── android/               # Gradle host (applicationId com.brinsley.kalao, minSdk 26)
│   └── app/src/main/kotlin/…/backend/   # channel handler calling the UniFFI bindings
├── assets/                # fonts (CJK subsets), icons
├── test/ · integration_test/ · docs/
└── extensions/            # git-ignored: private extensions checkout (never committed)
```

## 3. Rust workspace (`rust_backend/`, Mornye template)

Same shape as Mornye's `rust_backend/`: one workspace at the top level, `crates/<name>` with package `kalao-<name>`, edition 2024, resolver 3, toolchain pinned in `rust-toolchain.toml` (Rust 1.99.1 with rustfmt and clippy), shared versions in `[workspace.dependencies]` (exact pins for security-sensitive and FFI crates), `[workspace.package]` for version/edition/licence, `[workspace.lints]` with `unsafe_code = "deny"` and audited local exceptions only, `vendor/` for patched crates when needed, `NOTICE` for third-party notices, and a `README.md` crate map.

| Crate | Package | Owns | Depends on | Key dependencies (pin at implementation) |
| --- | --- | --- | --- | --- |
| `crates/core` | `kalao-core` | Domain types (`Song`, `LyricDoc`, `LyricLine`, `WordTiming`, `Annotation`); `sync` (time → active line/word); `lrc`; `annotate` (pinyin, tone marks, er-hua, alternative brackets, furigana/romaji, Trad↔Simp); `text` (section markers, normalisation); `lang`; `score` maths; backup manifest types. **No I/O** | none | `serde`, `thiserror`, pinyin and Japanese-reading dictionaries (e.g. `pinyin`, `lindera`), `whatlang` |
| `crates/network` | `kalao-network` | Shared cancellable HTTP transport: client, cookies, TLS roots, request policy, retry/backoff, URL and query helpers | none | `hyper-util`, `hyper-rustls`, `rustls-native-certs`, `tokio` |
| `crates/audio` | `kalao-audio` | Engine thread: synchronised decoders (original/instrumental/vocal), blend, crossfade, key/tempo, output, mic capture, YIN/pYIN pitch, reverb | core | `symphonia`, `cpal` (AAudio), `rubato`, time-stretch (ADR-005), `ringbuf` |
| `crates/stems` | `kalao-stems` | On-device separation: model manager (download, verify, select), chunked inference with overlap-add, resumable job state; client for the remote stem server | core, network | `ort` (ONNX Runtime; NNAPI/XNNPACK), `symphonia` |
| `crates/providers` | `kalao-providers` | Built-in service clients: Azure AI Translator and MyMemory (budget tracking, fallback, request coalescing) | core, network | — |
| `crates/extensions` | `kalao-extensions` | Extension runtime (see EXTENSIONS.md): package loader, manifest validation, QuickJS sandbox, host API (allowlisted fetch, storage, settings, login callbacks), capability dispatch, priority and fallback, repository index and signatures | core, network | `rquickjs`, `zip`, `ed25519-dalek`, `sha2`, `scraper` |
| `crates/party` | `kalao-party` | LAN party host and guest: WebSocket, mDNS, room state machine | core | `tokio-tungstenite`, `mdns-sd` |
| `crates/mobile` | `kalao-mobile` | **The UniFFI mobile API** (`uniffi::setup_scaffolding!`) and the app's data owner: library, SQLite schema and migrations, media and stem cache, lyric and annotation store, stats, backup and restore, settings, job orchestration, event streams. Built as `lib`, `cdylib` (`libkalao_mobile.so`) and `staticlib` | core, network, audio, stems, providers, extensions, party | `uniffi`, `rusqlite` (bundled), `zip` |
| `crates/desktop` | `kalao-desktop` | The C ABI for Windows/Linux/macOS, loaded by Flutter through `dart:ffi` (`kalao_init`, `kalao_call`, `kalao_cancel`, `kalao_subscribe`, `kalao_unsubscribe`, `kalao_free`). Dispatches the same method names as the Android channel as JSON; `src/dispatch.rs` is the single method table. The only crate allowed `unsafe` (in `src/ffi.rs`). Built when `desktop/` starts | mobile | — |
| `crates/bindgen` | `kalao-bindgen` | The UniFFI bindgen CLI, used only to generate the Kotlin bindings; its `cli` features never reach the shipped library | `uniffi` CLI only | `uniffi` (`cli`, `cargo-metadata`) |

**Dependency rule:** dependencies point downward. `core` and `network` depend on no workspace crate; `mobile` is the only crate the app links; `desktop` wraps `mobile`. CI enforces this with `cargo metadata`.

`web/` (later) needs a wasm build. Crates that compile to `wasm32` (`core`, and parts of `extensions` and `providers`) are kept free of native-only dependencies behind features; the web binding crate is designed when `web/` starts.

## 4. Flutter app

- **Backend calls:** `lib/backend/` sends `MethodChannel("kalao/backend")` calls; the Kotlin handler forwards them to the UniFFI bindings on a background executor and returns results. Streams (position, active lyric, pitch, job progress, party events) use an `EventChannel`. The method names and JSON shapes match `crates/desktop`, so `desktop/` reuses the Dart client with an FFI transport.
- **State:** Riverpod 3. Providers call `lib/backend/` and contain no business logic.
- **Navigation:** go_router. No auth or role guards.
- **Playback:** `services/audio_handler.dart` (`audio_service`) owns the media session, notification and focus, and forwards commands to the backend. The Rust engine produces the audio.
- **Long jobs:** stem separation runs in a foreground service (`mediaProcessing` type) with a progress notification. Scheduled backups run through WorkManager. Job state lives in Rust, so it survives process death.
- **Lyrics rendering:** `CustomPainter` word sweep. Ruby text (pinyin/furigana) is laid out from Rust-provided segments.
- **Extensions UI:** settings forms are generated from the manifest. The install flow shows publisher, permissions and requested hosts before installing.
- **Plugins:** `audio_service`, `audio_session`, `flutter_secure_storage`, `mobile_scanner` + `qr_flutter`, `permission_handler`, `url_launcher` (Ko-fi link, release page, extension logins), `file_picker` / SAF for import, export and backup folders, `workmanager`.

## 5. Key runtime flows

**Play (OG Karaoke):** `player.load(songId, mode)`. The library resolves the media (local file, cache, or an extension `audio` source) and the stems (cached, or "separate now?"). The engine plays the instrumental. The engine clock feeds `core::sync`, which drives the active-lyric stream; mic pitch goes to `core::score` and the pitch stream. At the end, a play record is stored locally.

**Original ↔ instrumental:** both decoders always run, and a switch is a 150 ms gain crossfade.

**Lyric fetch:** `lyrics.find(song)` → `kalao-extensions` asks every enabled `lyrics` extension in priority order (in parallel with a timeout). It ranks the results (synced > word-synced bonus > plain; title/artist/duration match), normalises them with `core::text`, stores them, and returns.

**Translation:** `lyrics.translate(song, lang)` → local cache first, then `kalao-providers`: Azure Translator with the user's own key while the user-set monthly budget allows, otherwise MyMemory. Results are cached on the device.

**Stems:** `stems.separate(song, prefer)`. With `prefer = remote` and an API key present, the audio is uploaded to the stem server and the stems are downloaded. On any failure, or by default, separation runs on-device. Details in STEM_SEPARATION.md.

**Backup:** `backup.export(target, options)` snapshots SQLite (online backup API), writes the manifest and data into a `.kalaobackup` zip, and streams it to the SAF target. `backup.preview(file)` / `backup.restore(file, mode)` validate the schema version and checksums, show the diff, and apply it in one transaction. Format in DATA_MODEL.md §3.

## 6. Stem server (`stem-server/`)

A separate deployment and the only Kalao-run service. A Rust gateway checks that an API key is whitelisted and bound to the calling device, rate-limits per key, accepts uploads, enqueues jobs in Redis, and serves the results. A Python worker runs Demucs on a GPU. Key issuance and monitoring use a CLI and an admin-token metrics endpoint. It has its own Cargo workspace and does not link the app crates. See STEM_SEPARATION.md.

## 7. Ownership table

| Concern | Single owner |
| --- | --- |
| Active lyric line/word | `kalao-core::sync` |
| Pinyin/furigana generation and alignment | `kalao-core::annotate` |
| Audio clock and output | `kalao-audio` |
| Media session, notification, focus | Flutter `services/audio_handler.dart` |
| Stem separation (local + remote choice) | `kalao-stems` |
| Talking to third-party content sites | extensions, via `kalao-extensions` host fetch only |
| Translation services and budget | `kalao-providers` |
| HTTP transport | `kalao-network` |
| Local persistence, backup and restore | `kalao-mobile` |
| Rust API surface for Android / desktop | `kalao-mobile` (UniFFI) / `kalao-desktop` (C ABI) |
| Stem API key validity and device binding | stem server gateway |
