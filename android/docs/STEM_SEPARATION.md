# Stem Separation

Splits a song into **vocals** and **instrumental**. OG Karaoke mode uses the instrumental, the vocal-guide blend uses both, and scoring uses the vocal stem to extract a reference melody.

## 1. On-device (default, always available)

- **Engine:** `kalao-stems` running ONNX Runtime (`ort`), with the NNAPI or XNNPACK execution provider and a CPU fallback.
- **Models:** downloaded on first use from Kalao's GitHub Releases assets, with SHA-256 checked against a list built into the app. Two profiles:
  - *Fast*: a lightweight 2-stem model (MDX-style, int8-quantised), for low-end phones.
  - *Quality*: Hybrid Transformer Demucs (htdemucs, MIT licence) exported to ONNX, fp16 where supported.
  The final model choice is confirmed at M6 after benchmarking on reference devices (target: at most 1× song length for *Quality* on a mid-range phone, at most 0.3× for *Fast*). Model licences must allow redistribution.
- **Pipeline:**
  1. Decode to 44.1 kHz stereo.
  2. Split into 10 s chunks with 1 s overlap.
  3. Run inference per chunk.
  4. Overlap-add.
  5. Instrumental = mix − vocals (the residual), or the model's own output.
  6. Write the stems as FLAC (44.1 kHz stereo, `flacenc`) to `stems/<sha256>/`. FLAC is lossless and decodes with Symphonia, so no extra codec library is needed; a 4-minute song uses about 25–30 MB per stem.
- **Job handling:** runs in Mornye's `BackgroundWorkService` (kind `stems`), an Android foreground service with a progress notification and a cancel action. A checkpoint after every chunk means the job resumes after process death or a reboot. Only one job runs at a time; the others are queued. It pauses on low battery or thermal throttling (both user-overridable).
- **Cache:** stems are keyed by the audio file's SHA-256, so the same song is never separated twice. They are pinned with downloads and LRU-evicted otherwise.

## 2. Remote processing (optional)

Kalao runs a separate stem server (`stem-server/`) with GPU workers. Access uses **personal API keys**. The maintainer gives a key to people who donate, but **the app has no notion of donations**: it just has an optional "Remote stem server API key" field.

### App behaviour
- Settings → Stem separation: `Processing: On-device | Remote (API key)`, a key field, and a "Test key" button.
- On first use, the key is bound to this install. The app generates a random install ID (stored in secure storage) and sends only a salted hash of it.
- Remote job flow: upload the audio (encrypted in transit) → poll or stream progress → download the stems → verify checksums → store them like on-device stems.
- On any failure (network, 401/403 key rejected, 409 bound to another device, 429 rate-limited, server busy), Kalao shows a short notice and falls back to on-device separation. It never blocks the user.

### Stem server
- **Gateway (Rust/axum):** accepts only whitelisted keys (stored as an argon2 hash plus a key prefix for lookup). It binds each key to the first device hash that uses it (**1 device per key**), with an admin-only reset. It also handles per-key rate limits and a concurrent-job cap, upload size and duration limits, and job submit/status/result endpoints.
- **Worker (Python, Docker, GPU):** runs Demucs at the highest quality. It pulls jobs from Redis and writes results to temporary storage.
- **Retention:** uploaded audio and results are deleted after download, or after 24 h at most. No audio is kept, and logs contain only job metadata.
- **Key admin:** `stem-admin issue --note "<donor ref>"` prints a key once; `stem-admin revoke|reset-device|list`. The note field must not hold personal data beyond what the maintainer needs.
- **Metrics** (queue depth, GPU temperature, jobs per key) are exposed in Prometheus format on `/metrics`, behind the operator's admin token. There is no in-app admin view.
