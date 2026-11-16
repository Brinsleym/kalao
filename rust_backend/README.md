# Kalao Rust Backend

The Rust workspace is the app's engine. It follows the layout of Mornye's `rust_backend/` (https://github.com/mornyeapp/Mornye, LGPL-3.0-only); files derived from Mornye carry a header saying so. Flutter reaches it through the `com.brinsley.kalao/backend` channel; Kotlin calls it through UniFFI bindings generated from `kalao-mobile`.

The toolchain is pinned in `rust-toolchain.toml` (Rust 1.99.1 with rustfmt and clippy). The workspace uses edition 2024, resolver 3, and denies `unsafe_code`.

## Crate map

Dependencies point downward: `core`, `network` and `audio` depend on no other workspace crate.

| Crate | Package | Depends on | Status |
| --- | --- | --- | --- |
| `crates/core` | `kalao-core` | none | M0: JSON helpers, text, XML depth check, matching, cancellation, lyrics (LRC, enhanced LRC, TTML payloads, matching). M1: lyric documents (`lyrics::doc`), section markers (`sections`), pinyin ruby (`annotate::pinyin`, via `pinyin_pro`), search keys, import pairing |
| `crates/audio` | `kalao-audio` | none | M1: playback engine (Symphonia → rubato → ring buffers → mixer → cpal/AAudio), `probe_file` |
| `crates/network` | `kalao-network` | none | M0: copied unchanged from Mornye (HTTP client, cookies, DNS, TLS roots, request policy) |
| `crates/mobile` | `kalao-mobile` | core, audio | M0: UniFFI API: `invoke_application` method table, `run_native_data_job`, cancellation registry, log buffer. M1: player, import and lyrics methods |
| `crates/bindgen` | `kalao-bindgen` | `uniffi` CLI | M0: generates the Kotlin bindings |

Later milestones add `stems`, `providers`, `extensions`, `party`, `desktop` and `ext-cli` (see `android/docs/ARCHITECTURE.md`).

## Method table

`kalao-mobile/src/backend.rs` holds every method name Kotlin forwards (`METHODS`, kept sorted; a test checks each name is dispatched). Arguments arrive as a JSON object; replies are JSON text. Methods: lifecycle (`initBackend`, `getBackendInfo`, `getLogs`, `clearLogs`, `setLoggingEnabled`), player (`playerLoad` … `playerState`), import (`probeAudio`, `pairImportFiles`), lyrics (`parseLyrics`, `detectSections`, `annotateLyrics`). Native data jobs (`run_native_data_job`): `hash_file`, `rebuildSearchKeys`.

## Building

| Command | Result |
| --- | --- |
| `bash scripts/build_rust_backend.sh host` | Release host library and Kotlin bindings in `target/bindings/kotlin/` |
| `bash scripts/build_rust_backend.sh android` | Host step, then `libkalao_mobile.so` in `target/android/jniLibs/<abi>/` (16 KB page aligned) |
| `bash scripts/check_rust_backend.sh` | `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test` |

Android Gradle runs the android build in its `buildRustBackend` task before `preBuild`, so a normal Flutter build is enough. `KALAO_RUST_ANDROID_ABIS` selects ABIs (default `arm64-v8a,armeabi-v7a,x86_64`); `ANDROID_NDK_HOME` must point to NDK 30.0.16248370.
