//! Import methods: `probeAudio` (tags, cover, duration, codec, decodability)
//! and `pairImportFiles` (original/instrumental/lyrics proposals).

use crate::backend::{BackendError, invalid, operation, str_arg};
use kalao_core::pairing::{self, PickedFile};
use serde_json::Value;
use std::path::Path;

/// `{path, coverBase?}`. When the file has embedded art and `coverBase` is
/// given, the picture is written to `coverBase` + `.jpg`/`.png` and the
/// reply's `coverPath` names it.
pub fn probe(method: &str, args: &Value) -> Result<Value, BackendError> {
    let path = str_arg(method, args, "path")?;
    let probe = kalao_audio::probe_file(Path::new(path)).map_err(operation)?;
    let mut reply = serde_json::to_value(&probe).map_err(operation)?;
    if let (Some(base), Some((media_type, bytes))) = (args["coverBase"].as_str(), &probe.cover) {
        let extension = if media_type.contains("png") {
            "png"
        } else {
            "jpg"
        };
        let cover_path = format!("{base}.{extension}");
        if let Some(parent) = Path::new(&cover_path).parent() {
            std::fs::create_dir_all(parent).map_err(operation)?;
        }
        std::fs::write(&cover_path, bytes).map_err(operation)?;
        reply["coverPath"] = Value::String(cover_path);
    }
    Ok(reply)
}

/// `{files: [{name, durationMs?}]}` → proposals (indices into `files`).
pub fn pair(method: &str, args: &Value) -> Result<Value, BackendError> {
    let files: Vec<PickedFile> = serde_json::from_value(args["files"].clone())
        .map_err(|error| invalid(method, error.to_string()))?;
    serde_json::to_value(pairing::propose(&files)).map_err(operation)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn pair_and_probe_errors() {
        let reply = pair(
            "pairImportFiles",
            &json!({"files": [{"name": "a.mp3"}, {"name": "a (karaoke).mp3"}]}),
        )
        .unwrap();
        assert_eq!(reply[0]["instrumental"], 1);
        assert!(pair("pairImportFiles", &json!({})).is_err());
        assert!(probe("probeAudio", &json!({"path": "missing.mp3"})).is_err());
    }
}
