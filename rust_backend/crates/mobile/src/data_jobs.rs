// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
//! CPU and file work submitted by Flutter. Platform dispatch owns the worker
//! thread and the cancellation lease; widgets continue to own presentation.

use crate::cancellation::RequestLease;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs::File, io::Read, sync::Arc};

#[derive(Debug, thiserror::Error, uniffi::Error)]
#[uniffi(flat_error)]
pub enum NativeDataJobError {
    #[error("{0}")]
    Operation(String),
}

#[uniffi::export]
pub fn run_native_data_job(
    request_json: String,
    lease: Option<Arc<RequestLease>>,
) -> Result<String, NativeDataJobError> {
    let check = || check_lease(lease.as_deref());
    check().map_err(NativeDataJobError::Operation)?;
    let request: Value = serde_json::from_str(&request_json)
        .map_err(|error| NativeDataJobError::Operation(error.to_string()))?;
    let value = execute(&request, &check).map_err(NativeDataJobError::Operation)?;
    check().map_err(NativeDataJobError::Operation)?;
    serde_json::to_string(&value).map_err(|error| NativeDataJobError::Operation(error.to_string()))
}

fn check_lease(lease: Option<&RequestLease>) -> Result<(), String> {
    match lease.map(RequestLease::is_cancelled) {
        Some(Ok(true)) => Err("data job cancelled".into()),
        Some(Err(error)) => Err(error.to_string()),
        _ => Ok(()),
    }
}

fn execute(request: &Value, check: &dyn Fn() -> Result<(), String>) -> Result<Value, String> {
    match string(request, "operation")? {
        "hash_file" => Ok(json!({"sha256": hash_file(string(request, "path")?, check)?})),
        other => Err(format!("Unknown native data job: {other}")),
    }
}

fn string<'a>(request: &'a Value, name: &str) -> Result<&'a str, String> {
    request
        .get(name)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("Missing native data field: {name}"))
}

pub(crate) fn hash_file(
    path: &str,
    check: &dyn Fn() -> Result<(), String>,
) -> Result<String, String> {
    check()?;
    let mut file = File::open(path).map_err(|error| error.to_string())?;
    if !file
        .metadata()
        .map_err(|error| error.to_string())?
        .is_file()
    {
        return Err("Hash input must be a regular file".into());
    }
    let mut hash = Sha256::new();
    let mut buffer = [0; 64 * 1024];
    loop {
        check()?;
        let count = file.read(&mut buffer).map_err(|error| error.to_string())?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    Ok(kalao_core::lower_hex(&hash.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hashes_a_file() {
        let path = std::env::temp_dir().join(format!("kalao-hash-{}", std::process::id()));
        std::fs::write(&path, b"abc").unwrap();
        let reply = run_native_data_job(
            json!({"operation": "hash_file", "path": path}).to_string(),
            None,
        )
        .unwrap();
        let _ = std::fs::remove_file(&path);
        assert_eq!(
            serde_json::from_str::<Value>(&reply).unwrap()["sha256"],
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn unknown_operation_fails() {
        assert!(run_native_data_job(json!({"operation": "x"}).to_string(), None).is_err());
    }
}
