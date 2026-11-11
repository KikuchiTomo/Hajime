#![forbid(unsafe_code)]

//! 絵文字の書体で描く文字の見分けと，肌の色(macOS の PaletteView.isEmoji と PaletteStrings.skinToneSample)

use ipc::SkinTone;

/// 肌の色の帯の並び(core の SkinTone.allCases と同じ順)．帯の何番目を押したかから肌の色を決める
pub const SKIN_TONES: [SkinTone; 6] = [
    SkinTone::None,
    SkinTone::Light,
    SkinTone::MediumLight,
    SkinTone::Medium,
    SkinTone::MediumDark,
    SkinTone::Dark,
];

/// 足元の肌の色のボタンに見せる絵文字(手を振る)
const SKIN_TONE_SAMPLE: char = '\u{1F44B}';
/// 絵文字の表示に切り替える字
const EMOJI_VARIATION: char = '\u{FE0F}';

/// 既定の肌の色のボタンに見せる絵文字(core の PaletteStrings.skinToneSample と同じ)
pub fn skin_tone_sample(tone: SkinTone) -> String {
    with_skin_tone(SKIN_TONE_SAMPLE, tone)
}

/// 人の絵文字 base に肌の色を付ける(肌の色を変えない形なら base のまま)
pub fn with_skin_tone(base: char, tone: SkinTone) -> String {
    let modifier = match tone {
        SkinTone::None => None,
        SkinTone::Light => Some('\u{1F3FB}'),
        SkinTone::MediumLight => Some('\u{1F3FC}'),
        SkinTone::Medium => Some('\u{1F3FD}'),
        SkinTone::MediumDark => Some('\u{1F3FE}'),
        SkinTone::Dark => Some('\u{1F3FF}'),
    };
    std::iter::once(base).chain(modifier).collect()
}

/// 絵文字の書体で描く文字か．絵文字の表示を持つ文字(U+FE0F を含むものを含む)と，組み合わせの絵文字(macOS と同じ決まり)
pub fn is_emoji(text: &str) -> bool {
    let Some(first) = text.chars().next() else {
        return false;
    };
    presents_as_emoji(first)
        || text.contains(EMOJI_VARIATION)
        || text.chars().nth(1).is_some() && is_emoji_character(first)
}

/// 既定で絵文字として表示する字(Unicode の Emoji_Presentation)
const PRESENTATION: &[(u32, u32)] = &[
    (0x231A, 0x231B),
    (0x23E9, 0x23EC),
    (0x23F0, 0x23F0),
    (0x23F3, 0x23F3),
    (0x25FD, 0x25FE),
    (0x2614, 0x2615),
    (0x2648, 0x2653),
    (0x267F, 0x267F),
    (0x2693, 0x2693),
    (0x26A1, 0x26A1),
    (0x26AA, 0x26AB),
    (0x26BD, 0x26BE),
    (0x26C4, 0x26C5),
    (0x26CE, 0x26CE),
    (0x26D4, 0x26D4),
    (0x26EA, 0x26EA),
    (0x26F2, 0x26F3),
    (0x26F5, 0x26F5),
    (0x26FA, 0x26FA),
    (0x26FD, 0x26FD),
    (0x2705, 0x2705),
    (0x270A, 0x270B),
    (0x2728, 0x2728),
    (0x274C, 0x274C),
    (0x274E, 0x274E),
    (0x2753, 0x2755),
    (0x2757, 0x2757),
    (0x2795, 0x2797),
    (0x27B0, 0x27B0),
    (0x27BF, 0x27BF),
    (0x2B1B, 0x2B1C),
    (0x2B50, 0x2B50),
    (0x2B55, 0x2B55),
    (0x1F004, 0x1F004),
    (0x1F0CF, 0x1F0CF),
    (0x1F18E, 0x1F18E),
    (0x1F191, 0x1F19A),
    (0x1F1E6, 0x1F1FF),
    (0x1F201, 0x1F201),
    (0x1F21A, 0x1F21A),
    (0x1F22F, 0x1F22F),
    (0x1F232, 0x1F236),
    (0x1F238, 0x1F23A),
    (0x1F250, 0x1F251),
    (0x1F300, 0x1F320),
    (0x1F32D, 0x1F335),
    (0x1F337, 0x1F37C),
    (0x1F37E, 0x1F393),
    (0x1F3A0, 0x1F3CA),
    (0x1F3CF, 0x1F3D3),
    (0x1F3E0, 0x1F3F0),
    (0x1F3F4, 0x1F3F4),
    (0x1F3F8, 0x1F43E),
    (0x1F440, 0x1F440),
    (0x1F442, 0x1F4FC),
    (0x1F4FF, 0x1F53D),
    (0x1F54B, 0x1F54E),
    (0x1F550, 0x1F567),
    (0x1F57A, 0x1F57A),
    (0x1F595, 0x1F596),
    (0x1F5A4, 0x1F5A4),
    (0x1F5FB, 0x1F64F),
    (0x1F680, 0x1F6C5),
    (0x1F6CC, 0x1F6CC),
    (0x1F6D0, 0x1F6D2),
    (0x1F6D5, 0x1F6D7),
    (0x1F6DC, 0x1F6DF),
    (0x1F6EB, 0x1F6EC),
    (0x1F6F4, 0x1F6FC),
    (0x1F7E0, 0x1F7EB),
    (0x1F7F0, 0x1F7F0),
    (0x1F90C, 0x1F93A),
    (0x1F93C, 0x1F945),
    (0x1F947, 0x1F9FF),
    (0x1FA70, 0x1FA7C),
    (0x1FA80, 0x1FA89),
    (0x1FA8F, 0x1FAC6),
    (0x1FACE, 0x1FADC),
    (0x1FADF, 0x1FAE9),
    (0x1FAF0, 0x1FAF8),
];

/// 絵文字にもなる字(Unicode の Emoji の大まかな範囲)．組み合わせの絵文字の先頭の字を見分けるのに使う
const EMOJI: &[(u32, u32)] = &[
    (0x23, 0x23),
    (0x2A, 0x2A),
    (0x30, 0x39),
    (0xA9, 0xA9),
    (0xAE, 0xAE),
    (0x203C, 0x203C),
    (0x2049, 0x2049),
    (0x2122, 0x2122),
    (0x2139, 0x2139),
    (0x2194, 0x2199),
    (0x21A9, 0x21AA),
    (0x231A, 0x231B),
    (0x2328, 0x2328),
    (0x23CF, 0x23CF),
    (0x23E9, 0x23F3),
    (0x23F8, 0x23FA),
    (0x24C2, 0x24C2),
    (0x25AA, 0x25AB),
    (0x25B6, 0x25B6),
    (0x25C0, 0x25C0),
    (0x25FB, 0x25FE),
    (0x2600, 0x27BF),
    (0x2934, 0x2935),
    (0x2B05, 0x2B07),
    (0x2B1B, 0x2B1C),
    (0x2B50, 0x2B50),
    (0x2B55, 0x2B55),
    (0x3030, 0x3030),
    (0x303D, 0x303D),
    (0x3297, 0x3297),
    (0x3299, 0x3299),
    (0x1F000, 0x1FAFF),
];

fn within(table: &[(u32, u32)], character: char) -> bool {
    let value = u32::from(character);
    table
        .iter()
        .any(|(low, high)| (*low..=*high).contains(&value))
}

fn presents_as_emoji(character: char) -> bool {
    within(PRESENTATION, character)
}

fn is_emoji_character(character: char) -> bool {
    within(EMOJI, character)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 絵文字の表示を持つ文字と組み合わせは絵文字の書体で描く() {
        for text in [
            "😄",
            "👍",
            "✨",
            "⚽",
            "🙇\u{200D}♂\u{FE0F}",
            "☺\u{FE0F}",
            "1\u{FE0F}\u{20E3}",
        ] {
            assert!(is_emoji(text), "{text}");
        }
        // 絵文字にもなる字に，肌の色や ZWJ を続けたもの
        assert!(is_emoji("❤\u{200D}🔥"));
    }

    #[test]
    fn 記号は候補の書体で描く() {
        for text in ["→", "★", "※", "℃", "①", "⇒", "〒", "↔", "", "あ"] {
            assert!(!is_emoji(text), "{text}");
        }
    }

    #[test]
    fn 肌の色のボタンは手を振る絵文字に肌の色を付ける() {
        assert_eq!(skin_tone_sample(SkinTone::None), "👋");
        assert_eq!(skin_tone_sample(SkinTone::Medium), "👋🏽");
        assert_eq!(skin_tone_sample(SkinTone::Dark), "👋🏿");
        assert_eq!(SKIN_TONES.len(), 6);
        assert_eq!(SKIN_TONES[0], SkinTone::None);
    }
}
