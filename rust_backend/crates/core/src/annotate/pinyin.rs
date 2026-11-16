//! Pinyin ruby for Chinese lyrics (FEATURES 2.3, IMPLEMENTATION.md §4).
//!
//! Readings come from `pinyin_pro`, the Rust port of the `pinyin-pro` library
//! the POC used, so polyphonic characters are read in context (`重要` zhòng,
//! `重新` chóng) and the POC's fixtures hold unchanged. On top of it:
//! - one segment per Han character; spaces and Latin text get no segment, so
//!   they never shift the alignment (the POC's whitespace bug);
//! - er-hua: `儿` in a known rhotacized word merges into the previous
//!   syllable (`哪儿` → `nǎr`), otherwise it keeps its own `ér`.

use super::{RubySegment, is_han};
use pinyin_pro::options::{NonZh, PinyinOptions, PinyinOutput, ToneType, TypeMode};

/// Words whose final `儿` is an r-suffix rather than a syllable.
const ERHUA_WORDS: &[&str] = &[
    "哪儿",
    "这儿",
    "那儿",
    "一点儿",
    "有点儿",
    "一会儿",
    "一块儿",
    "玩儿",
    "事儿",
    "劲儿",
    "味儿",
    "哪兒",
    "這兒",
    "那兒",
    "一點兒",
    "有點兒",
    "一會兒",
    "一塊兒",
    "玩兒",
    "事兒",
    "勁兒",
    "味兒",
];

fn array(text: &str, tone: ToneType) -> Vec<String> {
    let options = PinyinOptions {
        tone_type: tone,
        type_mode: TypeMode::Array,
        non_zh: NonZh::Spaced,
        ..PinyinOptions::default()
    };
    match pinyin_pro::pinyin(text, options) {
        PinyinOutput::Arr(items) => items,
        PinyinOutput::Str(value) => vec![value],
        PinyinOutput::All(items) => items.into_iter().map(|item| item.pinyin).collect(),
    }
}

/// One reading per character of `text` (`None` for non-Han characters).
pub fn readings(text: &str, tone: ToneType) -> Vec<Option<String>> {
    let chars: Vec<char> = text.chars().collect();
    let whole = array(text, tone);
    let usable = |reading: &str| reading.chars().next().is_some_and(char::is_alphabetic);
    if whole.len() == chars.len() {
        return chars
            .iter()
            .zip(whole)
            .map(|(ch, reading)| (is_han(*ch) && usable(&reading)).then_some(reading))
            .collect();
    }
    // Lengths differ (unusual input): read each Han character alone, as the
    // POC's fallback did, so alignment is still guaranteed.
    chars
        .iter()
        .map(|ch| {
            if !is_han(*ch) {
                return None;
            }
            array(&ch.to_string(), tone)
                .into_iter()
                .next()
                .filter(|reading| usable(reading))
        })
        .collect()
}

/// Character indices of `儿` that are er-hua suffixes in `chars`.
fn erhua_positions(chars: &[char]) -> Vec<usize> {
    let mut positions = Vec::new();
    for word in ERHUA_WORDS {
        let word: Vec<char> = word.chars().collect();
        if word.len() > chars.len() {
            continue;
        }
        for start in 0..=chars.len() - word.len() {
            if chars[start..start + word.len()] == word[..] {
                positions.push(start + word.len() - 1);
            }
        }
    }
    positions.sort_unstable();
    positions.dedup();
    positions
}

/// Pinyin ruby segments for one lyric line.
pub fn annotate(text: &str) -> Vec<RubySegment> {
    let chars: Vec<char> = text.chars().collect();
    let readings = readings(text, ToneType::Symbol);
    let erhua = erhua_positions(&chars);
    let mut segments: Vec<RubySegment> = Vec::new();
    let mut offset = 0;
    let mut previous_index = None;
    for (index, (ch, reading)) in chars.iter().zip(readings).enumerate() {
        let width = ch.len_utf16();
        let start = offset;
        offset += width;
        let Some(reading) = reading else {
            previous_index = None;
            continue;
        };
        if erhua.binary_search(&index).is_ok()
            && previous_index == Some(index.wrapping_sub(1))
            && let Some(last) = segments.last_mut()
        {
            last.reading.push('r');
            last.end = offset;
            previous_index = Some(index);
            continue;
        }
        segments.push(RubySegment {
            start,
            end: offset,
            reading,
        });
        previous_index = Some(index);
    }
    segments
}

/// Toneless pinyin of the Han characters, joined (`yueliang`), and their
/// initials (`yl`), for library search keys.
pub fn search_keys(text: &str) -> Option<(String, String)> {
    let mut full = String::new();
    let mut initials = String::new();
    for reading in readings(text, ToneType::None).into_iter().flatten() {
        let reading = reading.replace('ü', "v");
        if let Some(first) = reading.chars().next() {
            initials.push(first);
        }
        full.push_str(&reading);
    }
    (!full.is_empty()).then_some((full, initials))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn first(text: &str) -> String {
        annotate(text)
            .into_iter()
            .next()
            .map(|segment| segment.reading)
            .unwrap_or_default()
    }

    fn joined(text: &str) -> String {
        annotate(text)
            .into_iter()
            .map(|segment| segment.reading)
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// POC `tests/test-pinyin-diacritics.ts`, unchanged expectations.
    #[test]
    fn poc_diacritics() {
        for (text, expected) in [
            ("而", "ér"),
            ("啊", "a"),
            ("哦", "ò"),
            ("呃", "è"),
            ("嗯", "ǹg"),
            ("姆", "mǔ"),
            ("女", "nǚ"),
            ("綠", "lǜ"),
        ] {
            assert_eq!(first(text), expected, "{text}");
        }
    }

    /// POC `tests/test-er-pinyin.ts`: 而 is a full syllable in every word.
    #[test]
    fn poc_er_character() {
        for text in ["而", "而已", "時而", "而且", "從而"] {
            let segments = annotate(text);
            assert_eq!(segments.len(), text.chars().count(), "{text}");
            assert!(
                segments.iter().any(|segment| segment.reading == "ér"),
                "{text}"
            );
        }
    }

    #[test]
    fn polyphones_are_read_in_context() {
        assert_eq!(joined("重要"), "zhòng yào");
        assert_eq!(joined("重新"), "chóng xīn");
        assert_eq!(joined("银行"), "yín háng");
        assert_eq!(joined("行走"), "xíng zǒu");
    }

    #[test]
    fn erhua_merges_only_for_known_words() {
        let segments = annotate("你在哪儿");
        assert_eq!(segments.last().unwrap().reading, "nǎr");
        assert_eq!(segments.last().unwrap().start, 2);
        assert_eq!(segments.last().unwrap().end, 4);
        assert_eq!(segments.len(), 3);
        // 儿子: a real syllable.
        assert_eq!(joined("儿子"), "ér zi");
    }

    #[test]
    fn whitespace_and_latin_never_shift_alignment() {
        let segments = annotate("我 love 你");
        assert_eq!(
            segments,
            [
                RubySegment {
                    start: 0,
                    end: 1,
                    reading: "wǒ".into()
                },
                RubySegment {
                    start: 7,
                    end: 8,
                    reading: "nǐ".into()
                },
            ]
        );
        let spaced = annotate("月亮  代表");
        assert_eq!(
            spaced.iter().map(|s| s.start).collect::<Vec<_>>(),
            [0, 1, 4, 5]
        );
    }

    #[test]
    fn offsets_are_utf16() {
        // 𠀀 (U+20000) is two UTF-16 units.
        let segments = annotate("𠀀我");
        assert_eq!(segments.last().unwrap().start, 2);
    }

    #[test]
    fn search_keys_are_toneless() {
        assert_eq!(
            search_keys("月亮代表我的心"),
            Some(("yueliangdaibiaowodexin".into(), "yldbwdx".into()))
        );
        assert_eq!(search_keys("绿"), Some(("lv".into(), "l".into())));
        assert_eq!(search_keys("hello"), None);
    }
}
