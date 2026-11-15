# Contributing to Kalao

Thanks for helping. Start with [android/docs/README.md](android/docs/README.md); the architecture, roadmap and conventions are documented there.

- **Setup:** follow [android/docs/DEV_SETUP.md](android/docs/DEV_SETUP.md).
- **Before a pull request:** run `bash scripts/check_rust_backend.sh` from the repository root and `flutter analyze && flutter test` in `android/`. CI runs the same checks plus an Android build.
- **Docs:** update `android/docs/` in the same pull request when behaviour, data formats or the roadmap change.
- **Mornye code:** Kalao reuses code from [Mornye](https://github.com/mornyeapp/Mornye) (LGPL-3.0-only). Keep the attribution header on any file derived from it (see `android/docs/MORNYE_REUSE.md`).
- **Never commit** secrets, signing keys, audio or other media, or extension packages (`*.kalaoext`). Extensions are distributed separately.
- **Licence:** contributions are accepted under GPL-3.0-only.
