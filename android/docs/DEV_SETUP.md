# Development Setup (Windows host)

Toolchain versions match Mornye (LIBRARIES.md §1).

## Current machine status (2026-11-15)
| Tool | Status |
| --- | --- |
| Rust | ✅ cargo/rustc 1.99.1; `scripts/build_rust_backend.sh host` works on this Windows host (Git Bash) |
| adb | ✅ |
| Flutter 3.47.8 (FVM) | ❌ not installed |
| JDK 25 | ❌ not installed |
| Android SDK 37 / NDK 30.0.16248370 | ❌ not installed (`ANDROID_HOME` unset) |
| Git | ✅ `karaoke/` is the `Brinsleym/kalao` repo; `poc-webapp/` is git-ignored. Private extensions live in a separate private repo |

## Install
1. **FVM** (`dart pub global activate fvm` or the installer), then `fvm install` in `android/` (reads `.fvmrc`, Flutter 3.47.8). Use `fvm flutter …` for every command.
2. **Android Studio** → SDK Manager: Android SDK Platform 37, Build-Tools, Command-line Tools, **NDK 30.0.16248370**, CMake. Set `ANDROID_HOME` and `ANDROID_NDK_HOME`. Accept licences: `fvm flutter doctor --android-licenses`.
3. **JDK 25** (Kotlin `jvmTarget` 25, as Mornye); set `JAVA_HOME`.
4. **Rust** Android targets and tools (the toolchain is pinned by `rust_backend/rust-toolchain.toml`):
   ```sh
   rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
   cargo install cargo-ndk
   ```
5. **Git Bash** for `scripts/*.sh` and **Python 3** for `scripts/check_backend_apk.py` (as in Mornye).
6. **Docker Desktop** for the stem server (from M6).

## Everyday commands (run from `karaoke/`)
```sh
bash scripts/build_rust_backend.sh host        # host library + Kotlin bindings (kalao-bindgen)
bash scripts/build_rust_backend.sh android     # then libkalao_mobile.so per ABI (KALAO_RUST_ANDROID_ABIS selects ABIs)
bash scripts/check_rust_backend.sh             # cargo fmt --check, clippy -D warnings, cargo test (all --locked)
cd android && fvm flutter run                  # Gradle's buildRustBackend runs the android build before preBuild
cd android && fvm dart run build_runner build  # json_serializable models
cd android && fvm flutter analyze && fvm flutter test
cd android && fvm flutter test integration_test
gradle -p android/android :app:testDebugUnitTest   # Kotlin tests incl. MainActivityRoutingTest
docker compose -f stem-server/compose.yaml up  # stem gateway + GPU worker (needs NVIDIA container toolkit)
cargo run -p kalao-ext -- validate path/to/ext # extension CLI (from M5)
```

## Pushing workflow changes
The GitHub CLI token needs the `workflow` scope to push files under `.github/workflows/`: run `gh auth refresh -h github.com -s workflow` once.

## Releases
- Tag `vX.Y.Z` → `release.yml` builds per-ABI and universal APKs, signs them (V1–V4) with the release key from CI secrets, audits the Rust payloads, and publishes a GitHub Release with SHA-256 checksums and a `git-cliff` changelog. The update checker reads that release.

## Conventions
- Rust: `cargo fmt`, `clippy -D warnings`, `thiserror` errors, no `unwrap` outside tests, `unsafe` only in `kalao-desktop/src/ffi.rs` and audited exceptions; `--locked` everywhere.
- Dart: `dart format`, `flutter analyze` clean with Mornye's `analysis_options.yaml` and `riverpod_lint`; no business logic in widgets or providers; backend calls only through `PlatformBridge`.
- Kotlin: a new native method is added to `nativeBackendMethods` and the `when` in the same change (the routing test enforces it).
- Copied Mornye files keep the attribution header (MORNYE_REUSE.md §1).
- Small commits; CI must pass; each milestone gets a tag.
