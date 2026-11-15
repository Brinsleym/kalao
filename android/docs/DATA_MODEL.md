# Data Model

## 1. Timed lyrics (the core change from the POC)

The POC `Lyric` row stored text layers only, with no timing. Kalao separates **text**, **timing** and **annotations**:

```rust
// kalao-core
pub struct LyricDoc {
    pub song_id: SongId,
    pub version: u32,              // bumped on every edit
    pub source: LyricSource,       // Extension { id, item_id } | Imported | UserEdited
    pub source_lang: Lang,         // zh-Hans, zh-Hant, ja, en, ko …
    pub lines: Vec<LyricLine>,
}
pub struct LyricLine {
    pub idx: u32,
    pub section: Option<Section>,  // Verse, PreChorus, Chorus, Bridge, Outro, Custom(String)
    pub section_break_before: bool,
    pub text: String,
    pub start_ms: Option<u32>,     // None = untimed (manual stepping)
    pub end_ms: Option<u32>,
    pub words: Vec<WordTiming>,    // empty = line timing only
    pub singer: Option<String>,    // duets
}
pub struct WordTiming { pub char_range: Range<u32>, pub start_ms: u32, pub end_ms: u32 }

pub struct Annotation {
    pub line_idx: u32,
    pub kind: AnnotationKind,      // Pinyin, Furigana, Romaji, Traditional, Simplified, Translation(Lang)
    pub segments: Vec<RubySegment>,// base span → reading, for per-glyph alignment
    pub origin: Origin,            // Auto | Human | Translator(Azure|MyMemory)
}
```

Annotations with `origin = Human` are never overwritten by regeneration. LRC and enhanced LRC round-trip losslessly through `core::lrc`.

## 2. Local SQLite (`kalao-mobile`, on device)

| Table | Main columns | Notes |
| --- | --- | --- |
| `song` | id, title, artist, album, language, duration_ms, isrc, artwork_url, origin (local/extension), ext_ref, song_key | The library. `song_key` (ISRC, or normalised title+artist+duration) matches songs across backups and devices |
| `media_file` | song_id, kind (original/instrumental/vocals/melody), path, sha256, bytes, codec, source (import/extension/stems-local/stems-remote), pinned | Media and stem cache, LRU |
| `lyric_doc` | song_id, version, json | |
| `annotation` | song_id, version, line_idx, kind, json, origin | |
| `translation_cache` | text_hash, src_lang, dst_lang, text, provider, created_at | Per line text, so repeated lines are free |
| `translate_quota` | month, provider, chars_used | Tracks the user's Azure budget |
| `stem_job` | id, song_id, sha256, mode (local/remote), model, status, progress, checkpoint_chunk, remote_job_id, error | Resumable |
| `extension` | id, version, manifest_json, enabled, priority, repo_id, sha256, installed_at, health | Package files live in app-private storage |
| `extension_kv` | ext_id, key, value | `kalao.storage`; secrets go in secure storage, not here |
| `extension_repo` | id, url, name, public_key, trusted_at, auto_update | |
| `favorite` · `play` · `queue_item` | as in the POC (without user ids), plus `play.mode` and `play.score` | Feed the stats screen |
| `backup_run` | id, started_at, finished_at, target, bytes, status, error | Scheduled-backup history |
| `setting` | key, value_json | Player and lyric settings, stem and translation preferences, backup schedule |

Secure storage (Keystore-backed) holds the stem API key, the install ID, the user's Azure Translator key, and extension `secret` settings. None of these are ever written to a backup.

## 3. Backup file (`.kalaobackup`)

A zip archive, written and read only by `kalao-mobile`:

```
kalao-2026-11-15.kalaobackup
├── manifest.json        # format version, app version, created_at, counts, sha256 of every entry, options
├── library.sqlite       # SQLite online-backup snapshot, secure-storage values and caches excluded
├── extensions/          # installed .kalaoext packages (so restore works offline)
└── media/               # optional (7.2): imported audio and stems, named by sha256
```

- `manifest.json` carries `format` (an integer bumped on breaking changes). A newer app reads every older format through migrations; an older app refuses a newer format with a clear message.
- Restore verifies every checksum before touching the library, then applies in one transaction. *Merge* matches songs by `song_key` and media by sha256, keeps the newer `lyric_doc.version`, keeps `origin = Human` annotations, and unions favorites and plays. *Replace* swaps the library after a safety copy of the current one.
- Excluded: secrets, the translation cache, the downloaded stem models, debug logs.
- Backups are not encrypted; the export screen says so. They contain no credentials.

## 4. Stem server Postgres (`stem-server/`)

| Table | Columns |
| --- | --- |
| `api_keys` | id, prefix, hash (argon2), note, device_hash, bound_at, revoked_at, created_at |
| `jobs` | id, key_id, status, model, input_bytes, duration_ms, created_at, finished_at, error |
| `usage_daily` | key_id, day, jobs, audio_seconds |
