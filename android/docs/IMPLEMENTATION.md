# Implementation Guide

How each subsystem is built. Structure and ownership are in ARCHITECTURE.md, the Mornye file map in MORNYE_REUSE.md, libraries in LIBRARIES.md, tasks in ROADMAP.md. Feature numbers refer to FEATURES.md.

## 1. Backend method table

Every Rust call is a name in `kalao-mobile`'s dispatch (`invoke_application(method, args_json) -> String`), mirrored by a typed static method in `PlatformBridge` and, later, in `kalao-desktop/src/dispatch.rs`. Names are camelCase like Mornye's. Groups:

| Group | Methods |
| --- | --- |
| Lifecycle | `initBackend(paths)`, `getBackendInfo`, `getLogs(sinceSeq)`, `clearLogs`, `releaseMemory` |
| Player | `playerLoad(songId, sources, startMs)`, `playerPlay`, `playerPause`, `playerSeek(ms)`, `playerStop`, `playerSetVolume`, `playerSetStemGains({vocals, instrumental, original})`, `playerSwitchTrack(kind)`, `playerSetKey(semitones)`, `playerSetTempo(rate)`, `playerSetLoop(startMs?, endMs?)`, `playerPrefetch(sources)`, `playerState` |
| Mic | `micStart(mode: scoring|monitoring|recording, options)`, `micStop`, `micSetMonitorMix(gain, reverb)`, `measureLatency` |
| Import | `probeAudio(path)` (tags, duration, codec, sha256), `readCover(path)`, `importConvert(path)` (via FFmpeg when Symphonia cannot decode) |
| Lyrics | `parseLyrics(raw, format?)`, `exportLyrics(doc, format)`, `annotateLyrics(lines, lang, layers)`, `convertChinese(text, to)`, `detectSections(lines)` |
| Translation | `translateLines(texts, src, dst, contactEmail?)` |
| Stems | `stemsModels`, `stemsDownloadModel(id)`, `stemsSeparate(songId, audioPath, sha256, prefer)`, `stemsCancel(jobId)`, `stemsJobs`, `stemsRemoteTestKey(key, deviceHash)` |
| Scoring | `melodyExtract(vocalPath, sha256)`, `scoringStart(songId)`, `scoringStop` → `ScoreReport` |
| Extensions | Mornye's names: `installExtension`, `uninstallExtension`, `listExtensions`, `setExtensionEnabled`, `setExtensionSetting`, `invokeExtensionAction`, `extensionHealth`, `addRepository`, `refreshRepository`, `searchLyrics(query)`, `searchMetadata(query)`, `getArtwork(ref)`, `resolveAudio(ref)` |
| Data jobs | `runNativeDataJob({kind, …}, requestId)`, `cancelNativeDataJob(requestId)` with kinds `rebuildSearchKeys`, `statsAggregate`, `backupWrite`, `backupInspect`, `backupRestore`, `pocImport` |
| Party | `partyHostStart(options)`, `partyHostStop`, `partyApproveGuest(id)`, `partyKick(id)`, `partyPush(event)`, `partyJoin(qrPayload)`, `partyLeave`, `partySend(event)` |

Kotlin-native names (in `nativeBackendMethods`): SAF picker and I/O (Mornye's), `startBackgroundWork/updateBackgroundWork/stopBackgroundWork` (Mornye's), `setScreenAwake`, `installApk(path)`, `acquireMulticastLock/releaseMulticastLock`, `getAudioRoute`, `openAppSettings`.

## 2. Audio engine (`kalao-audio`) and `KaraokeDeck` (1.1–1.5, 3.1, 3.2)

**Graph.** One output stream (cpal → AAudio, `PerformanceMode::LowLatency`, shared mode, f32, device rate, usually 48 kHz). Up to three sources per song: `original`, `instrumental`, `vocals`. Each source has a decoder thread (Symphonia) → `rubato` resampler → `ringbuf` SPSC buffer (≈ 500 ms). The audio callback pulls the same frame count from every buffer, applies per-source gains, sums into a stereo bus, runs the stretcher, then the output gain and a soft limiter.

**Source sets.**
- *Original + instrumental files* (user imported both): play both; `switchTrack` crossfades their gains.
- *Stems* (separated): play `vocals` + `instrumental`; "original" = both at unity, "instrumental" = vocals at 0, vocal-guide blend (1.3) = vocals at 0–100%.
- *Original only*: one source; karaoke features ask to separate first (4.1).

**Sync.** All decoders seek to the same sample index; a seek pauses the callback mix, flushes the buffers, repositions every decoder, prefills, then resumes. Gains change with a 10 ms ramp; `switchTrack` uses a 150 ms equal-power crossfade. Because every source passes through one bus and one clock, stems never drift.

**Key and tempo (1.4).** One Signalsmith Stretch instance on the mixed stereo bus: `setTransposeSemitones(k)` for ±6 semitones, time ratio for 50–150% tempo. When both are neutral the stretcher is bypassed (no latency, no CPU).

**Clock.** `position = sourceFramesConsumed / sourceRate − outputLatency`, where output latency comes from AAudio timestamps (`getTimestamp`) via cpal's output callback info. With tempo ≠ 1, source frames advance at `rate` per output frame. The engine publishes `{positionMs, monotonicNs, playing, rate}` on `player_position_stream` at 30 Hz (on change of state immediately); Dart interpolates with the monotonic clock for smooth 60 fps lyric sweeps.

**Loops (3.1).** `setLoop(a, b)`: when the source position reaches `b`, the engine performs an in-callback seek to `a` with a 20 ms crossfade. "Loop current line" sets `a/b` from the active line's start/end.

**KaraokeDeck.** `services/karaoke_deck.dart` implements Mornye's `QueuedPlaybackDeck`. `setNetworkSource`/local source calls map to `playerLoad`; `onPositionChanged`, `onPlayerStateChanged`, `onPlayerComplete` come from `player_position_stream`; `setPlaybackRate` maps to tempo; `queueNextSource` maps to `playerPrefetch` so the next song's decoders warm up. Mornye's `music_player_service.dart` is used with the deck factory returning only `KaraokeDeck`; AutoMix/gapless/EQ/ReplayGain parts are removed.

**Media session (1.5).** Unchanged from Mornye: `audio_service` fork, `audio_session` focus handling (duck on transient loss, pause on loss, pause on becoming-noisy), headset buttons, lock-screen metadata and artwork from `media_session_art_cache.dart`.

## 3. Import and library (1.6, 1.7, 6.1, 6.2)

1. *Import* (SAF picker via Mornye's `MainActivitySafTreePicker`/`file_picker`): user picks one or more audio files, optionally a folder.
2. *Pairing:* for each original, Kalao proposes an instrumental and a lyrics file from the same pick by filename similarity (`core::filename` normalisation, then tokens such as `instrumental`, `inst`, `karaoke`, `off vocal`, `backing`, `伴奏`, `カラオケ`, `オフボーカル`) and duration within ±2 s. The user confirms in the import sheet.
3. *Copy:* files are copied into app storage `media/<sha256>.<ext>` (hashing while copying). This makes backups, stems and restore independent of SAF permissions. Duplicates by hash are linked, not copied twice.
4. *Probe:* `probeAudio` reads tags, cover, duration and codec (Mornye `core::tags` and `mobile::tags`). Undecodable formats run `importConvert` once (FFmpeg → FLAC) and keep the converted file.
5. *Store:* Dart `library_database.dart` inserts `song` and `media_file` rows; the cover goes to Mornye's `cover_store`.
6. *Search keys (6.2):* a `rebuildSearchKeys` native data job writes `song_search` rows: normalised title/artist (Mornye `normalizeLookupText`), toneless pinyin and initials for Chinese, romaji for Japanese. Library search queries title, artist, pinyin, initials, romaji with prefix matching.
7. *Home (6.1):* Mornye's `home_tab` with Kalao sections: Continue singing (session restore), Recently played (`history_database`), Favorites, Recently added.

## 4. Lyrics (2.1–2.3, 2.6–2.8, 2.13)

**Model (Dart, extended from Mornye `lyrics_parser.dart`).**
```dart
class LyricLine {            // Mornye fields
  Duration time; Duration? end; String text; List<LyricWord> words;
  String? romanization; List<LyricWord> romanizationWords; String? translation; LyricVoice? voice;
  // Kalao additions
  LyricSection? section; bool sectionBreakBefore;
  Map<LyricLayerKind, LyricLayer> layers;   // pinyin, furigana, romaji, traditional, simplified
}
class LyricLayer { List<RubySegment> segments; LayerOrigin origin; }   // auto | human
class RubySegment { int start; int end; String reading; }              // UTF-16 range in text
```
Untimed lyrics use `time = Duration.zero` for every line and a `timed = false` flag on the document (manual stepping, 2.7).

**Parsing (2.8).** Rust `native_lyrics` (from Mornye): LRC with offsets and multiple time tags per line, enhanced LRC (`<mm:ss.xx>` word tags), TTML (Apple-style word timing, backing vocals as `voice`). Plain text: one line per row, blank rows = section breaks. Export: LRC (line timing) and enhanced LRC (word timing); TTML export is not planned.

**Sections (2.2).** `core::text::detect_sections`: markers like `[Verse]`, `Chorus:`, `(Bridge)`, `【副歌】`, `主歌`, `副歌`, `间奏`, `[サビ]` become `LyricSection` on the next line and are removed from the text; blank lines become `sectionBreakBefore`.

**Pinyin (2.3).** `core::annotate::pinyin`:
1. Segment with `jieba-rs` so polyphonic characters are read in context (`重要` zhòng vs `重新` chóng), then `pinyin` per word with heteronym selection from the word dictionary.
2. Tone diacritics: mark goes on `a`/`e`, on `o` in `ou`, otherwise on the last vowel; `ü` kept (`lǜ`), `v` input normalised to `ü`.
3. Er-hua: `儿` after a syllable merges into an `r` suffix on that syllable (`哪儿` → `nǎr`) when the word is in the er-hua list; otherwise `ér`.
4. Alternative brackets: text in `（）`/`()` that is a reading or alternate lyric is shown as defined by the POC rules.
5. Alignment: one `RubySegment` per Han character (or per word for multi-character readings); non-Han text gets no segment, so spaces and Latin never shift the alignment (the POC's whitespace bug).
The POC's pinyin, er-hua, bracket and whitespace test cases in `poc-webapp` are ported as Rust fixture tests (`crates/core/tests/annotate_pinyin.rs`) and must pass unchanged.

**Japanese (2.4).** `lindera` (IPADIC) tokenises and gives katakana readings → converted to hiragana; segments are emitted only over kanji runs (okurigana stays unannotated). `wana_kana` converts readings to romaji (Hepburn), one romaji word per token; this fills `romanizationWords` for Mornye's pronunciation layout.

**Traditional ↔ Simplified (2.5).** OpenCC conversion (`s2t`, `t2s`, `s2tw`, `s2hk`); the target variant is a setting.

**Display (2.1).** Each layer is toggled in the lyrics options sheet (Mornye `lyrics_options_button.dart`); order: reading above text (pinyin/furigana as ruby), romaji below, translation below. `ruby_lyric_line.dart` lays out ruby per segment using `TextPainter` measurements; it falls back to Mornye's `aligned_lyric_pronunciation.dart` when only word-level pronunciation exists. Text sizes S–XXL use Mornye's `lyrics_text_scale.dart`.

**Sync (2.6) and sweep (2.13).** Active line = binary search over line start times using the interpolated engine position plus a per-song offset (`lyric_doc.offset_ms`, adjustable ±5 s in 50 ms steps). Word sweep: Mornye `player_lyrics_word_sweep.dart` driven by word times; lines without word timing sweep linearly across the line duration in karaoke mode. Accuracy target ±30 ms against the engine clock (integration test with a click track and known LRC).

**Sync editor (2.9).** `lyrics_sync_editor_controller.dart` + an editor screen built from Mornye `lyrics_editor_sheet.dart` and `utils/lyrics_draft.dart`:
- *Line mode:* play; tap the big button at each line start; the release time of the hold is the line end (optional).
- *Word mode:* per line, tap for each word (Chinese/Japanese split per character or per jieba/lindera token).
- Tempo can be lowered to 50% while timing; taps are converted back to song time. Timestamps are corrected for touch latency (configurable, default 40 ms) and output latency.
- Nudge controls (±10/50 ms), replay-line, undo. Saved as a new `lyric_doc` version with `source = userEdited`; export to LRC/eLRC.

## 5. Modes (3.1, 3.2)

- **Learn mode** (default for songs in a language other than the UI language): original vocals; all annotation layers available; translation; loop current line; A–B repeat (long-press two lines); slow-down presets 50/75/90%; line stepping with ↑/↓ and tap.
- **OG Karaoke mode:** instrumental (or vocals at the user's guide level); lyrics in large type, two lines visible, word sweep; countdown dots for gaps ≥ 4 s before the next line (Mornye's `lyric_gap_indicator.dart`), including the intro; next singer from the queue shown at the end; mic monitoring and scoring when enabled (M7). Screen kept awake (Mornye `lyrics_screen_awake.dart`).
- Mode is a per-play choice on the now-playing screen; the last choice per song is remembered.

## 6. Queue (6.5) and favorites (6.3)

Mornye's queue model (`library_queue_store.dart`, `app_state_database.dart`, `queue_tab*`) with Kalao fields: `singer` (free text name, parties use the guest name) and `mode`. Favorites use Mornye's loved-tracks pattern on `song.id`.

## 7. Stats (6.7)

Mornye `listening_statistics.dart` over Kalao's `play` history rows (`song_id`, `started_at`, `duration_ms`, `mode`, `score`, `singer`): totals per day/week, top songs, most-practised (learn mode time), best scores. Aggregation is a `statsAggregate` data job for large histories.

## 8. Stems

See STEM_SEPARATION.md. Engine-facing details: stems are FLAC files `stems/<sha256>/{vocals,instrumental}.flac` at 44.1 kHz stereo; `playerLoad` receives them as `vocals` + `instrumental` sources. The job runs inside Mornye's `BackgroundWorkService` with kind `stems` (foreground type `dataSync`), notification text supplied by Dart, progress on `stem_progress_stream`.

## 9. Scoring (3.3) and monitoring (3.4)

**Reference melody.** After stems exist, `melodyExtract` runs pYIN on the vocal stem (mono, 16 kHz, 10 ms hop) → f0 + voicing per frame → median-smoothed → stored as `melody/<sha256>.bin` (u16 cents per frame, 0 = unvoiced). Notes are derived by segmenting stable pitch runs ≥ 80 ms for the pitch-lane display.

**Live pitch.** `micStart(scoring)` opens an AAudio input stream (cpal, `LowLatency`, 48 kHz mono) → 16 kHz → YIN per 10 ms frame with a 40 ms window → cents + confidence. The mic timeline is shifted by measured round-trip latency (`measureLatency`: a chirp played and recorded once per output route; cached per route; Bluetooth routes show a warning and disable monitoring).

**Score.** Per voiced reference frame where the singer is voiced: error = distance in cents folded to one octave; frame score 1.0 within ±50 cents, linearly falling to 0 at ±300. Line score = mean frame score × coverage (voiced singer frames / voiced reference frames), 0–100. Song score = duration-weighted line mean. `pitch_stream` sends `{refCents, micCents, confidence}` at 50 Hz to `pitch_lane.dart` (scrolling note lane like the reference notes, with the live trace).

**Monitoring.** In monitoring mode the input is mixed into the output bus in the same callback (full-duplex on one cpal host) with gain and a small freeverb-style reverb/echo; enabled only on wired/USB routes (Mornye `audio_route_info.dart`).

**Recording (3.5).** `micStart(recording)` writes the mixed bus (instrumental + vocal) to FLAC in app storage; user-initiated, listed under Recordings, shareable via `share_plus`; never uploaded.

## 10. Extensions (5.x, 2.10, 2.11, 1.8, 6.4, 6.6)

Built on Mornye's `extensions` crate and Dart extension UI (MORNYE_REUSE.md §3–4). Kalao specifics:
- Capabilities map to Mornye provider types: `lyrics` (Mornye lyrics provider), `metadata` + `artwork` (Mornye metadata provider), `audio` (Kalao's `resolveAudio`; Kalao streams/downloads the URL itself, the extension never handles bytes).
- **Lyric fetch (2.11):** `searchLyrics` queries enabled lyrics extensions in priority order in parallel (6 s timeout each); candidates are ranked with Mornye's `core::lyrics::matching` (title/artist similarity, duration ±3 s) plus a format bonus (`elrc` > `lrc` > `plain`). The user's priority (Mornye `lyrics_provider_priority_page.dart`) breaks ties; a provider picker (Mornye `lyrics_provider_picker.dart`) lets the user choose another candidate.
- **Language detection (2.10):** Mornye `lyrics_language_guess.dart` on the chosen lyrics; the result picks annotation layers (zh → pinyin + Trad/Simp, ja → furigana + romaji).
- **Streaming (1.8):** `resolveAudio` URL → `KaraokeDeck` network source with HTTP range reads in Rust (`kalao-network`) and a byte cache (Mornye's `network_playback_cache.dart` policy); "Download for offline" (6.6) saves the stream into `media/` like an import.
- **Metadata/artwork (6.4):** `searchMetadata` merges results across extensions; artwork is cached by Mornye's cover cache.

## 11. Translation (2.12)

- Client: `kalao-providers::mymemory`. `GET https://api.mymemory.translated.net/get?q=<text>&langpair=<src>|<dst>[&de=<email>]`.
- Limits: `q` ≤ 500 bytes UTF-8 (longer lines are split at punctuation); free quota about 5,000 characters/day anonymously, about 50,000/day with a contact email. The optional email is a user setting (stored locally, never sent elsewhere) with an explanation of why it helps.
- Batching and cache: Mornye's `LyricsTranslationSource` sends each distinct line once (a repeated chorus costs nothing) and caches results by SHA-256 of the line list + language pair. Lines are requested with concurrency 2.
- Errors: a quota warning in `responseData.translatedText` or HTTP 429 → stop for the day, keep partial results, show "Daily translation limit reached". `responseStatus` ≠ 200 → line left untranslated.
- Language codes: Kalao's `zh-Hans` → `zh-CN`, `zh-Hant` → `zh-TW`, `ja` → `ja`, etc. (table in `lyrics_translation_languages.dart`).
- Translations are `origin = translator`; users can edit a line, which marks it `human`.

## 12. Backup and restore (7.x)

Mornye's model: Dart `backup_service.dart` decides categories and layout and drives the UI (`backup_restore_page.dart`); Rust `native_backup::archive` writes and reads the ZIP in a native data job, streaming large tables so they never pass through the UI isolate.
- Archive: `.kalaobackup` = ZIP with `manifest.json` (format version, app version, created_at, categories, counts, per-entry SHA-256), `library.db`, `history.db`, `app_state.db` (SQLite online-backup snapshots), `settings.json` (non-secret preferences), `extensions/*.kalaoext` + `extensions.json` (enabled, priority, repos), optional `media/` and `stems/`.
- Restore: `backupInspect` validates checksums and format and returns a summary for the preview; `backupRestore(mode)` merges (songs by `song_key`, media by sha256, newer lyric version wins, `human` layers kept, history and favorites unioned) or replaces (after a safety backup into app storage). Dart republishes the databases through Mornye's `LibraryNativeAdapter` pattern.
- Scheduled backup (7.4): Dart checks on app start and resume whether a backup is due (daily/weekly) and runs it into the user's chosen SAF folder, keeping the last N files; the result is logged in `backup_run`. There is no background scheduler, so a due backup runs the next time the app is opened.
- POC import (7.6): a one-off Node script in the private POC repo exports songs and lyric layers to a `kalao-poc.json`; `pocImport` converts it into library rows and lyric docs (layers marked `human`).

## 13. Parties (8.x)

Derived from Mornye Link (`crates/link`):
- **Host:** `partyHostStart` starts an HTTPS server (self-signed certificate from `rcgen`, as Link) and a WebSocket endpoint on the LAN, advertises `_kalao-party._tcp` via mDNS (`mdns-sd`; Dart discovery with `bonsoir`), and opens a 6-digit PIN pairing window.
- **Join:** the QR code encodes `kalao://party?h=<ip:port>&fp=<cert sha256>&pin=<pin>&name=<room>`. The guest verifies the certificate fingerprint and proves the PIN like Link (`HMAC-SHA256(key=PIN, "kalao-party-v1:" + fingerprint + ":" + deviceId)`; five bad proofs close the window). Manual join: pick the room from mDNS and type the PIN. The host approves each guest.
- **Protocol (WebSocket JSON):** `hello`, `library.page` (host's songs: id, title, artist, has_stems, has_timed_lyrics), `queue.add {songId, singer}`, `queue.move`, `queue.remove`, `queue.state`, `now_playing {songId, singer, mode}`, `position {ms, monotonic}` (2 Hz, guests interpolate), `lyrics {doc}` (sent once per song), `score {singer, line, total}`, `end`. Guests can only add, move and remove their own entries; the host can do everything.
- **TV view (8.5):** the host also serves a read-only lyrics page over plain HTTP at `http://<ip>:<port>/tv/<roomToken>` (HTML + WebSocket, no Google Cast); open it in a TV browser or cast the host screen with the system screen-mirroring.

## 14. Updates (9.8)

Mornye `update_checker.dart` + `apk_downloader.dart`: once a day if enabled, read `api.github.com/repos/Brinsleym/kalao/releases/latest`, compare versions, pick the APK for the device ABI (arm64 / arm32 / universal), and show `update_dialog.dart` with the changelog. Only when the user taps Update: download to cache with a progress notification, verify the SHA-256 from the release's checksums file, then hand the APK to the package installer (`installApk`, `REQUEST_INSTALL_PACKAGES`). "Open release page" is always offered.

## 15. Diagnostics (9.5)

Mornye logging: Dart `AppLogger` + Rust `LogBuffer` (ring buffer, secrets redacted by `redact`), merged in `log_screen.dart`; share/export as a text file. `app_crash_service.dart` and `AppCrashReporter.kt` keep the last crash report locally and show `app_crash_banner.dart` on next start with "Copy" and "Open GitHub issue" (pre-filled template, nothing sent automatically).

## 16. Settings

`models/settings.dart` (`json_serializable`, Mornye pattern) groups: appearance (theme mode, dynamic color, seed, lyric size, font), lyrics (layers on/off per language, Chinese variant, offset step, auto-fetch, provider priority), playback (default mode, crossfade on switch, countdown, keep screen on), stems (processing local/remote, model, battery/thermal pause, remote server URL), translation (target language, MyMemory email), mic (latency per route, monitoring gain/reverb), backup (folder URI, schedule, keep N, include media), updates (check enabled), party (room name, require approval), developer (extension developer mode). Searchable through Mornye `settings_search_catalog.dart`.

## 17. Testing

- **Rust:** unit tests per crate; fixtures for annotate (POC cases), LRC/eLRC/TTML round trips, matching, MyMemory response parsing, backup archive round trip, party pairing proofs; audio engine tests on rendered buffers (sync of stems = sample-identical sums, crossfade gain curve, loop seam, stretcher bypass).
- **Kotlin:** `MainActivityRoutingTest` (Mornye) and SAF/IO unit tests.
- **Dart:** unit and widget tests (`flutter test`) for services, providers and lyric layout; golden tests for ruby layout in four languages.
- **Integration (`integration_test/`, Mornye style):** playback start/stop and session restore, lyric timing accuracy (±30 ms), import pairing, backup round trip on device, stems job resume after process kill, party with two emulators.
- **CI:** Mornye's `ci.yml` jobs adapted (ROADMAP M0).
