#![forbid(unsafe_code)]

//! 文字を決まった幅に収める(macOS の TextFitting)．候補の窓の幅には上限があるので(size.candidate.max-width)，
//! 長い文の候補は「…」で省く

const ELLIPSIS: &str = "…";

/// 幅に収まるよう末尾を「…」で省く．省く位置は二分探索で決め，測る回数を文字数の対数に抑える
pub fn truncated(text: &str, width: f32, measure: &dyn Fn(&str) -> f32) -> String {
    if measure(text) <= width {
        return text.to_string();
    }
    let characters: Vec<char> = text.chars().collect();
    let (mut low, mut high) = (0, characters.len());
    while low < high {
        let middle = (low + high).div_ceil(2);
        let candidate: String = characters[..middle].iter().collect::<String>() + ELLIPSIS;
        if measure(&candidate) <= width {
            low = middle;
        } else {
            high = middle - 1;
        }
    }
    if low == 0 {
        String::new()
    } else {
        characters[..low].iter().collect::<String>() + ELLIPSIS
    }
}

/// 幅に収まるよう省く．keeping より後ろの字(ほかの候補と違うところ)をなるべく見せるため，先に頭を「…」で省き，
/// それでも入らなければ末尾も省く．keeping が 0 なら末尾だけを省く
pub fn truncated_keeping(
    text: &str,
    width: f32,
    keeping: usize,
    measure: &dyn Fn(&str) -> f32,
) -> String {
    if measure(text) <= width {
        return text.to_string();
    }
    let characters: Vec<char> = text.chars().collect();
    let keep = keeping.min(characters.len());
    if keep == 0 {
        return truncated(text, width, measure);
    }
    let from = |start: usize| -> String {
        ELLIPSIS.to_string() + &characters[start..].iter().collect::<String>()
    };
    if measure(&from(keep)) > width {
        return truncated(&from(keep), width, measure);
    }
    // 頭を省く字数をなるべく少なくする(start が大きいほど短い)
    let (mut low, mut high) = (1, keep);
    while low < high {
        let middle = (low + high) / 2;
        if measure(&from(middle)) <= width {
            high = middle;
        } else {
            low = middle + 1;
        }
    }
    from(low)
}

/// ほかの候補と頭から同じ字数(いちばん長く一致する候補との)
pub fn shared_prefix_length<'a>(text: &str, others: impl Iterator<Item = &'a str>) -> usize {
    others
        .filter(|other| *other != text)
        .map(|other| {
            text.chars()
                .zip(other.chars())
                .take_while(|(a, b)| a == b)
                .count()
        })
        .max()
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn count(text: &str) -> f32 {
        text.chars().count() as f32
    }

    #[test]
    fn 入らなければ末尾を省く() {
        assert_eq!(truncated("あいうえお", 10.0, &count), "あいうえお");
        assert_eq!(truncated("あいうえお", 3.0, &count), "あい…");
        assert_eq!(truncated("あいうえお", 0.5, &count), "");
    }

    #[test]
    fn 違うところを見せるよう頭を省く() {
        // 頭の 6 字が同じ候補が並ぶとき，違うところ(7 字目から)を残す
        let text = "今日はいい天気ですね";
        assert_eq!(truncated_keeping(text, 6.0, 5, &count), "…天気ですね");
        // 頭を省いても入らなければ末尾も省く
        assert_eq!(truncated_keeping(text, 4.0, 6, &count), "…気で…");
        assert_eq!(truncated_keeping(text, 4.0, 0, &count), "今日は…");
    }

    #[test]
    fn ほかの候補と頭から同じ字数() {
        let others = ["今日はいい天気", "今日は良い天気", "京はいい天気"];
        assert_eq!(
            shared_prefix_length("今日はいい天気", others.iter().copied()),
            3
        );
        assert_eq!(shared_prefix_length("abc", std::iter::empty()), 0);
    }
}
