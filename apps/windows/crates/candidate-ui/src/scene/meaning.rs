#![forbid(unsafe_code)]

//! 語の意味(R-08．macOS の MeaningCardDrawing)．一覧(list)と分岐図(branch)で同じものを使う．
//!
//! 箱は描かず，候補の列(分岐図では候補の枝)の続きとして置く．
//! 上から順に，見出し(辞書のアイコン・語・品詞の札)，意味，使い方の例，同音語を並べる．
//! - 意味が 2 つ以上なら，頭に角丸の四角の番号を付ける(候補の番号の丸と形を変え，番号キーで選ぶものと見分ける)
//! - 意味と例は語の意味の幅で折り返す(行の頭に句読点や小さいかなを置かない)．行数の上限を超える分は「…」で省く
//! - 使い方の例は左に縦の線を引いて控えめな色で出し，例の中の見出しの語だけを強める
//! - 同音語は区切りの線の下に，耳のアイコンと札だけで並べる．入らない札は「+n」にまとめる
//!
//! 候補の右に出すときは，一覧でも分岐図でも，選んでいる候補から見出しへ線を引く(アクセントの色はこの線だけに使う)

use super::card_layout::{self, CardLayout, Content, Placement, SenseLines};
use super::paint::Painter;
use super::{Draw, Figure, Frame, Look, Measure, Point, Segment};
use crate::keys::Icon;
use crate::strings;
use crate::theme::{Color, Font};
use ipc::{BranchColumn, BranchMap, CandidateList, HomophoneNote, MeaningPlacement};
use std::ops::Range;
use tokens::opacity;
use tokens::size::{branch, glass, meaning};

/// 行の頭に置かない字(句読点・閉じ括弧・中点・長音・繰り返しの記号・小さいかな)．折り返すときは前の行に付ける
const LINE_START_FORBIDDEN: &str = "、。，．,.:;!?)]}）］｝」』】〕〉》・：；？！ー…‥々ゝゞヽヾぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ";

const ELLIPSIS: char = '…';

/// 書体と色
#[derive(Debug, Clone, Copy, PartialEq)]
struct Style {
    font: Font,
    color: Color,
}

/// 1 行の中の，同じ書体と色で書く字の並び．候補の語を含むので Debug を付けない(中身をログに出さない)
struct Run {
    text: String,
    style: Style,
}

/// 折り返した 1 行
struct Line {
    runs: Vec<Run>,
}

/// 配置を決めた語の意味(配置は card_layout)
pub(super) struct Card {
    /// 意味ごとの，折り返した意味の行と例の行
    meaning: Vec<Vec<Line>>,
    example: Vec<Vec<Line>>,
    layout: CardLayout,
    pub width: f32,
    pub height: f32,
}

impl Card {
    /// 幅 width の語の意味．placement は目印の列の左の端と見出しの行の縦の真ん中
    pub fn new(
        painter: &Painter,
        note: &HomophoneNote,
        others: Vec<String>,
        width: f32,
        placement: Placement,
    ) -> Self {
        let theme = painter.theme;
        let measure = painter.measure;
        let columns = card_layout::Columns::new(width, placement.left);
        let numbered = note.senses.len() > 1;
        let body = Style {
            font: Font::MeaningBody,
            color: theme.text,
        };
        let meaning_lines: Vec<Vec<Line>> = note
            .senses
            .iter()
            .map(|sense| {
                lines(
                    measure,
                    &styled(&sense.meaning, body),
                    columns.text_width,
                    meaning::MEANING_LINES as usize,
                )
            })
            .collect();
        let example_lines: Vec<Vec<Line>> = note
            .senses
            .iter()
            .map(|sense| {
                sense.example.as_deref().map_or_else(Vec::new, |example| {
                    lines(
                        measure,
                        &example_text(example, &note.word, painter),
                        columns.example_width,
                        meaning::EXAMPLE_LINES as usize,
                    )
                })
            })
            .collect();
        let senses = (0..note.senses.len())
            .map(|index| SenseLines {
                number: numbered.then(|| strings::sense_number(index + 1)),
                meaning_lines: meaning_lines[index].len(),
                example_lines: example_lines[index].len(),
            })
            .collect();
        let content = Content {
            word: &note.word,
            part_of_speech: note.part_of_speech.map(strings::part_of_speech),
            senses,
            others: &others,
            more: &strings::more,
        };
        let layout = card_layout::place(&content, width, placement, measure, theme);
        Self {
            width: layout.width,
            height: layout.height,
            meaning: meaning_lines,
            example: example_lines,
            layout,
        }
    }

    /// 見出しの行の縦の中心(rect は語の意味の場所)．選んでいる候補からつなぐ線はここへ引く
    pub fn header_mid_y(&self, rect: Frame) -> f32 {
        (rect.y + self.layout.header_mid_y()).round()
    }
}

/// つなぐ線の終わりの x．見出しのアイコンの手前で止める(rect は語の意味の場所)
pub(super) fn connector_end_x(rect: Frame, placement: Placement) -> f32 {
    rect.x + placement.left - tokens::size::space::XS
}

/// 一覧で候補の右に出す語の意味
pub(super) fn list_card(painter: &Painter, note: &HomophoneNote, placement: Placement) -> Card {
    Card::new(
        painter,
        note,
        note.others.clone(),
        meaning::LIST_WIDTH,
        placement,
    )
}

/// 分岐図で出す語の意味．同音語の札には，下の枝に出ていない語だけを出す(枝に出ている語は見れば分かる)
pub(super) fn branch_card(
    painter: &Painter,
    note: &HomophoneNote,
    column: &BranchColumn,
    width: f32,
    placement: Placement,
) -> Card {
    let others = note
        .others
        .iter()
        .filter(|word| !column.alternatives.contains(word))
        .cloned()
        .collect();
    Card::new(painter, note, others, width, placement)
}

/// 語の意味の置き方と中身．card が None なら，意味の無い候補を選んでいるあいだ空けておく場所
pub(super) struct Slot {
    pub placement: MeaningPlacement,
    pub card: Option<Card>,
    /// 目印の列の左の端と見出しの行の縦の真ん中
    pub position: Placement,
    /// 場所の大きさ(platinum と desk は下の余白を含む)
    pub width: f32,
    pub height: f32,
}

/// 候補の右に出す語の意味．意味が無くても，空けておく高さ(reserved)があれば空けた場所にする．
/// bottom は下に足す余白(platinum と desk)．出さなければ None
pub(super) fn side_slot(
    card: Option<Card>,
    width: f32,
    reserved: Option<f32>,
    position: Placement,
    bottom: f32,
) -> Option<Slot> {
    if card.is_none() && reserved.is_none() {
        return None;
    }
    let height = card
        .as_ref()
        .map_or(0.0, |card| card.height + bottom)
        .max(reserved.unwrap_or(0.0));
    Some(Slot {
        placement: MeaningPlacement::Side,
        card,
        position,
        width,
        height,
    })
}

/// 候補の下に出す語の意味．bottom は下に足す余白(platinum と desk)
pub(super) fn below_slot(card: Card, position: Placement, bottom: f32) -> Slot {
    Slot {
        placement: MeaningPlacement::Below,
        width: card.width,
        height: card.height + bottom,
        position,
        card: Some(card),
    }
}

/// 送られた置き方．意味が無ければ送られないので，候補の右とみなす(空けておくカードは候補の右だけ)
pub(super) fn placement(placement: Option<MeaningPlacement>) -> MeaningPlacement {
    placement.unwrap_or(MeaningPlacement::Side)
}

// MARK: - カードの場所の予約

#[derive(PartialEq)]
enum ReservationKey {
    /// 一覧の候補の並び
    List(Vec<String>),
    /// 分岐図で注目している文節の位置と，下の枝の候補
    Branch(usize, Vec<String>),
}

/// 候補の右に出したカードの場所(macOS の CandidateView・BranchView の reservedCard)．
/// 同じ候補の並び(分岐図は同じ文節の同じ枝)のあいだは，意味の無い候補(ひらがなの候補など)を選んでも場所を空けたままにし，
/// 窓の幅と高さを変えない(候補を移るたびに窓の縁が動かないように)．
/// 前の窓の状態が要るので描く層が持ち，窓を描くたびに list か branch で決めた高さを Look::reserved_card に渡す．
/// 候補の並びを覚えるので Debug を付けない(中身をログに出さない)
#[derive(Default)]
pub struct CardReservation {
    held: Option<(ReservationKey, f32)>,
}

impl CardReservation {
    /// 一覧を描く前に呼び，空けておくカードの高さを返す
    pub fn list(
        &mut self,
        list: &CandidateList,
        look: &Look,
        measure: &dyn Measure,
    ) -> Option<f32> {
        if placement(list.meaning_placement) != MeaningPlacement::Side {
            return self.clear();
        }
        let painter = Painter::new(look, measure);
        let (position, bottom) = super::list::side_position(look, measure);
        let height = list
            .homophone
            .as_ref()
            .map(|note| list_card(&painter, note, position).height + bottom);
        let key = ReservationKey::List(
            list.entries
                .iter()
                .map(|entry| entry.text.clone())
                .collect(),
        );
        self.hold(key, height)
    }

    /// 分岐図を描く前に呼び，空けておくカードの高さを返す
    pub fn branch(&mut self, map: &BranchMap, look: &Look, measure: &dyn Measure) -> Option<f32> {
        let Some((index, column)) = super::branch::focused(map) else {
            return self.clear();
        };
        if column.split.is_some() || placement(map.meaning_placement) != MeaningPlacement::Side {
            return self.clear();
        }
        let painter = Painter::new(look, measure);
        let height = column.homophone.as_ref().map(|note| {
            branch_card(
                &painter,
                note,
                column,
                meaning::BRANCH_WIDTH,
                super::branch::side_position(look, measure),
            )
            .height
        });
        self.hold(
            ReservationKey::Branch(index, column.alternatives.clone()),
            height,
        )
    }

    /// 候補の窓を消したとき
    pub fn clear(&mut self) -> Option<f32> {
        self.held = None;
        None
    }

    /// 同じ並びなら，今のカードと空けておいた場所の高い方を覚える．並びが変われば今のカードの高さから始める
    fn hold(&mut self, key: ReservationKey, height: Option<f32>) -> Option<f32> {
        self.held = match self.held.take() {
            Some((held, reserved)) if held == key => {
                Some((key, reserved.max(height.unwrap_or(0.0))))
            }
            _ => height.map(|height| (key, height)),
        };
        self.held.as_ref().map(|(_, height)| *height)
    }
}

// MARK: - 描く

/// 語の意味を rect(語の意味の場所)に描く．箱は描かない．card が None なら，見出しの辞書のアイコンだけを薄く出す(場所は空けたまま)
pub(super) fn draw(painter: &mut Painter, card: Option<&Card>, rect: Frame, position: Placement) {
    match card {
        Some(card) => content(painter, card, rect),
        None => {
            let theme = painter.theme;
            let center = Point::new(
                rect.x + position.left + meaning::MARKER_WIDTH / 2.0,
                rect.y + position.header_mid_y,
            );
            painter.icon(
                Icon::Book,
                Frame::square(center, meaning::ICON_SIZE),
                theme
                    .text_muted
                    .with_alpha(opacity::glass::MEANING_EMPTY_ICON),
            );
        }
    }
}

/// 選んでいる候補の行の右の端(start)から語の意味の見出し(end)へ引く線．端に丸を付ける．
/// 枝(branch_lines)と同じ形: 水平に出て，真ん中で枝と同じ半径の 4 分の 1 の円で曲がり，縦に進んでまた曲がり，水平に見出しへ入る．
/// 直線の枝のテーマは直角に曲がる．高さの差が小さければ半径を縮める(macOS の MeaningCardDrawing.drawConnector)
pub(super) fn connector(painter: &mut Painter, start: Point, end: Point) {
    let theme = painter.theme;
    let middle = ((start.x + end.x) / 2.0).round();
    let rise = end.y - start.y;
    let turn = if theme.curved_branches() {
        glass::BRANCH_TURN_RADIUS
    } else {
        0.0
    };
    let radius = turn
        .min(rise.abs() / 2.0)
        .min(middle - start.x)
        .min(end.x - middle)
        .max(0.0);
    let direction = if rise < 0.0 { -1.0 } else { 1.0 };
    let segments = if rise == 0.0 {
        vec![Segment::Line(end)]
    } else {
        vec![
            Segment::Line(Point::new(middle - radius, start.y)),
            // 下へ曲がるときは時計回り，上へ曲がるときは反時計回り(y が下へ増える画面で見た向き)
            Segment::Arc {
                to: Point::new(middle, start.y + direction * radius),
                radius,
                clockwise: direction > 0.0,
            },
            Segment::Line(Point::new(middle, end.y - direction * radius)),
            Segment::Arc {
                to: Point::new(middle + radius, end.y),
                radius,
                clockwise: direction < 0.0,
            },
            Segment::Line(end),
        ]
    };
    painter.draws.push(Draw::Path {
        figures: vec![Figure { start, segments }],
        color: theme.selection,
        width: if theme.is_rounded() {
            glass::LINE_WIDTH_SELECTED
        } else {
            branch::LINE_WIDTH_SELECTED
        },
    });
    painter.draws.push(Draw::Ellipse {
        frame: Frame::square(end, meaning::DOT_SIZE),
        color: theme.selection,
    });
}

// MARK: - 中身

/// rect(語の意味の場所．箱は描かない)の中に，配置のとおりに見出し・意味・例・同音語を描く
fn content(painter: &mut Painter, card: &Card, rect: Frame) {
    let theme = painter.theme;
    let layout = &card.layout;
    let at = |frame: Frame| frame.offset(rect.x, rect.y);
    // アクセントの色(青)は使わない．アイコン・番号・品詞は控えめな色で，番号は枠線だけの丸，品詞は枠線だけの札にする
    // (地を塗らないので，控えめな色の字でも地との差が保てる)．同音語の札は，パレットの説明の札と同じく
    // 文字の色を薄く敷いた地に文字の色の字．札の形は 1 種類(角の丸み part.tag-radius)
    let (mark, bar_color) = (theme.text_muted, theme.line);
    let tag_radius = if theme.is_rounded() {
        tokens::size::part::TAG_RADIUS
    } else {
        0.0
    };

    // 見出し
    painter.icon(Icon::Book, icon_frame(at(layout.book_icon)), mark);
    let headword = &layout.headword;
    painter.text(
        &headword.text,
        headword.font,
        theme.text,
        rect.x + headword.place.line.x,
        at(headword.place.line),
    );
    if let Some(chip) = &layout.part_of_speech {
        // 品詞の札
        let frame = at(chip.frame);
        painter.draws.push(Draw::RoundRect {
            frame: frame.inset(0.5, 0.5),
            radius: tag_radius,
            fill: None,
            stroke: Some((theme.line, tokens::size::part::STROKE)),
        });
        painter.text(
            &chip.text,
            Font::MeaningTag,
            mark,
            rect.x + chip.text_place.line.x,
            at(chip.text_place.line),
        );
    }

    // 意味と例
    for (index, sense) in layout.senses.iter().enumerate() {
        if let (Some(badge), Some(number)) = (sense.badge, &sense.number) {
            // 番号は枠線だけの丸(候補の番号の塗った丸と形を変え，番号キーで選ぶものと見分ける)
            let badge = at(badge);
            painter.draws.push(Draw::RoundRect {
                frame: badge.inset(0.5, 0.5),
                radius: if theme.is_rounded() {
                    badge.width / 2.0 - 0.5
                } else {
                    0.0
                },
                fill: None,
                stroke: Some((theme.line, tokens::size::part::STROKE)),
            });
            painter.text(
                &number.text,
                number.font,
                mark,
                rect.x + number.place.line.x,
                at(number.place.line),
            );
        }
        for (place, line) in sense.meaning.iter().zip(&card.meaning[index]) {
            draw_line(painter, line, at(place.line));
        }
        if let Some(bar) = sense.example_bar {
            let bar = at(bar);
            painter.draws.push(Draw::RoundRect {
                frame: bar,
                radius: bar.width / 2.0,
                fill: Some(bar_color),
                stroke: None,
            });
        }
        for (place, line) in sense.example.iter().zip(&card.example[index]) {
            draw_line(painter, line, at(place.line));
        }
    }

    // 同音語
    let Some(separator) = layout.separator else {
        return;
    };
    painter.rect(at(separator), theme.line);
    if let Some(ear) = layout.ear_icon {
        painter.icon(Icon::Ear, icon_frame(at(ear)), theme.text_muted);
    }
    for tag in &layout.tags {
        let frame = at(tag.frame);
        painter.draws.push(Draw::RoundRect {
            frame,
            radius: tag_radius,
            fill: Some(theme.badge),
            stroke: None,
        });
        painter.text(
            &tag.text,
            Font::Label,
            theme.text,
            rect.x + tag.text_place.line.x,
            at(tag.text_place.line),
        );
    }
    if let Some(more) = &layout.more {
        painter.text(
            &more.text,
            more.font,
            theme.text_muted,
            rect.x + more.place.line.x,
            at(more.place.line),
        );
    }
}

/// 目印の枠(目印の列の一辺の正方形)の真ん中に置くアイコンの枠
fn icon_frame(marker: Frame) -> Frame {
    Frame::square(
        Point::new(marker.mid_x(), marker.mid_y()),
        meaning::ICON_SIZE,
    )
}

/// 1 行を行の箱 frame の左から描く．書体の変わり目で字の間が空かないよう，次の字の位置は切り上げない幅で進める
fn draw_line(painter: &mut Painter, line: &Line, frame: Frame) {
    let mut x = frame.x;
    for run in &line.runs {
        painter.text(&run.text, run.style.font, run.style.color, x, frame);
        x += painter.measure.width(&run.text, run.style.font);
    }
}

// MARK: - 文字

fn styled(text: &str, style: Style) -> Vec<(char, Style)> {
    text.chars().map(|character| (character, style)).collect()
}

/// 使い方の例．控えめな色で書き，例の中の見出しの語(活用した形は漢字の部分と送り仮名の長さまで)を文字の色の太字にする
fn example_text(example: &str, word: &str, painter: &Painter) -> Vec<(char, Style)> {
    let theme = painter.theme;
    let plain = Style {
        font: Font::MeaningExample,
        color: theme.text_muted,
    };
    let strong = Style {
        font: Font::MeaningExampleStrong,
        color: theme.text,
    };
    let range = highlight_range(word, example);
    example
        .chars()
        .enumerate()
        .map(|(index, character)| {
            let inside = range.as_ref().is_some_and(|range| range.contains(&index));
            (character, if inside { strong } else { plain })
        })
        .collect()
}

/// 例の中で見出しの語に当たる範囲(字の位置)．語がそのまま無ければ，漢字の部分と続くひらがなを送り仮名の長さまで．
/// 見つからなければ None
fn highlight_range(word: &str, example: &str) -> Option<Range<usize>> {
    let example: Vec<char> = example.chars().collect();
    let word: Vec<char> = word.chars().collect();
    if let Some(start) = find(&example, &word) {
        return Some(start..start + word.len());
    }
    let stem: Vec<char> = word
        .iter()
        .copied()
        .take_while(|character| !is_hiragana(*character))
        .collect();
    if stem.is_empty() || stem.len() == word.len() {
        return None;
    }
    let start = find(&example, &stem)?;
    let okurigana = word.len() - stem.len();
    let tail = example[start + stem.len()..]
        .iter()
        .take(okurigana)
        .take_while(|character| is_hiragana(**character))
        .count();
    Some(start..start + stem.len() + tail)
}

fn find(text: &[char], wanted: &[char]) -> Option<usize> {
    if wanted.is_empty() || wanted.len() > text.len() {
        return None;
    }
    text.windows(wanted.len())
        .position(|window| window == wanted)
}

fn is_hiragana(character: char) -> bool {
    ('\u{3041}'..='\u{309F}').contains(&character)
}

fn is_line_start_forbidden(character: char) -> bool {
    LINE_START_FORBIDDEN.contains(character)
}

/// 英数字の語の字か(語の途中では折り返さない)
fn is_word_character(character: char) -> bool {
    character.is_ascii_alphanumeric()
}

/// 同じ書体と色の字をまとめる
fn runs(characters: &[(char, Style)]) -> Vec<Run> {
    let mut runs: Vec<Run> = Vec::new();
    for &(character, style) in characters {
        match runs.last_mut() {
            Some(run) if run.style == style => run.text.push(character),
            _ => runs.push(Run {
                text: character.to_string(),
                style,
            }),
        }
    }
    runs
}

fn width(measure: &dyn Measure, characters: &[(char, Style)]) -> f32 {
    runs(characters)
        .iter()
        .map(|run| measure.width(&run.text, run.style.font))
        .sum()
}

/// 幅 width で折り返した行
fn lines(
    measure: &dyn Measure,
    characters: &[(char, Style)],
    width: f32,
    max_lines: usize,
) -> Vec<Line> {
    wrap(measure, characters, width, max_lines)
        .into_iter()
        .map(|runs| Line { runs })
        .collect()
}

/// 幅で貪欲に折り返す．行の頭に置かない字は前の行に付け，英数字の語は途中で切らない．
/// max_lines を超える分は，最後の行の末尾を「…」にして省く
fn wrap(
    measure: &dyn Measure,
    characters: &[(char, Style)],
    width: f32,
    max_lines: usize,
) -> Vec<Vec<Run>> {
    if characters.is_empty() || width <= 0.0 || max_lines == 0 {
        return Vec::new();
    }
    let mut lines = Vec::new();
    let mut start = 0;
    // 前の行の頭(1 字だけの最後の行を作らないように，前の行を詰め直すのに使う)
    let mut previous: Option<usize> = None;
    while start < characters.len() {
        let mut end = fitting_end(measure, characters, start, width);
        if end < characters.len()
            && is_word_character(characters[end - 1].0)
            && is_word_character(characters[end].0)
        {
            // 語の頭から次の行にする．語が 1 行に入らなければ途中で切る
            let word_start = (start..end)
                .rev()
                .find(|&index| !is_word_character(characters[index].0))
                .map_or(start, |index| index + 1);
            if word_start > start {
                end = word_start;
            }
        }
        while end < characters.len() && is_line_start_forbidden(characters[end].0) {
            end += 1;
        }
        if lines.len() + 1 == max_lines && end < characters.len() {
            lines.push(truncated(measure, &characters[start..], width));
            break;
        }
        // 最後の行が 1 字だけになるときは，前の行の最後の字も送る(1 字だけの行を作らない)．
        // 送る字を行の頭に置けないときと，前の行が短いときは送らない
        if end == characters.len() && end - start == 1 && start >= 3 {
            let moved = start - 1;
            let previous_start = previous.unwrap_or(0);
            if moved - previous_start >= 2 && !is_line_start_forbidden(characters[moved].0) {
                if let Some(last) = lines.last_mut() {
                    *last = runs(&characters[previous_start..moved]);
                    start = moved;
                }
            }
        }
        lines.push(runs(&characters[start..end]));
        previous = Some(start);
        start = end;
    }
    lines
}

/// start からいくつ先の字まで width に入るか(少なくとも 1 字)．並べた幅は字数とともに増えるので二分探索で決める
fn fitting_end(
    measure: &dyn Measure,
    characters: &[(char, Style)],
    start: usize,
    limit: f32,
) -> usize {
    let (mut low, mut high) = (start + 1, characters.len());
    if width(measure, &characters[start..high]) <= limit {
        return high;
    }
    // characters[start..low] は入る(1 字目は入らなくても置く)．characters[start..high] は入らない
    while high - low > 1 {
        let middle = (low + high) / 2;
        if width(measure, &characters[start..middle]) <= limit {
            low = middle;
        } else {
            high = middle;
        }
    }
    low
}

/// 末尾を「…」にして width に収めた 1 行
fn truncated(measure: &dyn Measure, characters: &[(char, Style)], limit: f32) -> Vec<Run> {
    if width(measure, characters) <= limit {
        return runs(characters);
    }
    let with_ellipsis = |count: usize| {
        let style = characters[count.saturating_sub(1)].1;
        let mut line = characters[..count].to_vec();
        line.push((ELLIPSIS, style));
        line
    };
    // with_ellipsis(low) は入る(0 字なら入らなくても「…」だけにする)．with_ellipsis(high) は入らない
    let (mut low, mut high) = (0, characters.len());
    while high - low > 1 {
        let middle = (low + high) / 2;
        if width(measure, &with_ellipsis(middle)) <= limit {
            low = middle;
        } else {
            high = middle;
        }
    }
    runs(&with_ellipsis(low))
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::*;
    use ipc::HomophoneSense;
    use tokens::size::candidate;

    /// 候補の右に置くとき(目印の列は場所の左の端，見出しの行は候補の 1 行目の地 24 の真ん中)
    const P: Placement = Placement {
        left: 0.0,
        header_mid_y: 12.0,
    };

    fn painter<'a>(look: &Look<'a>) -> Painter<'a> {
        Painter::new(look, &Fixed)
    }

    fn plain() -> Style {
        Style {
            font: Font::MeaningBody,
            color: Color::CLEAR,
        }
    }

    /// 折り返した行の文字(Fixed は 1 字 10 ドット)
    fn wrapped(text: &str, width: f32, max_lines: usize) -> Vec<String> {
        wrap(&Fixed, &styled(text, plain()), width, max_lines)
            .into_iter()
            .map(|runs| runs.into_iter().map(|run| run.text).collect())
            .collect()
    }

    fn note(senses: &[(&str, Option<&str>)], others: &[&str]) -> HomophoneNote {
        HomophoneNote {
            word: "撮る".into(),
            part_of_speech: Some(ipc::PartOfSpeech::Verb),
            senses: senses
                .iter()
                .map(|(meaning, example)| HomophoneSense {
                    meaning: (*meaning).into(),
                    example: example.map(Into::into),
                })
                .collect(),
            others: others.iter().map(|word| (*word).to_string()).collect(),
        }
    }

    #[test]
    fn 幅で貪欲に折り返す() {
        assert_eq!(
            wrapped("あいうえおかきくけこ", 40.0, 5),
            ["あいうえ", "おかきく", "けこ"]
        );
        assert_eq!(wrapped("あいう", 40.0, 5), ["あいう"]);
        // 1 字も入らない幅でも 1 字は置く
        assert_eq!(wrapped("あい", 5.0, 5), ["あ", "い"]);
        assert!(wrapped("", 40.0, 3).is_empty());
    }

    #[test]
    fn 句読点や小さいかなは行の頭に置かず前の行に付ける() {
        assert_eq!(
            wrapped("あいうえ。おかき", 40.0, 5),
            ["あいうえ。", "おかき"]
        );
        assert_eq!(
            wrapped("あいうえっ」かき", 40.0, 5),
            ["あいうえっ」", "かき"]
        );
        assert_eq!(wrapped("あいうえーお", 40.0, 5), ["あいうえー", "お"]);
        // 行の途中の句読点はそのまま
        assert_eq!(wrapped("あい、うえおか", 40.0, 5), ["あい、う", "えおか"]);
    }

    #[test]
    fn 最後の行を1字だけにしない() {
        // 4 字の行のあとに 1 字だけ残るときは，前の行の最後の字も送る
        assert_eq!(wrapped("あいうえお", 40.0, 5), ["あいう", "えお"]);
        // 送る字を行の頭に置けないときは送らない
        assert_eq!(wrapped("あいう。お", 40.0, 5), ["あいう。", "お"]);
    }

    #[test]
    fn 英数字の語は途中で切らない() {
        assert_eq!(wrapped("あいword", 40.0, 5), ["あい", "word"]);
        // 1 行に入らない語は途中で切る
        assert_eq!(wrapped("abcdefgh", 40.0, 5), ["abcd", "efgh"]);
    }

    #[test]
    fn 行数の上限を超える分は最後の行を省く() {
        assert_eq!(
            wrapped("あいうえおかきくけこさしすせそ", 40.0, 2),
            ["あいうえ", "おかき…"]
        );
        // ちょうど収まるなら省かない
        assert_eq!(
            wrapped("あいうえおかきく", 40.0, 2),
            ["あいうえ", "おかきく"]
        );
    }

    #[test]
    fn 例の中の見出しの語を強める() {
        assert_eq!(highlight_range("撮る", "写真を撮る"), Some(3..5));
        // 活用した形は漢字の部分と送り仮名の長さまで
        assert_eq!(highlight_range("撮る", "記念写真を撮った"), Some(5..7));
        assert_eq!(highlight_range("動く", "時計が動き始める"), Some(3..5));
        // 送り仮名が無い語は，そのまま無ければ強めない
        assert_eq!(highlight_range("清算", "運賃を精算する"), None);
        assert_eq!(highlight_range("撮る", "写真を写す"), None);
        assert_eq!(highlight_range("", "写真"), None);

        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let styles = runs(&example_text("記念写真を撮った", "撮る", &painter(&look)));
        let texts: Vec<(&str, Font)> = styles
            .iter()
            .map(|run| (run.text.as_str(), run.style.font))
            .collect();
        assert_eq!(
            texts,
            [
                ("記念写真を", Font::MeaningExample),
                ("撮っ", Font::MeaningExampleStrong),
                ("た", Font::MeaningExample)
            ]
        );
        assert_eq!(styles[1].style.color, theme.text);
        assert_eq!(styles[0].style.color, theme.text_muted);
    }

    #[test]
    fn 意味は3行_例は2行を超える分を省く() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let long = "意".repeat(200);
        let card = list_card(
            &painter(&look),
            &note(&[(long.as_str(), Some(long.as_str()))], &[]),
            P,
        );
        assert_eq!(card.meaning[0].len(), meaning::MEANING_LINES as usize);
        assert_eq!(card.example[0].len(), meaning::EXAMPLE_LINES as usize);
        let last = |lines: &[Line]| -> String {
            lines
                .last()
                .map(|line| line.runs.iter().map(|run| run.text.as_str()).collect())
                .unwrap_or_default()
        };
        assert!(last(&card.meaning[0]).ends_with(ELLIPSIS));
        assert!(last(&card.example[0]).ends_with(ELLIPSIS));
        // 意味が 1 つなら番号を付けない
        assert_eq!(card.layout.senses[0].number, None);
    }

    #[test]
    fn 意味が2つ以上なら目印の列に番号を付け_文字の幅は変えない() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let text = "意".repeat(26);
        let one = list_card(&painter(&look), &note(&[(text.as_str(), None)], &[]), P);
        let two = list_card(
            &painter(&look),
            &note(&[(text.as_str(), None), ("働く", None)], &[]),
            P,
        );
        // 番号は目印の列に置くので，意味の文の幅は番号があっても同じ
        assert_eq!(one.meaning[0].len(), two.meaning[0].len());
        assert_eq!(
            two.layout.senses[0]
                .number
                .as_ref()
                .map(|number| number.text.as_str()),
            Some("1")
        );
        assert_eq!(
            two.layout.senses[1]
                .number
                .as_ref()
                .map(|number| number.text.as_str()),
            Some("2")
        );
        assert_eq!(one.width, meaning::LIST_WIDTH);
    }

    #[test]
    fn 同音語の行は区切りの線の下に並べ_入らない札は数にまとめる() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let few = list_card(
            &painter(&look),
            &note(&[("撮影する", None)], &["取る", "採る"]),
            P,
        );
        let none = list_card(&painter(&look), &note(&[("撮影する", None)], &[]), P);
        assert_eq!(
            few.height - none.height,
            meaning::OTHERS_GAP * 2.0
                + candidate::FRAME_WIDTH
                + glass::TAG_HEIGHT.max(meaning::MARKER_WIDTH)
        );
        let mut drawn = painter(&look);
        draw(
            &mut drawn,
            Some(&few),
            Frame::new(0.0, 0.0, few.width, few.height),
            P,
        );
        let shown: Vec<String> = drawn
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Text { text, .. } => Some(text.clone()),
                _ => None,
            })
            .collect();
        for text in ["撮る", "動詞", "撮影する", "取る", "採る"] {
            assert!(shown.contains(&text.to_string()), "{text}");
        }
        // 同音語は耳のアイコンと札だけで並べ，見出しの言葉は置かない
        assert!(!shown.contains(&"同音語".to_string()));
        assert!(drawn.draws.iter().any(|draw| matches!(
            draw,
            Draw::Icon {
                icon: Icon::Ear,
                ..
            }
        )));

        let many: Vec<String> = (0..30).map(|index| format!("語{index}")).collect();
        let many: Vec<&str> = many.iter().map(String::as_str).collect();
        let crowded = list_card(&painter(&look), &note(&[("撮影する", None)], &many), P);
        let mut drawn = painter(&look);
        let rect = Frame::new(0.0, 0.0, crowded.width, crowded.height);
        draw(&mut drawn, Some(&crowded), rect, P);
        assert!(drawn
            .draws
            .iter()
            .any(|draw| matches!(draw, Draw::Text { text, .. } if text.starts_with('+'))));
        for draw in &drawn.draws {
            if let Draw::Text { frame, .. } = draw {
                assert!(frame.max_x() <= rect.max_x(), "{draw:?}");
            }
        }
    }

    #[test]
    fn 分岐図のカードの同音語は枝に出ていない語だけ() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let column = BranchColumn {
            alternatives: vec!["取る".into(), "撮る".into(), "とる".into()],
            ..super::super::sample::column("撮る")
        };
        let card = branch_card(
            &painter(&look),
            &note(&[("撮影する", None)], &["取る", "採る", "執る"]),
            &column,
            meaning::BRANCH_WIDTH,
            P,
        );
        let tags: Vec<&str> = card
            .layout
            .tags
            .iter()
            .map(|tag| tag.text.as_str())
            .collect();
        assert_eq!(tags, ["採る", "執る"]);
    }

    #[test]
    fn 空けておく場所は見出しの辞書のアイコンだけを薄く出す() {
        for name in ["washi", "platinum"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut drawn = painter(&look);
            draw(&mut drawn, None, Frame::new(0.0, 0.0, 300.0, 120.0), P);
            assert!(!drawn
                .draws
                .iter()
                .any(|draw| matches!(draw, Draw::Text { .. })));
            let icon = drawn.draws.iter().find_map(|draw| match draw {
                Draw::Icon {
                    icon: Icon::Book,
                    frame,
                    color,
                    ..
                } if color.alpha == opacity::glass::MEANING_EMPTY_ICON => Some(*frame),
                _ => None,
            });
            // 見出しのアイコンと同じ場所(目印の列の真ん中，見出しの行の高さ)
            let icon = icon.expect("薄いアイコン");
            assert_eq!(icon.mid_x(), P.left + meaning::MARKER_WIDTH / 2.0, "{name}");
            assert_eq!(icon.mid_y(), P.header_mid_y, "{name}");
            // 箱も三角も描かない
            assert!(!drawn.draws.iter().any(|draw| matches!(
                draw,
                Draw::Polygon { .. } | Draw::RoundRect { .. } | Draw::Rect { .. }
            )));
        }
    }

    /// つないだ線の図形と，その中の円弧の半径と向き
    fn connector_path(
        name: &str,
        start: Point,
        end: Point,
    ) -> (Figure, Vec<(f32, bool)>, Vec<Draw>) {
        let theme = theme(name);
        let mut drawn = painter(&Look::new(&theme, 15.0));
        connector(&mut drawn, start, end);
        let figure = drawn
            .draws
            .iter()
            .find_map(|draw| match draw {
                Draw::Path { figures, color, .. } if *color == theme.selection => {
                    Some(figures[0].clone())
                }
                _ => None,
            })
            .expect("線");
        let arcs = figure
            .segments
            .iter()
            .filter_map(|segment| match segment {
                Segment::Arc {
                    radius, clockwise, ..
                } => Some((*radius, *clockwise)),
                Segment::Line(_) => None,
            })
            .collect();
        (figure, arcs, drawn.draws)
    }

    #[test]
    fn つなぐ線は枝と同じ半径の曲がり角で曲がり_直線の枝のテーマは直角() {
        let start = Point::new(100.0, 50.0);
        let down = Point::new(140.0, 90.0);
        let up = Point::new(140.0, 20.0);
        // 下へ: 時計回りに曲がって下り，反時計回りに曲がって見出しへ入る
        let (figure, arcs, draws) = connector_path("washi", start, down);
        assert_eq!(figure.start, start);
        assert_eq!(figure.segments.last(), Some(&Segment::Line(down)));
        assert_eq!(
            arcs,
            vec![
                (glass::BRANCH_TURN_RADIUS, true),
                (glass::BRANCH_TURN_RADIUS, false)
            ]
        );
        assert!(
            matches!(draws.last(), Some(Draw::Ellipse { frame, .. }) if frame.mid_x() == down.x && frame.mid_y() == down.y)
        );
        // 上へ: 向きが逆
        let (_, arcs, _) = connector_path("washi", start, up);
        assert_eq!(
            arcs,
            vec![
                (glass::BRANCH_TURN_RADIUS, false),
                (glass::BRANCH_TURN_RADIUS, true)
            ]
        );
        // 高さの差が半径の 2 倍より小さければ半径を縮める
        let (_, arcs, _) = connector_path("washi", start, Point::new(140.0, 56.0));
        assert!(arcs.iter().all(|(radius, _)| *radius == 3.0));
        // 同じ高さなら 1 本の水平の線
        let (figure, arcs, _) = connector_path("washi", start, Point::new(140.0, 50.0));
        assert!(arcs.is_empty());
        assert_eq!(figure.segments.len(), 1);
        // 直線の枝のテーマは直角(半径 0)
        for name in ["platinum", "automatic"] {
            let (_, arcs, draws) = connector_path(name, start, down);
            assert!(arcs.iter().all(|(radius, _)| *radius == 0.0), "{name}");
            assert!(
                !draws.iter().any(|draw| matches!(draw, Draw::Curve { .. })),
                "{name}"
            );
        }
    }

    fn list(entries: &[&str], homophone: Option<HomophoneNote>) -> CandidateList {
        CandidateList {
            association: None,
            association_hint: None,
            association_key: None,
            hints: None,
            meaning_placement: homophone.as_ref().map(|_| MeaningPlacement::Side),
            column_length: None,
            homophone,
            shows_numbers: None,
            variants: vec![],
            selected_variant: None,
            entries: entries
                .iter()
                .map(|text| ipc::CandidateEntry {
                    text: (*text).into(),
                    annotation: None,
                    corrected_start: None,
                    corrected_length: None,
                    command: None,
                    has_comment: None,
                    detail: None,
                })
                .collect(),
            selected_entry: Some(0),
            focus: ipc::CandidateFocus::Candidate,
            position: 1,
            total: 3,
            note: None,
        }
    }

    #[test]
    fn 同じ候補の並びのあいだはカードの場所を空けたままにする() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let mut reservation = CardReservation::default();
        let short = note(&[("撮影する", None)], &[]);
        let tall = note(
            &[("撮影する", Some("写真を撮る")), ("映画を撮る", None)],
            &["取る"],
        );
        let entries = ["撮る", "とる", "トル"];
        let first = reservation.list(&list(&entries, Some(short.clone())), &look, &Fixed);
        let position = super::super::list::side_position(&look, &Fixed).0;
        let height = list_card(&painter(&look), &short, position).height;
        assert_eq!(first, Some(height));
        // 意味の無い候補に移っても，同じ並びなら空けたまま
        assert_eq!(
            reservation.list(&list(&entries, None), &look, &Fixed),
            Some(height)
        );
        // 高いカードを出したら，その高さを空けておく
        let taller = list_card(&painter(&look), &tall, position).height;
        assert!(taller > height);
        assert_eq!(
            reservation.list(&list(&entries, Some(tall)), &look, &Fixed),
            Some(taller)
        );
        assert_eq!(
            reservation.list(&list(&entries, Some(short.clone())), &look, &Fixed),
            Some(taller)
        );
        // 並びが変われば空けない
        assert_eq!(
            reservation.list(&list(&["取る", "とる"], None), &look, &Fixed),
            None
        );
        // 候補の下に出す設定では空けない
        let mut below = list(&entries, Some(short));
        below.meaning_placement = Some(MeaningPlacement::Below);
        assert_eq!(reservation.list(&below, &look, &Fixed), None);
        assert_eq!(reservation.list(&list(&entries, None), &look, &Fixed), None);
    }

    #[test]
    fn 分岐図では同じ文節の同じ枝のあいだカードの場所を空けたままにする() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let mut reservation = CardReservation::default();
        let mut map = super::super::sample::branch();
        let focused = map.columns.len() - 1;
        map.columns[focused].homophone = Some(note(&[("撮影する", None)], &[]));
        map.meaning_placement = Some(MeaningPlacement::Side);
        let height = reservation.branch(&map, &look, &Fixed);
        assert!(height.is_some());
        let mut moved = map.clone();
        moved.columns[focused].homophone = None;
        moved.columns[focused].selected_alternative = Some(2);
        moved.meaning_placement = None;
        assert_eq!(reservation.branch(&moved, &look, &Fixed), height);
        // 注目している文節が変われば空けない
        let mut other = moved.clone();
        other.columns[focused].is_focused = false;
        other.columns[0].is_focused = true;
        assert_eq!(reservation.branch(&other, &look, &Fixed), None);
        // 区切っているあいだも空けない
        assert!(reservation.branch(&map, &look, &Fixed).is_some());
        let mut split = moved;
        split.columns[focused].split = Some(ipc::BranchSplit {
            pieces: vec!["中野".into(), "です".into()],
        });
        assert_eq!(reservation.branch(&split, &look, &Fixed), None);
    }
}
