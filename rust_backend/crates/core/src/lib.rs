// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
//! Shared backend logic, independent of mobile bindings and UI runtimes.

pub mod app_version;
pub mod cancellation;
pub mod json;
pub mod lyrics;
pub mod matching;
mod text;
pub mod xml;
pub use text::{json_surrogates as normalize_json_surrogates, lower_hex};
