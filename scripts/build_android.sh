#!/usr/bin/env bash
# Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
# LGPL-3.0-only. Modified for Kalao.
#
# Build release APKs (one per ABI plus a universal APK) and audit each one.
# ABIs come from KALAO_RUST_ANDROID_ABIS (default arm64-v8a,armeabi-v7a,x86_64).
# Extra arguments are passed to `flutter build apk`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
APP_DIR="$REPO_DIR/android"
OUTPUT_DIR="$APP_DIR/build/app/outputs/flutter-apk"

for argument in "$@"; do
  case "$argument" in
    --target-platform|--target-platform=*|--split-per-abi|--no-split-per-abi)
      echo "Error: set KALAO_RUST_ANDROID_ABIS to select the release APK architectures." >&2
      exit 1
      ;;
  esac
done

ANDROID_ABIS_RAW="${KALAO_RUST_ANDROID_ABIS-arm64-v8a,armeabi-v7a,x86_64}"
export KALAO_RUST_ANDROID_ABIS="$ANDROID_ABIS_RAW"
IFS=',' read -r -a ANDROID_ABIS <<< "$ANDROID_ABIS_RAW"
TARGET_PLATFORMS=()
for abi in "${ANDROID_ABIS[@]}"; do
  case "$abi" in
    arm64-v8a) TARGET_PLATFORMS+=(android-arm64) ;;
    armeabi-v7a) TARGET_PLATFORMS+=(android-arm) ;;
    x86_64) TARGET_PLATFORMS+=(android-x64) ;;
    *) echo "Error: unsupported ABI '$abi'." >&2; exit 1 ;;
  esac
done
TARGET_PLATFORM_LIST="$(IFS=','; echo "${TARGET_PLATFORMS[*]}")"

cd "$APP_DIR"
if command -v fvm >/dev/null 2>&1 && [[ -z "${CI:-}" ]]; then
  FLUTTER=(fvm flutter)
else
  FLUTTER=(flutter)
fi

"${FLUTTER[@]}" build apk \
  --release \
  --obfuscate \
  --split-debug-info "$APP_DIR/build/symbols/android" \
  --split-per-abi \
  --target-platform "$TARGET_PLATFORM_LIST" \
  "$@"

for target in "${ANDROID_ABIS[@]}" universal; do
  apk="app-$target-release.apk"
  abis="$target"
  if [[ "$target" == "universal" ]]; then
    apk=app-release.apk
    abis="$ANDROID_ABIS_RAW"
  fi
  if [[ ! -f "$OUTPUT_DIR/$apk" ]]; then
    echo "Error: expected APK was not created: $OUTPUT_DIR/$apk" >&2
    exit 1
  fi
  python3 "$REPO_DIR/scripts/check_backend_apk.py" "$OUTPUT_DIR/$apk" --abis "$abis"
done

echo "Built Android release APKs in $OUTPUT_DIR"
