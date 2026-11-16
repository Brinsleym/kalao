//! Section markers in lyrics (`[Verse 1]`, `【副歌】`, `「サビ」`, …), ported
//! from the POC's Genius cleaner with its test cases. A line that is only a
//! marker becomes the section of the next line; markers inside a line are
//! removed; blank lines become section breaks.

use regex::Regex;
use std::sync::LazyLock;

/// Marker words per language, in the POC's order (leftmost alternative wins).
const TERMS: &[&str] = &[
    // English
    "Verse",
    "Chorus",
    "Pre-Chorus",
    "Post-Chorus",
    "Hook",
    "Bridge",
    "Intro",
    "Outro",
    "Interlude",
    "Refrain",
    "Drop",
    "Break",
    "Instrumental",
    "Solo",
    "Buildup",
    "Breakdown",
    "Coda",
    "Tag",
    "Ad-Lib",
    "Skit",
    "Spoken",
    "Transition",
    "Prechorus",
    "Postchorus",
    // Chinese
    "主歌",
    "副歌",
    "間奏",
    "前奏",
    "尾奏",
    "過渡",
    "橋段",
    "副段",
    "前副歌",
    "后副歌",
    "引子",
    "尾声",
    "间奏",
    "过渡",
    "桥段",
    "独奏",
    "合唱",
    // Japanese
    "イントロ",
    "Aメロ",
    "Bメロ",
    "サビ",
    "後奏",
    "アウトロ",
    "ブリッジ",
    "ソロ",
    // Korean
    "인트로",
    "벌스",
    "코러스",
    "브릿지",
    "아웃트로",
    "전주",
    "간주",
    "후주",
    // Spanish, French, German, Portuguese
    "Verso",
    "Estribillo",
    "Coro",
    "Puente",
    "Interludio",
    "Couplet",
    "Pont",
    "Strophe",
    "Refrão",
    "Ponte",
];

const OPEN: &str = r"(?:\[|【|｛|「|『|❲)";
const CLOSE: &str = r"(?:\]|】|｝|」|』|❳)";
const BODY: &str = r"(?:[^\]】｝」』❳]*)?";

fn terms_pattern() -> String {
    TERMS
        .iter()
        .map(|term| regex::escape(term))
        .collect::<Vec<_>>()
        .join("|")
}

static STANDALONE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!("(?i)^{OPEN}({}){BODY}{CLOSE}$", terms_pattern())).expect("valid")
});

static INLINE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!("(?i){OPEN}({}){BODY}{CLOSE}", terms_pattern())).expect("valid")
});

/// Unbracketed headings such as `Chorus:` or `副歌：`.
static HEADING: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(&format!(
        r"(?i)^(?:\(|（)?({})(?:\s*\d+|[一二三四五六七八九十]+)?(?:\)|）)?\s*[:：]?$",
        terms_pattern()
    ))
    .expect("valid")
});

/// Whether the whole line is a section marker.
pub fn is_marker(line: &str) -> bool {
    let line = line.trim();
    STANDALONE.is_match(line) || HEADING.is_match(line)
}

/// Removes markers inside a line (the line keeps its other text unchanged).
pub fn strip_inline(line: &str) -> String {
    INLINE.replace_all(line, "").into_owned()
}

/// The section kind for a marker line, or `None` if it is not a marker.
pub fn marker_kind(line: &str) -> Option<&'static str> {
    let line = line.trim();
    let term = STANDALONE
        .captures(line)
        .or_else(|| HEADING.captures(line))?
        .get(1)?
        .as_str()
        .to_lowercase();
    Some(match term.as_str() {
        "verse" | "主歌" | "aメロ" | "벌스" | "verso" | "couplet" | "strophe" => "verse",
        "pre-chorus" | "prechorus" | "bメロ" | "前副歌" => "preChorus",
        "chorus" | "hook" | "refrain" | "副歌" | "サビ" | "코러스" | "estribillo" | "coro"
        | "refrão" | "合唱" | "副段" => "chorus",
        "post-chorus" | "postchorus" | "后副歌" => "postChorus",
        "bridge" | "橋段" | "桥段" | "過渡" | "过渡" | "ブリッジ" | "브릿지" | "puente"
        | "pont" | "ponte" | "transition" => "bridge",
        "intro" | "前奏" | "引子" | "イントロ" | "인트로" | "전주" => "intro",
        "outro" | "尾奏" | "尾声" | "後奏" | "アウトロ" | "아웃트로" | "후주" | "coda" => {
            "outro"
        }
        "interlude" | "間奏" | "间奏" | "간주" | "interludio" | "instrumental" | "break"
        | "breakdown" | "drop" | "solo" | "独奏" | "ソロ" => "interlude",
        _ => "other",
    })
}

/// One lyric line after section detection.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SectionedLine {
    pub text: String,
    pub section: Option<&'static str>,
    pub section_break_before: bool,
}

/// Applies the rules above to raw lines (blank lines included).
pub fn detect(lines: &[&str]) -> Vec<SectionedLine> {
    let mut out = Vec::new();
    let mut pending_section = None;
    let mut pending_break = false;
    for raw in lines {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            pending_break = !out.is_empty();
            continue;
        }
        if let Some(kind) = marker_kind(trimmed) {
            pending_section = Some(kind);
            pending_break = !out.is_empty();
            continue;
        }
        let text = strip_inline(trimmed).trim().to_owned();
        if text.is_empty() {
            continue;
        }
        out.push(SectionedLine {
            text,
            section: pending_section.take(),
            section_break_before: std::mem::take(&mut pending_break),
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// POC `tests/test-section-markers.ts` (standalone cases).
    #[test]
    fn poc_section_markers() {
        let matching = [
            "[Verse 1]",
            "[Chorus]",
            "[Pre-Chorus]",
            "[Bridge - Part 2]",
            "[Outro (Acoustic)]",
            "[Instrumental Break]",
            "[Verse 3: John]",
            "[CHORUS]",
            "[主歌]",
            "[主歌一]",
            "[主歌五]",
            "[副歌]",
            "[過渡]",
            "[間奏]",
            "[前奏]",
            "[尾奏]",
            "[橋段]",
            "[イントロ]",
            "[Aメロ]",
            "[Bメロ]",
            "[サビ]",
            "[アウトロ]",
            "[인트로]",
            "[벌스]",
            "[코러스]",
            "[브릿지]",
            "[Verso 1]",
            "[Estribillo]",
            "[Puente]",
            "[Couplet 1]",
            "[Refrain]",
            "[Pont]",
            "[Strophe 1]",
            "[Refrão]",
            "[Verse 12]",
            "[Chorus (x2)]",
            "[Verse 2 - John & Jane]",
            "[Pre-Chorus: Intro]",
        ];
        for text in matching {
            assert!(STANDALONE.is_match(text), "{text} should match");
        }
        for text in [
            "[Some random text]",
            "[Artist Name]",
            "Verse without brackets",
            "[123]",
            "Regular lyric line",
        ] {
            assert!(!STANDALONE.is_match(text), "{text} should not match");
        }
    }

    /// POC `tests/test-section-markers.ts` (inline removal).
    #[test]
    fn poc_inline_removal() {
        for (text, expected) in [
            ("Some lyrics[Verse 2]", "Some lyrics"),
            ("You might also like[Chorus]", "You might also like"),
            ("[主歌]Start of line", "Start of line"),
            ("Middle[副歌]of line", "Middleof line"),
            ("Multiple[Verse 1][Chorus]markers", "Multiplemarkers"),
        ] {
            assert_eq!(strip_inline(text), expected);
        }
    }

    /// POC `tests/test-alternative-brackets.ts`.
    #[test]
    fn poc_alternative_brackets() {
        for text in [
            "[Verse 1]",
            "[Chorus]",
            "[主歌]",
            "【Verse 1】",
            "【Chorus】",
            "【主歌】",
            "【副歌】",
            "【Aメロ】",
            "【サビ】",
            "｛Verse｝",
            "｛Chorus｝",
            "｛主歌｝",
            "「Verse」",
            "「主歌」",
            "「イントロ」",
            "「サビ」",
            "『Chorus』",
            "『副歌』",
            "『Bメロ』",
            "❲Bridge❳",
            "❲橋段❳",
            "「主歌一」",
            "『Chorus 2』",
            "｛Pre-Chorus｝",
            "❲Verse 3: John❳",
        ] {
            assert!(STANDALONE.is_match(text), "{text} should match");
        }
        for text in [
            "【歌手名】",
            "「愛してる」",
            "『星空』",
            "｛心｝",
            "❲あなた❳",
            "[Random text]",
            "【こんにちは】",
        ] {
            assert!(!STANDALONE.is_match(text), "{text} should not match");
        }
        for text in ["Some lyrics【Verse】", "Text before「Chorus」more text"] {
            assert!(INLINE.is_match(text));
        }
        for (text, expected) in [
            ("【Verse】Some lyrics here", "Some lyrics here"),
            ("Start「Chorus」middle『Bridge』end", "Startmiddleend"),
            ("｛Pre-Chorus｝Begin the song", "Begin the song"),
            ("Text❲Outro❳more text", "Textmore text"),
            ("【主歌】これは歌詞です", "これは歌詞です"),
            (
                "Keep these 「愛してる」 lyrics",
                "Keep these 「愛してる」 lyrics",
            ),
            (
                "Normal [Verse] markers work too",
                "Normal  markers work too",
            ),
        ] {
            assert_eq!(strip_inline(text), expected);
        }
    }

    #[test]
    fn detect_assigns_sections_and_breaks() {
        let lines = detect(&[
            "【主歌】",
            "月亮代表我的心",
            "你问我爱你有多深",
            "",
            "Chorus:",
            "Hello[Verse]",
            "",
            "",
            "End",
        ]);
        assert_eq!(
            lines,
            [
                SectionedLine {
                    text: "月亮代表我的心".into(),
                    section: Some("verse"),
                    section_break_before: false,
                },
                SectionedLine {
                    text: "你问我爱你有多深".into(),
                    section: None,
                    section_break_before: false,
                },
                SectionedLine {
                    text: "Hello".into(),
                    section: Some("chorus"),
                    section_break_before: true,
                },
                SectionedLine {
                    text: "End".into(),
                    section: None,
                    section_break_before: true,
                },
            ]
        );
    }

    #[test]
    fn headings_need_the_whole_line() {
        assert!(is_marker("Chorus:"));
        assert!(is_marker("副歌："));
        assert!(is_marker("(Bridge)"));
        assert!(!is_marker("Chorus girls are dancing"));
    }
}
