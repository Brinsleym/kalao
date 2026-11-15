# Development Setup (Windows host)

## Current machine status (2026-11-15)
| Tool | Status |
| --- | --- |
| Rust | ✅ cargo/rustc 1.99.1 (targets: wasm32, x86_64-pc-windows-msvc only) |
| adb | ✅ |
| Flutter SDK | ❌ not installed |
| JDK 17 | ❌ not installed |
| Android SDK / NDK | ❌ not installed (`ANDROID_HOME` unset) |
| Git | ⚠️ `karaoke/` is not a git repo. The public Kalao repo is `karaoke/` with `poc-webapp/` excluded (it contains leaked secrets and copyrighted audio). Keep the POC and the private extensions in separate private repos |

## Install
1. Flutter SDK (stable) → add `flutter\bin` to PATH → `flutter doctor`.
2. Android Studio (installs the SDK) → in SDK Manager also install the **NDK (side by side)**, CMake, and command-line tools; accept licences with `flutter doctor --android-licenses`.
3. JDK 17 (Android Studio's bundled JBR is fine; set `JAVA_HOME`).
4. Rust Android targets and tools:
   ```sh
   rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
   cargo install cargo-ndk
   ```
   The toolchain version comes from `rust_backend/rust-toolchain.toml`.
5. Git Bash (for the `scripts/*.sh` build scripts, as in Mornye).
6. Stem server (from M6): Docker Desktop.

## Everyday commands (once M0 lands; run from `karaoke/`)
```sh
bash scripts/build_rust_backend.sh host       # host library + Kotlin bindings (kalao-bindgen)
bash scripts/build_rust_backend.sh android    # host step, then libkalao_mobile.so per ABI
bash scripts/check_rust_backend.sh            # cargo fmt --check, clippy -D warnings, cargo test (all --locked)
cd android && flutter run                     # Gradle runs the android build step before preBuild
cd android && flutter test && flutter test integration_test
docker compose -f stem-server/compose.yaml up # stem gateway + GPU worker (needs NVIDIA container toolkit)
cargo run -p kalao-ext -- validate path/to/ext   # extension CLI (from M5)
```

## Releases
- Tag `vX.Y.Z` → CI builds and signs the APKs with the release key (a CI secret, never in the repo), and creates a GitHub Release with per-ABI and universal APKs, SHA-256 checksums and the changelog.

## Conventions
- Rust: `cargo fmt`, `clippy -D warnings`, `thiserror` for library errors; no `unwrap` outside tests; `unsafe` only in `kalao-desktop/src/ffi.rs`; every cargo call in scripts and CI passes `--locked`.
- Dart: `flutter analyze` clean, `very_good_analysis` lints; no business logic in widgets or providers.
- Commits are small and CI must pass; each milestone gets a tag.
