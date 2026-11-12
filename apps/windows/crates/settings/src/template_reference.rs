#![forbid(unsafe_code)]

//! 単語と変換マクロに書ける書き方のチップ(macOS の core の TemplateReference・FlowLayout，設定の画面の TemplatePalette)．
//! まとまりとチップの文言は strings::templates に置き，ここには押した書き方を語に足す決まりと，切り替えとチップの置き場所を置く．
//! 足す決まりとチップの並べ方は core と同じ(テストも同じ例)．
//! 上の切り替えでまとまりを選び，そのチップを左から並べて送る．チップには書き方と値を並べ，書き方と値はベースラインでそろえる

use crate::layout::Rect;
use tokens::size::{part, space};

/// まとまりの種類．押したときの足し方が変わる
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// `{date}` のような書き方．押すと語の末尾に足す
    Syntax,
    /// `|upper` のような値の変え方．語の最後の書き方の中に足す
    Filter,
    /// `YYYY` のような日時の書式の記号．語の最後の日時の書き方の書式に足す
    FormatSymbol,
}

/// 1 つのチップ
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Item {
    /// チップに出す書き方(`{date}`・`|upper`・`YYYY`)
    pub code: &'static str,
    pub meaning: &'static str,
    /// 語の最後に足せる書き方が無いときに末尾に足す書き方(macOS はチップの値もこれで求める)
    pub sample: &'static str,
    /// チップに添える値．Windows の設定の画面は値を求められないので，2026/04/01(水) 09:30:15 の値を書く(macOS は今の値)
    pub example: &'static str,
    /// 値がコード(UUID・16 進数・Base64 など)で，等幅の書体で出す
    pub code_value: bool,
}

impl Item {
    /// `{date}` のような書き方(sample は code と同じ)
    pub const fn new(code: &'static str, meaning: &'static str, example: &'static str) -> Self {
        Self {
            code,
            meaning,
            sample: code,
            example,
            code_value: false,
        }
    }

    /// 値の変え方と書式の記号(sample は語の末尾に足す書き方)
    pub const fn with_sample(
        code: &'static str,
        meaning: &'static str,
        sample: &'static str,
        example: &'static str,
    ) -> Self {
        Self {
            code,
            meaning,
            sample,
            example,
            code_value: false,
        }
    }

    /// 値を等幅の書体で出す
    pub const fn code_value(self) -> Self {
        Self {
            code_value: true,
            ..self
        }
    }
}

/// 短い見出しを付けたまとまり
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Group {
    pub title: &'static str,
    pub kind: Kind,
    pub items: &'static [Item],
}

/// item を押したときの語．text は欄の入力位置より前の文字．
/// 打ちかけの書き方(`{da`・`{reading|ka`・`{date:YY`)があれば，その打ちかけの部分を置き換える．
/// 無ければ，書き方は末尾に足し，値の変え方と書式の記号は語の最後の書き方に足せれば足し，足せなければ sample を末尾に足す
/// (core の TemplateReference.inserting と同じ)
pub fn inserting(item: &Item, kind: Kind, text: &str) -> String {
    let typed = typing(text);
    let drop = |count: usize| {
        let end = text
            .char_indices()
            .rev()
            .nth(count.saturating_sub(1))
            .map_or(text.len(), |(index, _)| index);
        if count == 0 {
            text
        } else {
            &text[..end]
        }
    };
    match kind {
        Kind::Syntax => match typed {
            Some(Typing::Name(name)) => format!("{}{}", drop(name.chars().count() + 1), item.code),
            _ => format!("{text}{}", item.code),
        },
        Kind::Filter => {
            let filter = item.code.trim_start_matches('|');
            match typed {
                Some(Typing::Filter(typed)) => {
                    format!("{}|{filter}", drop(typed.chars().count() + 1))
                }
                Some(_) => format!("{text}|{filter}"),
                None => {
                    adding_filter(filter, text).unwrap_or_else(|| format!("{text}{}", item.sample))
                }
            }
        }
        Kind::FormatSymbol => match typed {
            Some(Typing::Format(typed)) => {
                format!("{}{}", drop(typed.chars().count()), item.code)
            }
            Some(Typing::Name(name)) if accepts_format(&name) => {
                format!("{text}:{}", item.code)
            }
            Some(_) => format!("{text}{}", item.code),
            None => adding_format_symbol(item.code, text)
                .unwrap_or_else(|| format!("{text}{}", item.sample)),
        },
    }
}

/// 欄の文字の書き換え．range(UTF-16 の位置．EDIT の選択と同じ数え方)を replacement に置き換える
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Edit {
    pub range: std::ops::Range<usize>,
    pub replacement: String,
}

/// 欄で selection(UTF-16 の位置．入力位置なら空の範囲)を選んでいるときに item を押した書き換え．
/// 選んでいる部分を消し，入力位置より前の文字に inserting をかける．書き換える範囲は変わる部分だけにする(取り消しで戻せるように)
pub fn insertion(item: &Item, kind: Kind, text: &str, selection: std::ops::Range<usize>) -> Edit {
    let utf16: Vec<u16> = text.encode_utf16().collect();
    let lower = selection.start.min(utf16.len());
    let upper = selection.end.clamp(lower, utf16.len());
    let prefix = String::from_utf16_lossy(&utf16[..lower]);
    let inserted = inserting(item, kind, &prefix);
    let common = prefix
        .chars()
        .zip(inserted.chars())
        .take_while(|(old, new)| old == new)
        .count();
    let start: usize = prefix.chars().take(common).map(char::len_utf16).sum();
    Edit {
        range: start..upper,
        replacement: inserted.chars().skip(common).collect(),
    }
}

/// 入力位置の前で打ちかけの書き方．何を打っているかで分ける(core の TextTemplate.Typing)
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Typing {
    /// 名前を打っている(`{da` の da．`{` だけなら空)．ずらす量(`+1d`)も含む
    Name(String),
    /// 値の変え方を打っている(`{reading|ka` の ka)
    Filter(String),
    /// 日時の書式を打っている(`{date:YY` の YY．書式の末尾の英字)
    Format(String),
    /// そのほかの引数を打っている(`{random:1-`)
    Argument,
}

/// prefix(欄の入力位置より前)の末尾の打ちかけの書き方(`{da`)．閉じていれば・打ちかけでなければ None(`{{` は文字の「{」)
pub fn open_placeholder(prefix: &str) -> Option<String> {
    match pieces(prefix).pop()? {
        Piece::Unclosed(text) if prefix.ends_with(&text) => Some(text),
        _ => None,
    }
}

/// prefix の末尾で打ちかけの書き方を，何を打っているかで分けたもの
pub fn typing(prefix: &str) -> Option<Typing> {
    let text = open_placeholder(prefix)?;
    let body = &text[1..];
    if let Some(bar) = body.rfind('|') {
        return Some(Typing::Filter(body[bar + 1..].to_string()));
    }
    let Some((name, argument)) = body.split_once(':') else {
        return Some(Typing::Name(body.to_string()));
    };
    if !FORMATTED_DATE_NAMES.contains(&name_of(name)) {
        return Some(Typing::Argument);
    }
    let letters: Vec<char> = argument
        .chars()
        .rev()
        .take_while(char::is_ascii_alphabetic)
        .collect();
    Some(Typing::Format(letters.into_iter().rev().collect()))
}

/// 書き方の中身(`date+1d:M/D|upper`)の名前(`date`)
pub fn name_of(body: &str) -> &str {
    let head = body.split('|').next().unwrap_or_default();
    let name_and_steps = head.split(':').next().unwrap_or_default();
    let end = name_and_steps
        .find(['+', '-', '@'])
        .unwrap_or(name_and_steps.len());
    &name_and_steps[..end]
}

/// 打ちかけの名前(`date+1d`)が，書式の記号を引数に書ける日時の名前か
pub fn accepts_format(name: &str) -> bool {
    !name.contains(':') && FORMATTED_DATE_NAMES.contains(&name_of(name))
}

/// 打ちかけの書き方に当たるチップ(まとまりの順)．絞り込まないとき(打ちかけでない・名前をまだ打っていない・
/// 日時でない引数を打っている)は None．
/// 名前を打ちかけているあいだ(`{da`)は，当たる名前ごとに最初のチップを 1 つずつ並べる(date・datetime・days)．
/// 名前を打ち終えたら(`{date`)，ずらす量や引数を付けたものも並べる(core の TemplateReference.matches と同じ)
pub fn matches(groups: &[Group], typed: Option<&Typing>) -> Option<Vec<(Item, Kind)>> {
    let body = |code: &str| {
        code.strip_prefix('{')
            .and_then(|code| code.strip_suffix('}'))
            .unwrap_or(code)
            .to_string()
    };
    let (kind, query, case_sensitive, one_per_name) = match typed {
        Some(Typing::Name(name)) if !name.is_empty() => {
            let lowered = name.to_lowercase();
            let known = groups
                .iter()
                .filter(|group| group.kind == Kind::Syntax)
                .flat_map(|group| group.items)
                .any(|item| name_of(&body(item.code)) == lowered);
            let one = !known && !lowered.contains(['+', '-', '@', ':']);
            (Kind::Syntax, lowered, false, one)
        }
        Some(Typing::Filter(typed)) => (Kind::Filter, typed.to_lowercase(), false, false),
        // 書式の記号は大文字と小文字で意味が違う(M は月，m は分)
        Some(Typing::Format(typed)) => (Kind::FormatSymbol, typed.clone(), true, false),
        _ => return None,
    };
    let mut seen = std::collections::HashSet::new();
    let mut found = Vec::new();
    for group in groups.iter().filter(|group| group.kind == kind) {
        for item in group.items {
            let code = match kind {
                Kind::FormatSymbol => item.code.to_string(),
                _ => item.code.chars().skip(1).collect::<String>().to_lowercase(),
            };
            let code = if case_sensitive {
                code
            } else {
                code.to_lowercase()
            };
            if !code.starts_with(&query) {
                continue;
            }
            let key = if one_per_name {
                name_of(&body(item.code)).to_string()
            } else {
                item.code.to_string()
            };
            if seen.insert(key) {
                found.push((*item, kind));
            }
        }
    }
    Some(found)
}

/// text の最後の置き換える部分(`{…}`)の中身．最後が置き換える部分で終わっていなければ None(`{{` `}}` は文字なので数えない．
/// core の TextTemplate の読み方と同じ)
fn trailing_placeholder(text: &str) -> Option<&str> {
    let characters: Vec<(usize, char)> = text.char_indices().collect();
    let mut index = 0;
    let mut last = None;
    while index < characters.len() {
        let (_, character) = characters[index];
        let next = characters.get(index + 1).map(|(_, next)| *next);
        if (character == '{' && next == Some('{')) || (character == '}' && next == Some('}')) {
            last = None;
            index += 2;
            continue;
        }
        if character == '{' {
            // 次の `}` までに `{` が無ければ置き換える部分
            let close = characters[index + 1..]
                .iter()
                .position(|(_, other)| *other == '}');
            let open = characters[index + 1..]
                .iter()
                .position(|(_, other)| *other == '{');
            if let Some(close) = close.filter(|close| open.is_none_or(|open| open > *close)) {
                let start = characters[index].0 + 1;
                let end = characters[index + 1 + close].0;
                last = Some((start, end));
                index += close + 2;
                continue;
            }
        }
        last = None;
        index += 1;
    }
    let (start, end) = last?;
    (end + 1 == text.len()).then(|| &text[start..end])
}

/// text の最後の置き換える部分に，値の変え方(`|upper` の upper)を足した語
fn adding_filter(name: &str, text: &str) -> Option<String> {
    trailing_placeholder(text)?;
    Some(format!("{}|{name}}}", &text[..text.len() - 1]))
}

/// 書式の記号(DateTimeFormat)を引数に書ける日時の名前
const FORMATTED_DATE_NAMES: [&str; 4] = ["datetime", "date", "time", "utc"];

/// text の最後の日時の書き方(`{date:M/D}`)の書式の末尾に，書式の記号を足した語．書式の無い `{date}` には足さない
/// (既定の書式が記号だけに置き換わるため)
fn adding_format_symbol(symbol: &str, text: &str) -> Option<String> {
    let body = trailing_placeholder(text)?;
    let mut segments = body.split('|');
    let head = segments.next().unwrap_or_default();
    let filters: String = segments
        .filter(|filter| !filter.is_empty())
        .map(|filter| format!("|{filter}"))
        .collect();
    let (name_and_steps, argument) = head.split_once(':')?;
    let name_end = name_and_steps
        .find(['+', '-', '@'])
        .unwrap_or(name_and_steps.len());
    if !FORMATTED_DATE_NAMES.contains(&&name_and_steps[..name_end]) {
        return None;
    }
    let prefix = &text[..text.len() - body.len() - 2];
    Some(format!(
        "{prefix}{{{name_and_steps}:{argument}{symbol}{filters}}}"
    ))
}

/// 語の中のひとまとまり(core の TextTemplate の読み方と同じ)
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Piece {
    /// 文字のまま入る部分(`{{` `}}` は `{` `}` にしたもの)
    Literal(String),
    /// 置き換える部分(`{` と `}` の間)
    Placeholder(String),
    /// 閉じていない `{` から次の `{` の前まで(文字のまま入る．書き方の誤り)
    Unclosed(String),
}

/// 語をひとまとまりずつに分ける(core の TextTemplate.tokens と同じ決まり)
pub fn pieces(text: &str) -> Vec<Piece> {
    let characters: Vec<char> = text.chars().collect();
    let mut pieces = Vec::new();
    let mut literal = String::new();
    let mut index = 0;
    let flush = |literal: &mut String, pieces: &mut Vec<Piece>| {
        if !literal.is_empty() {
            pieces.push(Piece::Literal(std::mem::take(literal)));
        }
    };
    while index < characters.len() {
        let character = characters[index];
        let next = characters.get(index + 1).copied();
        if (character == '{' && next == Some('{')) || (character == '}' && next == Some('}')) {
            literal.push(character);
            index += 2;
            continue;
        }
        if character == '{' {
            let rest = &characters[index + 1..];
            let close = rest.iter().position(|other| *other == '}');
            let open = rest.iter().position(|other| *other == '{');
            flush(&mut literal, &mut pieces);
            match close.filter(|close| open.is_none_or(|open| open > *close)) {
                Some(close) => {
                    pieces.push(Piece::Placeholder(rest[..close].iter().collect()));
                    index += close + 2;
                }
                None => {
                    let end = open.unwrap_or(rest.len());
                    pieces.push(Piece::Unclosed(
                        std::iter::once('{')
                            .chain(rest[..end].iter().copied())
                            .collect(),
                    ));
                    index += end + 1;
                }
            }
            continue;
        }
        literal.push(character);
        index += 1;
    }
    flush(&mut literal, &mut pieces);
    pieces
}

// MARK: - 置き場所

/// 文字の書体
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Face {
    /// チップの書き方(等幅)
    Code,
    /// チップに添える値
    Value,
    /// チップに添えるコードの値(等幅)
    CodeValue,
    /// まとまりの切り替えの見出し
    Switch,
}

/// 文字を測る口(設定の画面は DirectWrite で測る)．チップも切り替えも 1 行
pub trait Measure {
    /// 1 行にしたときの幅
    fn width(&self, text: &str, face: Face) -> f32;
    /// 1 行の高さ
    fn line_height(&self, face: Face) -> f32;
    /// 行の上端からベースラインまで(行の中の字の書体で変わるので，文字ごとに測る)
    fn baseline(&self, text: &str, face: Face) -> f32;
}

/// チップを左から並べ，幅に収まらなければ次の行に送る(core の FlowLayout と同じ)．チップごとの左端と行の番号．
/// 行の先頭のチップは左端に置き，1 つで幅を超えるチップも行の先頭に置く(縮めない)
pub fn flow(widths: &[f32], spacing: f32, width: f32) -> Vec<(f32, usize)> {
    let mut placements = Vec::with_capacity(widths.len());
    let (mut x, mut row) = (0.0_f32, 0_usize);
    for item in widths {
        if x > 0.0 && x + item > width {
            row += 1;
            x = 0.0;
        }
        placements.push((x, row));
        x += item + spacing;
    }
    placements
}

/// まとまりの切り替えの欄．ページの上の切り替え(登録した単語・取り込んだ辞書)と同じ形を小さくしたもので，
/// 欄を左から隙間なく並べる．高さは欄の高さ
pub fn place_switch(groups: &[Group], measure: &dyn Measure) -> Vec<Rect> {
    let mut x = 0.0;
    groups
        .iter()
        .map(|group| {
            let width =
                (measure.width(group.title, Face::Switch) + part::FIELD_PADDING_X * 2.0).ceil();
            let rect = Rect::new(x, 0.0, width, part::FIELD_HEIGHT);
            x += width;
            rect
        })
        .collect()
}

/// 1 つのチップの置き場所(チップを並べる欄の左上を 0 とする)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Chip {
    /// group.items の番号
    pub item: usize,
    /// 押せる範囲(書き方のチップと値)
    pub area: Rect,
    /// 書き方のチップの背景
    pub tag: Rect,
    pub code: Rect,
    /// 値(空なら幅 0)
    pub value: Rect,
}

/// チップの並び
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Chips {
    pub chips: Vec<Chip>,
    pub height: f32,
}

impl Chips {
    /// (x, y)(チップを並べる欄の左上から)にあるチップ(group.items の番号)
    pub fn item_at(&self, x: f32, y: f32) -> Option<usize> {
        self.chips
            .iter()
            .find(|chip| {
                x >= chip.area.x
                    && x < chip.area.max_x()
                    && y >= chip.area.y
                    && y < chip.area.max_y()
            })
            .map(|chip| chip.item)
    }
}

/// チップに添える値．エンジンから読んだ今の値(live)があればそれ，無ければ決めておいた例．
/// 見本のエンジン(--offline)は書き方をそのまま返すので，書き方と同じなら例を出す
pub fn value_of<'a>(item: &'a Item, live: Option<&'a str>) -> &'a str {
    live.filter(|value| !value.is_empty() && *value != item.sample)
        .unwrap_or(item.example)
}

/// チップ(items)を幅 width に並べる．values はチップに添える今の値(チップと同じ並び．value_of)．
/// チップとチップの間と行の間は group(押せる部品どうしの間)．
/// 書き方のチップの高さはチップの字の行の高さに上下の余白を足したもの．書き方と値は 1 行目のベースラインでそろえる
pub fn place_chips(items: &[Item], values: &[String], width: f32, measure: &dyn Measure) -> Chips {
    let tag_height = measure.line_height(Face::Code) + part::TAG_PADDING_Y * 2.0;
    let value_height = measure
        .line_height(Face::Value)
        .max(measure.line_height(Face::CodeValue));
    let row_height = tag_height.max(value_height);
    let faces: Vec<Face> = items
        .iter()
        .map(|item| {
            if item.code_value {
                Face::CodeValue
            } else {
                Face::Value
            }
        })
        .collect();
    let codes: Vec<f32> = items
        .iter()
        .map(|item| (measure.width(item.code, Face::Code) + part::TAG_PADDING_X * 2.0).ceil())
        .collect();
    let texts: Vec<&str> = items
        .iter()
        .enumerate()
        .map(|(index, item)| value_of(item, values.get(index).map(String::as_str)))
        .collect();
    let values: Vec<f32> = texts
        .iter()
        .zip(&faces)
        .map(|(text, face)| {
            if text.is_empty() {
                0.0
            } else {
                measure.width(text, *face).ceil()
            }
        })
        .collect();
    let widths: Vec<f32> = codes
        .iter()
        .zip(&values)
        .map(|(code, value)| {
            if *value > 0.0 {
                code + space::INLINE + value
            } else {
                *code
            }
        })
        .collect();
    let mut chips = Vec::with_capacity(items.len());
    let mut rows = 0;
    for (index, (x, row)) in flow(&widths, space::GROUP, width).into_iter().enumerate() {
        let item = &items[index];
        rows = rows.max(row + 1);
        let top = row as f32 * (row_height + space::GROUP);
        // 書き方のチップは行の真ん中に置き，値は書き方の字のベースラインにそろえる
        let tag = Rect::new(
            x,
            top + (row_height - tag_height) / 2.0,
            codes[index],
            tag_height,
        );
        let code_baseline = measure.baseline(item.code, Face::Code);
        let baseline = tag.y + part::TAG_PADDING_Y + code_baseline;
        let code = Rect::new(
            x + part::TAG_PADDING_X,
            baseline - code_baseline,
            (codes[index] - part::TAG_PADDING_X * 2.0).max(0.0),
            measure.line_height(Face::Code),
        );
        let value = if values[index] > 0.0 {
            Rect::new(
                tag.max_x() + space::INLINE,
                baseline - measure.baseline(texts[index], faces[index]),
                values[index],
                measure.line_height(faces[index]),
            )
        } else {
            Rect::new(tag.max_x(), top, 0.0, 0.0)
        };
        chips.push(Chip {
            item: index,
            area: Rect::new(x, top, widths[index], row_height),
            tag,
            code,
            value,
        });
    }
    let height = if rows == 0 {
        0.0
    } else {
        rows as f32 * row_height + (rows - 1) as f32 * space::GROUP
    };
    Chips { chips, height }
}

#[cfg(test)]
mod tests {
    use super::*;

    const GROUP: Group = Group {
        title: "日時",
        kind: Kind::Syntax,
        items: &[
            Item::new("{date}", "今日の日付", "2026/04/01"),
            Item::new("{time}", "今の時刻", "09:30"),
            Item::new("{holiday}", "祝日の名前", ""),
            Item::new("{uuid}", "UUID", "3F2504E0-4F89-11D3-9A0C-0305E82C3301").code_value(),
        ],
    };

    #[test]
    fn 入力位置の前の打ちかけの書き方を分ける() {
        let typed = |prefix: &str| typing(prefix);
        assert_eq!(typed("締切 {"), Some(Typing::Name(String::new())));
        assert_eq!(typed("{date} {da"), Some(Typing::Name("da".into())));
        assert_eq!(typed("{date+1"), Some(Typing::Name("date+1".into())));
        assert_eq!(typed("{reading|ka"), Some(Typing::Filter("ka".into())));
        assert_eq!(typed("{date:M月D"), Some(Typing::Format("D".into())));
        assert_eq!(typed("{date+1w:YY"), Some(Typing::Format("YY".into())));
        assert_eq!(typed("{date:M月"), Some(Typing::Format(String::new())));
        assert_eq!(typed("{random:1-"), Some(Typing::Argument));
        // 閉じた書き方と {{(文字の「{」)は打ちかけではない
        assert_eq!(typed("{date}"), None);
        assert_eq!(typed("{{da"), None);
        assert_eq!(typed(""), None);
    }

    #[test]
    fn 打ちかけの書き方に当たるチップだけを返す() {
        const GROUPS: &[Group] = &[
            Group {
                title: "日時",
                kind: Kind::Syntax,
                items: &[
                    Item::new("{date}", "日付", ""),
                    Item::new("{time}", "時刻", ""),
                    Item::new("{datetime}", "日時", ""),
                ],
            },
            Group {
                title: "暦",
                kind: Kind::Syntax,
                items: &[
                    Item::new("{days:12/25}", "日数", ""),
                    Item::new("{days:2027-03-31}", "日数", ""),
                    Item::new("{date}", "日付", ""),
                ],
            },
            Group {
                title: "変換",
                kind: Kind::Filter,
                items: &[
                    Item::new("|katakana", "カタカナ", ""),
                    Item::new("|kansuji", "漢数字", ""),
                    Item::new("|upper", "大文字", ""),
                ],
            },
            Group {
                title: "書式",
                kind: Kind::FormatSymbol,
                items: &[
                    Item::new("YYYY", "年", ""),
                    Item::new("MM", "月", ""),
                    Item::new("mm", "分", ""),
                ],
            },
        ];
        let codes = |typed: Option<Typing>| {
            matches(GROUPS, typed.as_ref())
                .map(|found| found.iter().map(|(item, _)| item.code).collect::<Vec<_>>())
        };
        // 名前を打ちかけているあいだは名前ごとに 1 つ．打ち終えたら，その名前で始まるものをすべて
        assert_eq!(
            codes(Some(Typing::Name("Da".into()))),
            Some(vec!["{date}", "{datetime}", "{days:12/25}"])
        );
        assert_eq!(
            codes(Some(Typing::Name("date".into()))),
            Some(vec!["{date}", "{datetime}"])
        );
        assert_eq!(
            codes(Some(Typing::Name("days".into()))),
            Some(vec!["{days:12/25}", "{days:2027-03-31}"])
        );
        assert_eq!(codes(Some(Typing::Name("date+".into()))), Some(vec![]));
        assert_eq!(
            codes(Some(Typing::Filter("ka".into()))),
            Some(vec!["|katakana", "|kansuji"])
        );
        // 書式の記号は大文字と小文字を分ける(M は月，m は分)
        assert_eq!(codes(Some(Typing::Format("M".into()))), Some(vec!["MM"]));
        assert_eq!(codes(Some(Typing::Name(String::new()))), None);
        assert_eq!(codes(Some(Typing::Argument)), None);
        assert_eq!(codes(None), None);
    }

    #[test]
    fn 打ちかけの書き方は押したチップで置き換える() {
        let date = Item::new("{date}", "日付", "");
        let katakana = Item::with_sample("|katakana", "カタカナ", "{reading|katakana}", "");
        let year = Item::with_sample("YYYY", "年", "{date:YYYY}", "");
        assert_eq!(inserting(&date, Kind::Syntax, "締切 {da"), "締切 {date}");
        assert_eq!(inserting(&date, Kind::Syntax, "{"), "{date}");
        assert_eq!(
            inserting(&katakana, Kind::Filter, "{reading|ka"),
            "{reading|katakana"
        );
        assert_eq!(
            inserting(&katakana, Kind::Filter, "{reading"),
            "{reading|katakana"
        );
        assert_eq!(
            inserting(&year, Kind::FormatSymbol, "{date:M/D YY"),
            "{date:M/D YYYY"
        );
        assert_eq!(
            inserting(&year, Kind::FormatSymbol, "{date+1d"),
            "{date+1d:YYYY"
        );
    }

    #[test]
    fn 入力位置に入れ書き換える範囲は変わる部分だけにする() {
        let date = Item::new("{date}", "日付", "");
        let upper = Item::with_sample("|upper", "大文字", "{date:MMM|upper}", "");
        let edit = |item: &Item, kind: Kind, text: &str, selection: std::ops::Range<usize>| {
            let edit = insertion(item, kind, text, selection);
            (edit.range, edit.replacement)
        };
        // 「締切 {da|まで」(| が入力位置)．打ちかけの {da を {date} にし，後ろの「まで」は残す
        assert_eq!(
            edit(&date, Kind::Syntax, "締切 {daまで", 6..6),
            (6..6, "te}".to_string())
        );
        // 選んでいる部分は置き換える
        assert_eq!(
            edit(&date, Kind::Syntax, "締切 XX", 3..5),
            (3..5, "{date}".to_string())
        );
        // 入力位置の直前の書き方に値の変え方を足す(閉じかっこの前に入る)
        assert_eq!(
            edit(&upper, Kind::Filter, "{uuid} です", 6..6),
            (5..6, "|upper}".to_string())
        );
        // 範囲の外の入力位置は末尾にそろえる
        assert_eq!(
            edit(&date, Kind::Syntax, "😀", 9..9),
            (2..2, "{date}".to_string())
        );
    }

    /// 全角を 1，半角を 0.5 文字とみなし，12 を掛ける．書体ごとに行の高さとベースラインを変えて，そろえる計算を確かめる
    struct Estimate;

    impl Measure for Estimate {
        fn width(&self, text: &str, _: Face) -> f32 {
            text.chars()
                .map(|character| if character.is_ascii() { 0.5 } else { 1.0 })
                .sum::<f32>()
                * 12.0
        }

        fn line_height(&self, face: Face) -> f32 {
            match face {
                Face::Code => 14.0,
                Face::Value | Face::CodeValue => 16.0,
                Face::Switch => 20.0,
            }
        }

        fn baseline(&self, text: &str, face: Face) -> f32 {
            // 全角の字のある行は日本語の書体のベースラインになる
            match face {
                Face::Code if !text.is_ascii() => 12.0,
                Face::Code => 11.0,
                Face::Value | Face::CodeValue | Face::Switch => 13.0,
            }
        }
    }

    #[test]
    fn 書き方は語の末尾に足す() {
        let item = Item::new("{date}", "今日の日付", "");
        assert_eq!(inserting(&item, Kind::Syntax, ""), "{date}");
        assert_eq!(inserting(&item, Kind::Syntax, "締切 "), "締切 {date}");
        assert_eq!(inserting(&item, Kind::Syntax, "{time}"), "{time}{date}");
    }

    #[test]
    fn 値の変え方は最後の書き方の中に足し_足せなければ例の書き方を末尾に足す() {
        let upper = Item::with_sample("|upper", "大文字", "{date:MMM|upper}", "");
        let chain = Item::with_sample(
            "|upper|fullwidth",
            "左から順にかける",
            "{date:MMM|upper|fullwidth}",
            "",
        );
        assert_eq!(
            inserting(&upper, Kind::Filter, "{date:MMM}"),
            "{date:MMM|upper}"
        );
        assert_eq!(
            inserting(&upper, Kind::Filter, "{uuid|lower}"),
            "{uuid|lower|upper}"
        );
        assert_eq!(
            inserting(&chain, Kind::Filter, "{text}"),
            "{text|upper|fullwidth}"
        );
        assert_eq!(inserting(&upper, Kind::Filter, ""), "{date:MMM|upper}");
        assert_eq!(
            inserting(&upper, Kind::Filter, "{date}です"),
            "{date}です{date:MMM|upper}"
        );
        // }} は文字の「}」で，書き方の終わりではない
        assert_eq!(
            inserting(&upper, Kind::Filter, "{{date}}"),
            "{{date}}{date:MMM|upper}"
        );
    }

    #[test]
    fn 書式の記号は最後の日時の書き方の書式に足し_書式が無ければ例の書き方を末尾に足す() {
        let weekday = Item::with_sample("ddd", "曜日（略）", "{date:ddd}", "");
        assert_eq!(
            inserting(&weekday, Kind::FormatSymbol, "{date:M/D}"),
            "{date:M/Dddd}"
        );
        assert_eq!(
            inserting(&weekday, Kind::FormatSymbol, "{date+1w@mon:M/D(|kansuji}"),
            "{date+1w@mon:M/D(ddd|kansuji}"
        );
        assert_eq!(
            inserting(&weekday, Kind::FormatSymbol, "{utc:YYYY}"),
            "{utc:YYYYddd}"
        );
        // 書式の無い {date} に足すと既定の書式が消えるので，例を足す
        assert_eq!(
            inserting(&weekday, Kind::FormatSymbol, "{date}"),
            "{date}{date:ddd}"
        );
        assert_eq!(
            inserting(&weekday, Kind::FormatSymbol, "{holiday:平日}"),
            "{holiday:平日}{date:ddd}"
        );
        assert_eq!(inserting(&weekday, Kind::FormatSymbol, ""), "{date:ddd}");
    }

    #[test]
    fn 語を置き換える部分と閉じていない括弧に分ける() {
        assert_eq!(
            pieces("締切 {date:M/D}です"),
            vec![
                Piece::Literal("締切 ".into()),
                Piece::Placeholder("date:M/D".into()),
                Piece::Literal("です".into()),
            ]
        );
        // 閉じていない { は次の { の前まで(core の TextTemplate.problems と同じ例)
        assert_eq!(
            pieces("{date:M/D {time}"),
            vec![
                Piece::Unclosed("{date:M/D ".into()),
                Piece::Placeholder("time".into()),
            ]
        );
        assert_eq!(
            pieces("締切 {date"),
            vec![
                Piece::Literal("締切 ".into()),
                Piece::Unclosed("{date".into())
            ]
        );
        assert_eq!(pieces("{{date}}"), vec![Piece::Literal("{date}".into())]);
    }

    #[test]
    fn チップは左端から間をそろえて並べ_幅を超えるチップは次の行の左端に送る() {
        let placements = flow(&[40.0, 60.0, 50.0, 30.0], space::GROUP, 120.0);
        assert_eq!(
            placements,
            vec![
                (0.0, 0),
                (40.0 + space::GROUP, 0),
                (0.0, 1),
                (50.0 + space::GROUP, 1)
            ]
        );
        // 1 つで幅を超えるチップも縮めず行の先頭に置く(core の FlowLayout と同じ)
        let wide = flow(&[30.0, 300.0, 30.0], space::GROUP, 120.0);
        assert_eq!(wide, vec![(0.0, 0), (0.0, 1), (0.0, 2)]);
    }

    #[test]
    fn 書き方と値は1行目のベースラインでそろえ_チップは重ならない() {
        let placed = place_chips(GROUP.items, &[], 400.0, &Estimate);
        assert_eq!(placed.chips.len(), 4);
        for (chip, item) in placed.chips.iter().zip(GROUP.items) {
            if chip.value.width > 0.0 {
                let code = chip.code.y + Estimate.baseline(item.code, Face::Code);
                let face = if item.code_value {
                    Face::CodeValue
                } else {
                    Face::Value
                };
                let value = chip.value.y + Estimate.baseline(item.example, face);
                assert!((code - value).abs() <= 0.5, "{item:?}");
                // 値はチップの右に inline の間をあけて置く
                assert_eq!(chip.value.x, chip.tag.max_x() + space::INLINE);
            }
            assert_eq!(chip.code.x, chip.tag.x + part::TAG_PADDING_X);
            assert!(chip.tag.y >= chip.area.y && chip.tag.max_y() <= chip.area.max_y());
        }
        // 値の無いチップ(祝日でない日の {holiday})は書き方だけ
        assert_eq!(placed.chips[2].value.width, 0.0);
        assert_eq!(placed.chips[2].area.width, placed.chips[2].tag.width);
        for pair in placed.chips.windows(2) {
            let (a, b) = (pair[0].area, pair[1].area);
            assert!(
                b.x >= a.max_x() + space::GROUP - 0.01 || b.y >= a.max_y() + space::GROUP - 0.01
            );
        }
    }

    #[test]
    fn チップの値は今の値があればそれを_無いか書き方のままなら例を出す() {
        let item = GROUP.items[0];
        assert_eq!(value_of(&item, Some("2026/11/12")), "2026/11/12");
        assert_eq!(value_of(&item, Some("")), "2026/04/01");
        assert_eq!(value_of(&item, Some("{date}")), "2026/04/01");
        assert_eq!(value_of(&item, None), "2026/04/01");
        let live = vec!["2026/11/12 (今日)".to_string()];
        let wide = place_chips(GROUP.items, &live, 400.0, &Estimate);
        let narrow = place_chips(GROUP.items, &[], 400.0, &Estimate);
        assert!(wide.chips[0].value.width > narrow.chips[0].value.width);
    }

    #[test]
    fn チップの並びの高さは行の数と行の間から決まり_押した位置のチップを引く() {
        let placed = place_chips(GROUP.items, &[], 200.0, &Estimate);
        let last = placed
            .chips
            .last()
            .map(|chip| chip.area.max_y())
            .unwrap_or_default();
        assert!((placed.height - last).abs() < 0.01);
        let first = placed.chips[0].area;
        assert_eq!(placed.item_at(first.x + 1.0, first.y + 1.0), Some(0));
        assert_eq!(placed.item_at(first.max_x() + 1.0, first.y + 1.0), None);
    }

    #[test]
    fn 切り替えの欄は左から隙間なく並べる() {
        let groups = [
            GROUP,
            Group {
                title: "ずらす",
                ..GROUP
            },
        ];
        let rects = place_switch(&groups, &Estimate);
        assert_eq!(rects[0].x, 0.0);
        assert_eq!(rects[1].x, rects[0].max_x());
        assert!(rects.iter().all(|rect| rect.height == part::FIELD_HEIGHT));
    }
}
