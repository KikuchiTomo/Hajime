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

/// text の頭から width に入る 1 行の字数(text が空でなければ少なくとも 1 字)．英数字の語は空白・「-」・「_」のあとで分け，
/// 語が 1 行に入らなければ途中で分ける．日本語はどの字のあいだでも分けるが，句読点などを行の頭に置かない．
/// Unicode の名前・ショートコード・見出しの名前を折り返すのに使う(macOS の TextFitting.lineBreak)
pub fn line_break(text: &[char], width: f32, measure: &dyn Fn(&str) -> f32) -> usize {
    let prefix = |end: usize| text[..end].iter().collect::<String>();
    if measure(&prefix(text.len())) <= width {
        return text.len();
    }
    // text[..low] は入る(1 字目は入らなくても置く)．text[..high] は入らない
    let (mut low, mut high) = (1, text.len());
    while high - low > 1 {
        let middle = (low + high) / 2;
        if measure(&prefix(middle)) <= width {
            low = middle;
        } else {
            high = middle;
        }
    }
    (1..=low)
        .rev()
        .find(|end| can_break(text, *end))
        .unwrap_or(low)
}

/// 幅 width で折り返した行．行の頭と末尾の空白は除く．max_lines を超える分は，最後の行の末尾を「…」にして省く
/// (macOS の TextFitting.wrapped)
pub fn wrapped(
    text: &str,
    width: f32,
    max_lines: usize,
    measure: &dyn Fn(&str) -> f32,
) -> Vec<String> {
    let mut lines = Vec::new();
    let mut rest: Vec<char> = text.chars().collect();
    while !rest.is_empty() && lines.len() < max_lines {
        let count = line_break(&rest, width, measure);
        if lines.len() + 1 == max_lines && count < rest.len() {
            lines.push(truncated(&rest.iter().collect::<String>(), width, measure));
            break;
        }
        lines.push(rest[..count].iter().collect::<String>().trim().to_string());
        rest = rest[count..]
            .iter()
            .skip_while(|character| **character == ' ')
            .copied()
            .collect();
    }
    lines
}

/// 行の頭に置かない字
const LINE_START_FORBIDDEN: &str = "、。，．・：；？！ー…‥）」』】〕〉》,.:;!?)]}";

/// text[end - 1] と text[end] のあいだで行を分けてよいか．英数字の語の途中と，行の頭に置かない字の前では分けない
fn can_break(text: &[char], end: usize) -> bool {
    let (Some(&before), Some(&after)) = (text.get(end.wrapping_sub(1)), text.get(end)) else {
        return true;
    };
    if LINE_START_FORBIDDEN.contains(after) {
        return false;
    }
    if matches!(before, ' ' | '-' | '_') || after == ' ' {
        return true;
    }
    !(before.is_ascii() && after.is_ascii())
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
    fn 語の切れ目で折り返し_入らない語は途中で分ける() {
        let characters = |text: &str| text.chars().collect::<Vec<_>>();
        // 「SMILING FACE」は 12 字．7 字の幅なら空白の前で分ける(空白は次の行の頭で除く)
        assert_eq!(line_break(&characters("SMILING FACE"), 7.5, &count), 7);
        assert_eq!(line_break(&characters("SMILING FACE"), 9.0, &count), 8);
        assert_eq!(line_break(&characters("SMILING FACE"), 20.0, &count), 12);
        // ショートコードは「_」のあとで分ける．切れ目が無ければ語の途中で分ける
        assert_eq!(line_break(&characters("face_with_hand"), 11.0, &count), 10);
        assert_eq!(line_break(&characters("U+1F604"), 4.0, &count), 4);
        // 1 字目が入らなくても 1 字は置く
        assert_eq!(line_break(&characters("あ"), 0.5, &count), 1);
        assert_eq!(
            wrapped("SMILING FACE WITH OPEN MOUTH", 12.0, 9, &count),
            ["SMILING FACE", "WITH OPEN", "MOUTH"]
        );
        // 行の数の上限を超える分は最後の行の末尾を省く
        assert_eq!(
            wrapped("SMILING FACE WITH OPEN MOUTH", 12.0, 2, &count),
            ["SMILING FACE", "WITH OPEN M…"]
        );
        // 日本語はどの字のあいだでも分け，句読点などを行の頭に置かない
        assert_eq!(
            wrapped(
                "旗: サウスジョージア・サウスサンドウィッチ諸島",
                12.0,
                9,
                &count
            ),
            ["旗: サウスジョージア・", "サウスサンドウィッチ諸島"]
        );
        // 「・」を行の頭に置かないよう，前の字から次の行へ送る
        assert_eq!(
            wrapped("サウスジョージア・サウス", 8.0, 9, &count),
            ["サウスジョージ", "ア・サウス"]
        );
        assert!(wrapped("", 12.0, 2, &count).is_empty());
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
