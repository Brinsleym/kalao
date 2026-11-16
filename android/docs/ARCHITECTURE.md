# Architecture

Kalao copies Mornye's internal architecture: the same layers, the same transport between Dart and Rust, the same split of data ownership, and the same folder and file conventions. Kalao-specific code (karaoke audio engine, lyric annotation, stems, scoring, parties) is added at the seams Mornye already has. What is copied from which Mornye file is listed in [MORNYE_REUSE.md](MORNYE_REUSE.md); libraries and versions in [LIBRARIES.md](LIBRARIES.md); how each subsystem works in [IMPLEMENTATION.md](IMPLEMENTATION.md).

## 1. System overview

```
┌───────────────────────────────── Android device ─────────────────────────────────┐
│ Flutter (Dart)                                                                   │
│  screens/ widgets/ providers/ (Riverpod 3) controllers/ services/ models/ theme/ │
│  services/platform_bridge.dart ── PlatformBridge: the only caller of the backend │
│  services/backend/backend_channel.dart ── BackendChannel (MethodChannel | FFI)   │
│        │ MethodChannel "com.brinsley.kalao/backend" + progress EventChannels      │
│ Kotlin host (android/app/src/main/kotlin/com/brinsley/kalao/)                     │
│  MainActivity: nativeBackendMethods (SAF, services, OS) │ everything else ──►     │
│  src/rust/kotlin/SelectedCoreBackend.kt → UniFFI bindings (JNA) on Dispatchers.IO │
│  BackgroundWorkService (ref-counted foreground service: stems, import, backup)    │
│        │ JNA                                                                      │
│ Rust: rust_backend/ → libkalao_mobile.so                                          │
│  kalao-mobile (UniFFI API, native data jobs) → audio · stems · extensions ·       │
│  providers (MyMemory) · party · core · network                                    │
└──────────┬────────────────────────┬──────────────────────────┬────────────────────┘
           │ extension fetch        │ MyMemory                 │ optional donor API key
           ▼ (allowlisted hosts)    ▼ api.mymemory.translated  ▼
       third-party sites                                  Kalao stem server (stem-server/)
```

There is no account server. The only Kalao-run service is the optional stem server.

## 2. Repository layout (mirrors Mornye's root)

```
karaoke/                         # git root of kalaoapp/Kalao
├── rust_backend/                # shared Cargo workspace (§4), Mornye template
├── scripts/                     # build_rust_backend.sh, check_rust_backend.sh, build_android.sh, check_backend_apk.py
├── android/                     # the Flutter app for Android (this project)
│   ├── lib/  test/  integration_test/  assets/  third_party/
│   ├── android/                 # Gradle host (Mornye's android/ folder)
│   ├── pubspec.yaml  analysis_options.yaml  l10n.yaml  .fvmrc
│   ├── docs/                    # these documents
│   └── extensions/              # git-ignored private extensions
├── desktop/  web/               # later
├── stem-server/                 # Rust gateway + Python worker (Docker)
├── .github/workflows/           # ci.yml, release.yml (from Mornye)
├── LICENSE (GPL-3.0)  NOTICE (Kalao + Mornye attribution)  README.md
```

Mornye keeps one Flutter project at its root for every platform. Kalao keeps one Flutter project per platform folder (Q6), so `desktop/` will be a second Flutter project that reuses `android/lib/` through a shared Dart package extracted when desktop starts (`packages/kalao_app/`). Until then all Dart code lives in `android/lib/`.

## 3. Flutter app (`android/lib/`), same folders as Mornye

| Folder | Role (as in Mornye) | Kalao contents |
| --- | --- | --- |
| `main.dart`, `app.dart` | Startup, `ProviderScope`, `MaterialApp.router`, `_routerProvider` with `initialLocationForAppState` (`/setup` → `/tutorial` → `/whats-new` → `/`) | Same flow |
| `constants/` | `app_info.dart` (version, repo URLs, donation URL), `language_choices.dart` | `AppInfo.donateUrl = https://ko-fi.com/brinsley`, `AppInfo.githubRepo = kalaoapp/Kalao` |
| `models/` | Plain data, `json_serializable` (`settings.dart` + `.g.dart`, `track.dart`, `extension.dart`, `theme_settings.dart`) | `settings.dart`, `song.dart`, `lyrics_layers.dart`, `stem_job.dart`, `party.dart`, `extension.dart`, `theme_settings.dart` |
| `services/` | All non-UI logic; one file per concern; large services split with `part` files | Mornye services kept (§MORNYE_REUSE), plus `karaoke_deck.dart`, `lyrics_annotation_service.dart`, `stem_service.dart`, `scoring_service.dart`, `party_host_service.dart`, `party_guest_service.dart` |
| `services/backend/` | `BackendChannel`, `MethodChannelBackend`, `RustFfiBackend`, transports | Copied unchanged (renamed) |
| `services/platform_bridge.dart` (+ `platform_bridge/` parts) | Typed static methods over `backendChannel`, JSON decoding in isolates, `__json_file` spill handling | Same; Kalao methods grouped in parts: `platform_bridge/player.dart`, `lyrics.dart`, `stems.dart`, `extensions.dart`, `backup.dart`, `party.dart` |
| `providers/` | Riverpod `Notifier`s and providers, thin over services | `settings_provider`, `theme_provider`, `music_player_provider`, `playback_provider`, `local_library_provider`, `extension_provider` (+ `_priority`), `repo_provider`, `lyrics_translation_provider`, `listening_statistics_provider`, `stems_provider`, `party_provider`, `karaoke_mode_provider` |
| `controllers/` | Multi-step UI flows and mixins | `selection_mode_mixin`, `extension_action_forms`, `extension_auth_launcher`, `open_audio_controller`, `player_track_navigation`, `lyrics_sync_editor_controller`, `restore_controller` |
| `screens/` | Top-level screens; `main_shell.dart`; `settings/` pages | `main_shell` (Home, Library, Queue, Extensions, Settings), `now_playing_screen` (Learn / Karaoke layouts), `setup_screen`, `tutorial_screen`, `whats_new_screen`, `settings/*` |
| `widgets/` | Design-system widgets (`app_*`, `expressive_*`) and feature widgets | Mornye design-system widgets and lyrics widgets reused; Kalao adds `ruby_lyric_line`, `pitch_lane`, `stem_mix_slider`, `countdown_overlay`, `party_qr_card` |
| `theme/` | Theme layer (`app_tokens`, `app_theme`, `app_motion`, `dynamic_color_wrapper`, `material_expressive`) | Material style only (Mornye's iOS glass style is not copied) with Kalao tokens |
| `l10n/` | `arb/app_<locale>.arb`, generated `app_localizations.dart`, `supported_locales.dart` | en, zh_Hans, zh_Hant, ja (then ko, es, fr) |
| `utils/` | `logger.dart` (`AppLogger`), `lyrics_parser.dart`, `lyrics_timeline.dart`, `synced_lyrics_scroll.dart`, `file_access.dart`, … | Reused; Kalao adds `ruby_segments.dart` |
| `routes/` | Route objects for non-shell routes (`now_playing_route.dart`) | Same |

Rules carried over from Mornye: no business logic in widgets or providers; services own I/O; every backend call goes through `PlatformBridge`; long JSON is decoded off the UI isolate; desktop-only or Android-only paths are guarded with `isDesktopPlatform` / `Platform.isAndroid`.

## 4. Rust workspace (`rust_backend/`), Mornye template

Workspace settings copied from Mornye: `resolver = "3"`, edition 2024, `rust-version = "1.99.0"`, toolchain `1.99.1` (`profile = "minimal"`, rustfmt + clippy), `[workspace.dependencies]` with exact pins, `[workspace.lints]` with `unsafe_code = "deny"`, `[patch.crates-io] rustix = { path = "vendor/rustix-1.1.6" }` (Android < 30 `statx` SIGSYS fix), `NOTICE`, `README.md` crate map. Licence `GPL-3.0-only`.

| Crate | Package | Origin | Owns | Depends on |
| --- | --- | --- | --- | --- |
| `crates/core` | `kalao-core` | Mornye `core` (subset) + new | JSON helpers (`lenient_deserialize!`), filenames, tags and covers, lyrics (`lrc`, `matching`, `payloads/ttml`), progress types; **new:** `sync` (time → line/word), `annotate` (pinyin, er-hua, brackets, furigana, romaji, Trad↔Simp), `text` (section markers, normalisation), `score` maths, `song_key` | none |
| `crates/network` | `kalao-network` | Mornye `network`, unchanged | Cancellable HTTP client, cookies, DNS, TLS roots, request policy (`GrantedOrigin`), URL parts | none |
| `crates/providers` | `kalao-providers` | Mornye `providers` (structure only) | Built-in service clients: **MyMemory** translation, request coalescer | core, network |
| `crates/extensions` | `kalao-extensions` | Mornye `extensions` (subset) | QuickJS runtime, host APIs, manifest, package, repository, storage, manager, lyrics/metadata/health backends | core, network, providers |
| `crates/audio` | `kalao-audio` | new | Karaoke engine: synchronised stem decoders, mixer, crossfade, key/tempo, AAudio output and input, pitch tracking, reverb, recording | core |
| `crates/stems` | `kalao-stems` | new | ONNX separation, model manager, resumable chunked jobs, FLAC output, remote stem-server client | core, network |
| `crates/party` | `kalao-party` | Mornye `link` (server, tls, pairing, ws, mdns modules) | LAN party host: HTTPS + WebSocket, PIN pairing, room state machine, lyrics web view for TVs | core |
| `crates/mobile` | `kalao-mobile` | Mornye `mobile` (skeleton) | UniFFI API (`uniffi::setup_scaffolding!`), `invoke_application` dispatch, cancellation, logging (`LogBuffer`), progress subscriptions, native data jobs on detached SQLite files, backup archive codec, extension manager glue, player/stems/party handles | everything above |
| `crates/desktop` | `kalao-desktop` | Mornye `desktop` | C ABI (`kalao_init/call/cancel/subscribe/unsubscribe/free`) over the same method table. Built when `desktop/` starts | mobile |
| `crates/bindgen` | `kalao-bindgen` | Mornye `bindgen`, unchanged | UniFFI CLI for Kotlin bindings | uniffi only |
| `crates/ext-cli` | `kalao-ext` | new | Extension author CLI (validate, test, pack, sign) | extensions |

`crates/mobile/uniffi.toml`: `package_name = "com.brinsley.kalao.backend"`, `cdylib_name = "kalao_mobile"`. Dependencies point downward; `core` and `network` depend on no workspace crate.

## 5. Dart ↔ Kotlin ↔ Rust transport (Mornye's native channel contract)

- **One backend channel:** `MethodChannel("com.brinsley.kalao/backend")`. Dart side: `PlatformBridge` → `backendChannel` (`MethodChannelBackend` on Android, `RustFfiBackend` on desktop).
- **Android routing:** `MainActivity` keeps a `nativeBackendMethods` set for calls Kotlin must handle (SAF, foreground services, installer, screen-awake, OS info). Every other name goes to `dispatchBackendApplication` in `src/rust/kotlin/SelectedCoreBackend.kt`, which runs `coreBackend.invokeApplication(method, argsJson)` on `Dispatchers.IO`. `MainActivityRoutingTest` fails if the set and the `when` labels differ. Handlers live in `MainActivity*Calls.kt` extension files grouped by area (Lifecycle, Service, Saf, Import, Player, Party).
- **Replies:** JSON text, decoded by Dart in an isolate. Replies over 256 KiB use the **`__json_file` spill** (`{"__json_file": path}` in `cacheDir`, read and deleted by Dart; stale files swept at engine setup).
- **Errors:** `result.error(code, message)`; `foreground_service_start_not_allowed` when Android refuses a service start, otherwise `ERROR`.
- **Host → Dart events** over the same channel (`setMethodCallHandler`): `extensionAuthCallbackReceived`, `stemJobChanged`, `partyGuestEvent`, `audioRouteChanged`.
- **Progress streams:** dedicated `EventChannel`s, as Mornye's `download_progress_stream` and `library_scan_progress_stream`: `player_position_stream` (engine clock, 30 Hz while visible), `pitch_stream` (mic + reference, 50 Hz while scoring), `stem_progress_stream`, `import_progress_stream`, `party_event_stream`. Rust pushes into a `ProgressSubscription`; Kotlin forwards to the sink.
- **Native data jobs:** `runNativeDataJob(request, requestId)` / `cancelNativeDataJob` for heavy work on detached SQLite snapshots (import scans, search-key rebuilds, backup and restore, stats aggregation), with a cancellation registry (`NativeDataJobs.kt`).
- **Bindings:** UniFFI Kotlin bindings are generated into `rust_backend/target/bindings/kotlin/` and loaded through JNA (`net.java.dev.jna:jna:5.19.1@aar`; ProGuard keeps `com.sun.jna`). Gradle's `buildRustBackend` task runs `scripts/build_rust_backend.sh android` before `preBuild`.

## 6. Data ownership (Mornye's split)

| Data | Owner | Storage |
| --- | --- | --- |
| Library schema (songs, media files, lyrics, annotations, favorites) | **Dart** `services/library_schema.dart` + `library_database.dart` (sqflite) | `kalao_library.db` |
| Play history and scores | Dart `history_database.dart` / `history_schema.dart` | `kalao_history.db` |
| Queue, playback session, UI state | Dart `app_state_database.dart`, `library_queue_store.dart`, `playback_session_writer.dart` | `kalao_app_state.db` |
| Settings | Dart `models/settings.dart` (`json_serializable`) via `settings_provider` | `shared_preferences` (`preference_blob_store.dart` for large blobs) |
| Secrets (stem key, install ID, extension secrets) | Dart `secure_storage_options.dart` | `flutter_secure_storage` (Keystore) |
| Heavy jobs over the databases | Rust `kalao-mobile` native data jobs | Detached private copies, published back by Dart (`LibraryNativeAdapter`, `sqlite_native_snapshot.dart`) |
| Extension packages, storage and cookies | Rust `kalao-extensions` | App-private files |
| Stem models, stem job checkpoints, stem files | Rust `kalao-stems` | App-private files, keyed by audio SHA-256 |
| Translation cache | Dart `lyrics_translation.dart` (Mornye's file cache) | App support dir |

The schema stays owned by Dart (as in Mornye: "the schema remains owned by Dart; scans enter through one worker call and never transfer a library-sized row list to UI").

## 7. Playback architecture

- Mornye's player roles are kept, sized for one deck (as built in M1): `PlayerController` (`providers/player_provider.dart`) takes the place of `music_player_service.dart` + `playback_session_restore.dart`; `KalaoAudioHandler` (`services/playback_handler.dart`) the place of `playback_notification.dart`, on the published `audio_service` package (Mornye's fork patches serve Android Auto and browsing, which Kalao does not have); `audio_session` focus handling as in Mornye.
- Mornye's `PlaybackDeck` interface (`services/playback_deck.dart`) is the seam. Kalao adds **`KaraokeDeck`**, backed by `kalao-audio` through `PlatformBridge`, as the only deck on Android (M1 does not need the `QueuedPlaybackDeck` interface; it is introduced if desktop adds a second deck). Mornye's `audioplayers` deck is not used: two independent players cannot keep stems sample-aligned, and they have no pitch shift or mic path.
- `KaraokeDeck` adds Kalao calls beyond the interface: `setStemGains`, `switchTrack(original|instrumental)`, `setKey(semitones)`, `setTempo(rate)`, `setLoop(a, b)`, `startScoring`, `startMonitoring`.
- The engine clock is the single source of truth for lyric sync: `player_position_stream` carries `{positionMs, clockMonotonicNs}` and Dart interpolates between events for 60 fps rendering.

## 8. Lyrics pipeline

1. **Source:** imported file, pasted text, extension result, or edited draft.
2. **Parse:** Rust `native_lyrics` (LRC, enhanced LRC, TTML; from Mornye) → `ParsedLyrics` JSON; Dart `utils/lyrics_parser.dart` (Mornye) builds `LyricLine { time, end, text, words, romanization, romanizationWords, translation, voice }`.
3. **Normalise:** `kalao-core::text` (section markers incl. Chinese markers, alternative brackets, whitespace).
4. **Annotate:** `annotateLyrics(lines, sourceLang)` → per-line layers (`pinyin`, `furigana`, `romaji`, `traditional`, `simplified`) as ruby segments aligned to character ranges. Kalao extends Mornye's `LyricLine` with `layers: Map<LyricLayerKind, LyricLayer>`; `romanization`/`romanizationWords` are filled from the pinyin or romaji layer so Mornye's `aligned_lyric_pronunciation.dart` works unchanged.
5. **Store:** `lyric_doc` + `lyric_annotation` rows (Dart schema); `origin = human` layers are never overwritten.
6. **Render:** Mornye's `player_lyrics*.dart`, `lyrics_timeline.dart` (`LyricDisplayLayout`), `synced_lyrics_scroll.dart`, `player_lyrics_word_sweep.dart`, plus Kalao's `ruby_lyric_line.dart` for multi-layer ruby.
7. **Translate:** Mornye's `lyrics_translation.dart` (distinct lines, chorus sent once, SHA-256 cache key) with the MyMemory client instead of `lyrics_ai_client.dart`.

## 9. Android host (`android/android/app/src/main/kotlin/com/brinsley/kalao/`)

Copied from Mornye and trimmed: `KalaoApplication.kt` (crash capture), `MainActivity.kt` + `MainActivityLifecycleCalls.kt`, `MainActivityServiceCalls.kt`, `MainActivitySafCalls.kt` / `SafIo` / `SafTreePicker` / `SafLeases` (import and backup folders), `MainActivityProgressStreams.kt`, `MainActivitySmallChannels.kt`, `MainActivityExtensionIntents.kt`, `ExtensionAuthCallbacks.kt`, `BackgroundWorkService.kt`, `ForegroundServiceStartPolicy.kt`, `ForegroundWorkLock.kt`, `AppCrashReporter.kt`, `NativeCrashTrace.kt`, `AudioRouteInfo.kt`, `src/rust/kotlin/{SelectedCoreBackend,RustCoreBackendApplication,NativeDataJobs}.kt`. New: `MainActivityPlayerCalls.kt` (audio permissions, AAudio session ids), `MainActivityPartyCalls.kt` (multicast lock, Wi-Fi state), `ApkInstallCalls.kt` (update installer).

Manifest: `minSdk 26`, `targetSdk 37`, `compileSdk 37`, NDK `30.0.16248370`, 16 KB page-aligned `.so`, ABI splits (arm64-v8a, armeabi-v7a, x86_64) plus universal. Permissions: `INTERNET`, `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` + `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `WAKE_LOCK`, `RECORD_AUDIO` (requested only for scoring/monitoring/recording), `CHANGE_WIFI_MULTICAST_STATE` (parties), `REQUEST_INSTALL_PACKAGES` (user-started updates), `CAMERA` (QR join, requested on use). No Google Play services.

## 10. Stem server (`stem-server/`)

Separate deployment with its own Cargo workspace: Rust (axum) gateway with key whitelist, device binding, rate limits and job API; Python worker running Demucs on a GPU via a Redis queue; `stem-admin` CLI; Prometheus `/metrics` behind an admin token. See STEM_SEPARATION.md and API.md.

## 11. Ownership table

| Concern | Single owner |
| --- | --- |
| Backend transport | `services/backend/` + `platform_bridge.dart` (Dart), `SelectedCoreBackend.kt` (Android), `kalao-mobile` (Rust) |
| Audio clock and output | `kalao-audio` |
| Player state, queue, media session | `music_player_service.dart` (Mornye) via `KaraokeDeck` |
| Active lyric line/word | `kalao-core::sync` (engine side) mirrored by `lyrics_timeline.dart` for layout |
| Annotation generation | `kalao-core::annotate` |
| Library and history schemas | Dart services (`library_schema.dart`, `history_schema.dart`) |
| Stem separation (local + remote) | `kalao-stems` |
| Third-party content access | extensions, via `kalao-extensions` host fetch only |
| Translation | `kalao-providers` (MyMemory client) + `lyrics_translation.dart` (dedupe, cache, alignment) |
| Backup layout and categories | Dart `backup_service.dart`; archive codec in `kalao-mobile::native_backup` |
| Updates | `update_checker.dart` + `apk_downloader.dart` (Mornye) |
| Stem API key validity and device binding | stem server gateway |
