//! Kalao's lyric document (DATA_MODEL.md §1) from imported text: LRC (line
//! timing, several time tags per line, `[offset:]`) or plain text (one line
//! per row, blank rows are section breaks). Section markers become
//! `section` on the following line. Word timing and TTML arrive in M2.

use crate::sections;
use regex::Regex;
use serde::Serialize;
use std::sync::LazyLock;

static TIME_TAG: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]").expect("valid"));
static WORD_TAG: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>").expect("valid"));
static METADATA: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^\[([a-z#][a-z0-9_-]*):(.*)\]$").expect("valid"));

pub const DOC_VERSION: u32 = 1;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DocLine {
    pub time_ms: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub end_ms: Option<i64>,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub section: Option<&'static str>,
    pub section_break_before: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LyricDoc {
    pub version: u32,
    pub format: &'static str,
    pub timed: bool,
    pub offset_ms: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub artist: Option<String>,
    pub lines: Vec<DocLine>,
}

fn tag_ms(captures: &regex::Captures<'_>) -> i64 {
    let minutes: i64 = captures[1].parse().unwrap_or(0);
    let seconds: i64 = captures[2].parse().unwrap_or(0);
    let fraction = captures.get(3).map_or(0, |m| {
        let digits = m.as_str();
        let value: i64 = digits.parse().unwrap_or(0);
        match digits.len() {
            1 => value * 100,
            2 => value * 10,
            _ => value,
        }
    });
    minutes * 60_000 + seconds * 1000 + fraction
}

/// Parses `raw`. `format` is `"lrc"`, `"plain"` or `None` to detect.
pub fn parse(raw: &str, format: Option<&str>) -> LyricDoc {
    let raw = raw
        .trim_start_matches('\u{feff}')
        .replace("\r\n", "\n")
        .replace('\r', "\n");
    let is_lrc = match format {
        Some("lrc") => true,
        Some("plain") => false,
        _ => raw.lines().any(|line| {
            TIME_TAG
                .find(line.trim_start())
                .is_some_and(|tag| tag.start() == 0)
        }),
    };
    if is_lrc {
        parse_lrc(&raw)
    } else {
        parse_plain(&raw)
    }
}

fn parse_plain(raw: &str) -> LyricDoc {
    let rows: Vec<&str> = raw.split('\n').collect();
    let lines = sections::detect(&rows)
        .into_iter()
        .map(|line| DocLine {
            time_ms: 0,
            end_ms: None,
            text: line.text,
            section: line.section,
            section_break_before: line.section_break_before,
        })
        .collect();
    LyricDoc {
        version: DOC_VERSION,
        format: "plain",
        timed: false,
        offset_ms: 0,
        title: None,
        artist: None,
        lines,
    }
}

fn parse_lrc(raw: &str) -> LyricDoc {
    let mut offset_ms = 0;
    let (mut title, mut artist) = (None, None);
    // (time, row order, text); section markers and blanks keep their order.
    let mut timed: Vec<(i64, usize, String)> = Vec::new();
    for (order, row) in raw.split('\n').enumerate() {
        let row = row.trim();
        if row.is_empty() {
            continue;
        }
        let mut rest = row;
        let mut times = Vec::new();
        while let Some(captures) = TIME_TAG.captures(rest) {
            let whole = captures.get(0).expect("match");
            if whole.start() != 0 {
                break;
            }
            times.push(tag_ms(&captures));
            rest = rest[whole.end()..].trim_start();
        }
        if times.is_empty() {
            if let Some(captures) = METADATA.captures(row) {
                let value = captures[2].trim().to_owned();
                match captures[1].to_lowercase().as_str() {
                    "offset" => offset_ms = value.parse().unwrap_or(0),
                    "ti" if !value.is_empty() => title = Some(value),
                    "ar" if !value.is_empty() => artist = Some(value),
                    _ => {}
                }
            }
            continue;
        }
        let text = WORD_TAG.replace_all(rest, "").trim().to_owned();
        for time in times {
            timed.push((time, order, text.clone()));
        }
    }
    timed.sort_by_key(|(time, order, _)| (*time, *order));
    // Section detection over the timed rows: an empty timed row is a break
    // and a marker row names the next section; times stay with their text.
    let mut lines: Vec<DocLine> = Vec::new();
    let mut pending_section = None;
    let mut pending_break = false;
    for (time, _, text) in &timed {
        if text.is_empty() {
            pending_break = !lines.is_empty();
            if let Some(previous) = lines.last_mut() {
                previous.end_ms.get_or_insert(*time);
            }
            continue;
        }
        if let Some(kind) = sections::marker_kind(text) {
            pending_section = Some(kind);
            pending_break = !lines.is_empty();
            continue;
        }
        let text = sections::strip_inline(text).trim().to_owned();
        if text.is_empty() {
            continue;
        }
        lines.push(DocLine {
            time_ms: *time,
            end_ms: None,
            text,
            section: pending_section.take(),
            section_break_before: std::mem::take(&mut pending_break),
        });
    }
    for index in 1..lines.len() {
        let next = lines[index].time_ms;
        let previous = &mut lines[index - 1];
        if previous.end_ms.is_none_or(|end| end > next) {
            previous.end_ms = Some(next);
        }
    }
    LyricDoc {
        version: DOC_VERSION,
        format: "lrc",
        timed: lines.iter().any(|line| line.time_ms > 0),
        offset_ms,
        title,
        artist,
        lines,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_text_keeps_sections_and_breaks() {
        let doc = parse("[Verse 1]\nLine one\nLine two\n\n[Chorus]\nSing it\n", None);
        assert_eq!(doc.format, "plain");
        assert!(!doc.timed);
        let texts: Vec<_> = doc.lines.iter().map(|l| l.text.as_str()).collect();
        assert_eq!(texts, ["Line one", "Line two", "Sing it"]);
        assert_eq!(doc.lines[0].section, Some("verse"));
        assert_eq!(doc.lines[2].section, Some("chorus"));
        assert!(doc.lines[2].section_break_before);
        assert!(doc.lines.iter().all(|l| l.time_ms == 0));
    }

    #[test]
    fn lrc_with_metadata_offset_and_repeated_tags() {
        let raw = "\u{feff}[ti:月亮代表我的心]\r\n[ar:邓丽君]\r\n[offset:-150]\r\n\
                   [00:12.34]你问我爱你有多深\r\n[00:20.5][01:10.00]我爱你有几分\r\n\
                   [00:30.120][Chorus]\r\n[00:31.00]<00:31.00>月<00:31.50>亮\r\n";
        let doc = parse(raw, None);
        assert_eq!(doc.format, "lrc");
        assert!(doc.timed);
        assert_eq!(doc.offset_ms, -150);
        assert_eq!(doc.title.as_deref(), Some("月亮代表我的心"));
        assert_eq!(doc.artist.as_deref(), Some("邓丽君"));
        let lines: Vec<_> = doc
            .lines
            .iter()
            .map(|l| (l.time_ms, l.end_ms, l.text.as_str(), l.section))
            .collect();
        assert_eq!(
            lines,
            [
                (12_340, Some(20_500), "你问我爱你有多深", None),
                (20_500, Some(31_000), "我爱你有几分", None),
                (31_000, Some(70_000), "月亮", Some("chorus")),
                (70_000, None, "我爱你有几分", None),
            ]
        );
    }

    #[test]
    fn explicit_format_wins() {
        assert_eq!(parse("[00:01.00]x", Some("plain")).format, "plain");
        assert_eq!(parse("no tags", Some("lrc")).lines.len(), 0);
    }
}
