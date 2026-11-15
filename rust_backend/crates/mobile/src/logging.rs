// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
//! Process-wide diagnostic ring buffer (Mornye's extension LogBuffer). Dart
//! merges these entries with its own AppLogger output in the log screen.
//! Secret redaction is added with the extension runtime (M5); nothing logged
//! before then carries secrets.

use serde::Serialize;
use std::collections::VecDeque;
use std::sync::{Mutex, OnceLock};

const CAPACITY: usize = 500;
const MAX_MESSAGE: usize = 4000;

#[derive(Clone, Debug, Serialize)]
pub struct LogEntry {
    pub timestamp: String,
    pub level: String,
    pub tag: String,
    pub message: String,
}

#[derive(Default)]
struct State {
    entries: VecDeque<LogEntry>,
    next_index: i64,
    enabled: bool,
}

#[derive(Default)]
pub struct LogBuffer(Mutex<State>);

pub fn global() -> &'static LogBuffer {
    static BUFFER: OnceLock<LogBuffer> = OnceLock::new();
    BUFFER.get_or_init(LogBuffer::default)
}

fn truncate(message: &str) -> String {
    if message.len() <= MAX_MESSAGE {
        return message.to_owned();
    }
    let mut end = MAX_MESSAGE;
    while !message.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}...[truncated]", &message[..end])
}

impl LogBuffer {
    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    pub fn set_enabled(&self, enabled: bool) {
        self.state().enabled = enabled;
    }

    /// Debug and info entries are kept only while logging is enabled; warnings
    /// and errors are always kept so a crash report has context.
    pub fn add(&self, level: &str, tag: &str, message: &str) {
        let mut state = self.state();
        if !state.enabled && !matches!(level, "WARN" | "ERROR" | "FATAL") {
            return;
        }
        let entry = LogEntry {
            timestamp: chrono::Local::now().format("%H:%M:%S%.3f").to_string(),
            level: level.into(),
            tag: tag.into(),
            message: truncate(message),
        };
        if state.entries.len() == CAPACITY {
            state.entries.pop_front();
        }
        let line = format!("[{}] {}", entry.tag, entry.message);
        state.entries.push_back(entry);
        state.next_index = state.next_index.wrapping_add(1);
        drop(state);
        use std::io::Write;
        let _ = writeln!(std::io::stderr().lock(), "{line}");
    }

    /// Entries added at or after index, plus the index to ask for next time.
    pub fn since(&self, index: i64) -> serde_json::Value {
        let state = self.state();
        let earliest = state.next_index - state.entries.len() as i64;
        let skip = if index >= state.next_index {
            state.entries.len()
        } else {
            (index.max(earliest) - earliest) as usize
        };
        let logs: Vec<_> = state.entries.iter().skip(skip).collect();
        serde_json::json!({"logs": logs, "next_index": state.next_index})
    }

    pub fn clear(&self) {
        self.state().entries.clear();
    }
}

pub(crate) fn info(tag: &str, message: &str) {
    global().add("INFO", tag, message);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keeps_warnings_when_disabled_and_pages_by_index() {
        let buffer = LogBuffer::default();
        buffer.add("INFO", "T", "dropped");
        buffer.add("WARN", "T", "kept");
        buffer.set_enabled(true);
        buffer.add("INFO", "T", "kept too");
        let all = buffer.since(0);
        assert_eq!(all["logs"].as_array().map(Vec::len), Some(2));
        assert_eq!(all["next_index"], 2);
        assert_eq!(buffer.since(1)["logs"][0]["message"], "kept too");
    }

    #[test]
    fn ring_buffer_drops_oldest() {
        let buffer = LogBuffer::default();
        buffer.set_enabled(true);
        for i in 0..(CAPACITY + 5) {
            buffer.add("INFO", "T", &i.to_string());
        }
        let all = buffer.since(0);
        assert_eq!(all["logs"].as_array().map(Vec::len), Some(CAPACITY));
        assert_eq!(all["logs"][0]["message"], "5");
    }

    #[test]
    fn truncates_on_char_boundary() {
        let long = "歌".repeat(MAX_MESSAGE);
        assert!(truncate(&long).ends_with("...[truncated]"));
    }
}
