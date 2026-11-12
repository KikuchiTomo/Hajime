#![forbid(unsafe_code)]

//! 語の意味のカード(R-08．macOS の MeaningCardDrawing)．一覧(list)と分岐図(branch)で同じものを使う．
//!
//! 上から順に，見出し(辞書のアイコン・語・品詞の札)，意味，使い方の例，同音語を並べる．
//! - 意味が 2 つ以上なら，頭に角丸の四角の番号を付ける(候補の番号の丸と形を変え，番号キーで選ぶものと見分ける)
//! - 意味と例はカードの幅で折り返す(行の頭に句読点や小さいかなを置かない)．行数の上限を超える分は「…」で省く
//! - 使い方の例は左に縦の線を引いて控えめな色で出し，例の中の見出しの語だけを強める
//! - 同音語は区切りの線の下に，耳のアイコンと札で並べる．入らない札は「+n」にまとめる
//!
//! 候補の右に出すときは，一覧では選んでいる候補を指す三角を左の辺に付け，分岐図では選んでいる候補からカードへ線を引く

use super::paint::{Painter, TagStyle};
use super::{Draw, Frame, Look, Measure, Point};
use crate::keys::Icon;
use crate::strings;
use crate::theme::{Color, Font};
use ipc::{BranchColumn, BranchMap, CandidateList, HomophoneNote, MeaningPlacement};
use std::ops::Range;
use tokens::opacity;
use tokens::size::{branch, candidate, glass};

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
    height: f32,
}

/// 1 つの意味の行
struct Sense {
    number: Option<String>,
    meaning: Vec<Line>,
    example: Vec<Line>,
    height: f32,
}

/// 描く位置を決めたカード．width・height は内側の余白を含む
pub(super) struct Card {
    word: String,
    part_of_speech: Option<&'static str>,
    /// 同音語の札に出す語(分岐図では枝に出ている語を除いたもの)
    others: Vec<String>,
    header_height: f32,
    senses: Vec<Sense>,
    pub width: f32,
    pub height: f32,
}

impl Card {
    /// 文字を並べる幅(余白を除く)が width のカード
    pub fn new(painter: &Painter, note: &HomophoneNote, others: Vec<String>, width: f32) -> Self {
        let theme = painter.theme;
        let measure = painter.measure;
        let numbered = note.senses.len() > 1;
        let text_width = width
            - if numbered {
                glass::MEANING_BADGE_SIZE + glass::NOTE_GAP
            } else {
                0.0
            };
        let example_width =
            text_width - glass::MEANING_EXAMPLE_BAR_WIDTH - glass::MEANING_EXAMPLE_INDENT;
        let body = Style {
            font: Font::MeaningBody,
            color: theme.text,
        };
        let senses: Vec<Sense> = note
            .senses
            .iter()
            .enumerate()
            .map(|(index, sense)| {
                let meaning = lines(
                    measure,
                    &styled(&sense.meaning, body),
                    text_width,
                    glass::MEANING_MEANING_LINES as usize,
                );
                let example = sense.example.as_deref().map_or_else(Vec::new, |example| {
                    lines(
                        measure,
                        &example_text(example, &note.word, painter),
                        example_width,
                        glass::MEANING_EXAMPLE_LINES as usize,
                    )
                });
                let height = lines_height(&meaning)
                    + if example.is_empty() {
                        0.0
                    } else {
                        glass::MEANING_EXAMPLE_GAP + lines_height(&example)
                    };
                Sense {
                    number: numbered.then(|| strings::sense_number(index + 1)),
                    meaning,
                    example,
                    height,
                }
            })
            .collect();
        let header_height = measure
            .height(Font::MeaningHeadword)
            .ceil()
            .max(glass::MEANING_POS_HEIGHT);
        let others_height = if others.is_empty() {
            0.0
        } else {
            glass::MEANING_OTHERS_GAP * 2.0 + candidate::FRAME_WIDTH + glass::TAG_HEIGHT
        };
        let senses_height = senses.iter().map(|sense| sense.height).sum::<f32>()
            + glass::MEANING_SENSE_GAP * senses.len().saturating_sub(1) as f32;
        let height = glass::MEANING_PADDING * 2.0
            + header_height
            + glass::MEANING_HEADER_GAP
            + senses_height
            + others_height;
        Self {
            word: note.word.clone(),
            part_of_speech: note.part_of_speech.map(strings::part_of_speech),
            others,
            header_height,
            senses,
            width: width + glass::MEANING_PADDING * 2.0,
            height: height.ceil(),
        }
    }

    /// 見出しの行の縦の中心(rect はカードの枠)．分岐図のつなぐ線はここへ引く
    pub fn header_mid_y(&self, rect: Frame) -> f32 {
        (rect.y + glass::MEANING_PADDING + self.header_height / 2.0).round()
    }
}

/// 一覧で出すカード(候補の右に出すときの幅)
pub(super) fn list_card(painter: &Painter, note: &HomophoneNote) -> Card {
    Card::new(
        painter,
        note,
        note.others.clone(),
        glass::MEANING_CARD_WIDTH,
    )
}

/// 分岐図で出すカード．同音語の札には，下の枝に出ていない語だけを出す(枝に出ている語は見れば分かる)
pub(super) fn branch_card(
    painter: &Painter,
    note: &HomophoneNote,
    column: &BranchColumn,
    width: f32,
) -> Card {
    let others = note
        .others
        .iter()
        .filter(|word| !column.alternatives.contains(word))
        .cloned()
        .collect();
    Card::new(painter, note, others, width)
}

/// 語の意味のカードの置き方と中身．card が None なら，意味の無い候補を選んでいるあいだ空けておくカード
pub(super) struct Slot {
    pub placement: MeaningPlacement,
    pub card: Option<Card>,
    /// カードの大きさ(内側の余白を含む．一覧の候補の右では窓の縁から離す空きも含む)
    pub width: f32,
    pub height: f32,
}

/// 候補の右に出すカード．意味が無くても，空けておく高さ(reserved)があれば空いたカードにする．
/// 出さなければ None
pub(super) fn side_slot(card: Option<Card>, width: f32, reserved: Option<f32>) -> Option<Slot> {
    if card.is_none() && reserved.is_none() {
        return None;
    }
    let height = card
        .as_ref()
        .map_or(0.0, |card| card.height)
        .max(reserved.unwrap_or(0.0));
    Some(Slot {
        placement: MeaningPlacement::Side,
        card,
        width: width + glass::MEANING_PADDING * 2.0,
        height,
    })
}

/// 候補の下に出すカード
pub(super) fn below_slot(card: Card) -> Slot {
    Slot {
        placement: MeaningPlacement::Below,
        width: card.width,
        height: card.height,
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
        let height = list
            .homophone
            .as_ref()
            .map(|note| list_card(&painter, note).height);
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
        let height = column
            .homophone
            .as_ref()
            .map(|note| branch_card(&painter, note, column, glass::MEANING_BRANCH_WIDTH).height);
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

// MARK: - 地

/// カードを描く．card が None なら空けておくカード．pointer_y があれば，左の辺からその高さを指す三角を出す(一覧で選んでいる候補を指す)
pub(super) fn draw(
    painter: &mut Painter,
    card: Option<&Card>,
    rect: Frame,
    pointer_y: Option<f32>,
) {
    background(painter, rect, pointer_y);
    match card {
        Some(card) => content(painter, card, rect),
        None => {
            // 意味の無い候補を選んでいるときは，地の真ん中に辞書のアイコンを薄く出す(カードの場所は動かさない)
            let theme = painter.theme;
            let side = glass::MEANING_EMPTY_ICON_SIZE;
            let frame = Frame::new(
                (rect.mid_x() - side / 2.0).round(),
                (rect.mid_y() - side / 2.0).round(),
                side,
                side,
            );
            painter.icon(
                Icon::Book,
                frame,
                theme
                    .text_muted
                    .with_alpha(opacity::glass::MEANING_EMPTY_ICON),
            );
        }
    }
}

/// カードの地．角丸のテーマは文字の色を薄く敷き，platinum と desk は 1 ドットの枠にする．三角は地と同じ色
fn background(painter: &mut Painter, rect: Frame, pointer_y: Option<f32>) {
    let theme = painter.theme;
    let notch = glass::MEANING_NOTCH;
    let pointer = |y: f32| {
        vec![
            Point::new(rect.x, y - notch),
            Point::new(rect.x - notch, y),
            Point::new(rect.x, y + notch),
        ]
    };
    if !theme.is_rounded() {
        let line = candidate::FRAME_WIDTH;
        for frame in [
            Frame::new(rect.x, rect.y, rect.width, line),
            Frame::new(rect.x, rect.max_y() - line, rect.width, line),
            Frame::new(rect.x, rect.y, line, rect.height),
            Frame::new(rect.max_x() - line, rect.y, line, rect.height),
        ] {
            painter.rect(frame, theme.line);
        }
        if let Some(y) = pointer_y {
            let y = y
                .min(rect.max_y() - notch * 2.0)
                .max(rect.y + notch * 2.0)
                .round();
            painter.draws.push(Draw::Polygon {
                points: pointer(y),
                color: theme.line,
            });
        }
        return;
    }
    let fill = theme.meaning_card_fill();
    let radius = glass::MEANING_RADIUS
        .min(theme.corner_radius)
        .min(rect.height / 2.0)
        .min(rect.width / 2.0);
    painter.draws.push(Draw::RoundRect {
        frame: rect,
        radius,
        fill: Some(fill),
        stroke: None,
    });
    if let Some(y) = pointer_y.filter(|_| rect.height > (radius + notch) * 2.0) {
        // 三角は角の丸みにかからない範囲に収める
        let y = y
            .min(rect.max_y() - radius - notch)
            .max(rect.y + radius + notch)
            .round();
        painter.draws.push(Draw::Polygon {
            points: pointer(y),
            color: fill,
        });
    }
}

/// 分岐図で，選んでいる候補の行の右の端(start)からカードの左の辺(end)へ引く線．端に丸を付ける．
/// 曲線の枝のテーマはなめらかな S 字，直線の枝のテーマは折れ線にする
pub(super) fn connector(painter: &mut Painter, start: Point, end: Point) {
    let theme = painter.theme;
    let middle = ((start.x + end.x) / 2.0).round();
    if theme.curved_branches() {
        painter.draws.push(Draw::Curve {
            from: start,
            control1: Point::new(middle, start.y),
            control2: Point::new(middle, end.y),
            to: end,
            color: theme.selection,
            width: glass::LINE_WIDTH_SELECTED,
        });
    } else {
        // 枝と同じく，デバイスのピクセルにそろう長方形で描く
        let width = branch::LINE_WIDTH_SELECTED;
        let half = width / 2.0;
        let (top, bottom) = (start.y.min(end.y), start.y.max(end.y));
        for frame in [
            Frame::new(start.x, (start.y - half).round(), middle - start.x, width),
            Frame::new(
                (middle - half).round(),
                (top - half).round(),
                width,
                bottom - top + width,
            ),
            Frame::new(middle, (end.y - half).round(), end.x - middle, width),
        ] {
            painter.rect(frame, theme.selection);
        }
    }
    painter.draws.push(Draw::Ellipse {
        frame: Frame::square(end, glass::MEANING_DOT_SIZE),
        color: theme.selection,
    });
}

// MARK: - 中身

/// rect(カードの枠．地は描かない)の中に，見出し・意味・例・同音語を描く
fn content(painter: &mut Painter, card: &Card, rect: Frame) {
    let theme = painter.theme;
    let left = rect.x + glass::MEANING_PADDING;
    let right = rect.max_x() - glass::MEANING_PADDING;
    let mut y = rect.y + glass::MEANING_PADDING;
    header(painter, card, left, right, y);
    y += card.header_height + glass::MEANING_HEADER_GAP;
    for sense in &card.senses {
        let mut text_x = left;
        if let (Some(number), Some(first)) = (&sense.number, sense.meaning.first()) {
            let size = glass::MEANING_BADGE_SIZE;
            let badge = Frame::new(left, (y + (first.height - size) / 2.0).round(), size, size);
            painter.draws.push(Draw::RoundRect {
                frame: badge,
                radius: if theme.is_rounded() {
                    glass::MEANING_BADGE_RADIUS
                } else {
                    0.0
                },
                fill: Some(theme.meaning_tint()),
                stroke: None,
            });
            painter.centered(number, Font::MeaningNumber, theme.selection, badge);
            text_x = badge.max_x() + glass::NOTE_GAP;
        }
        let mut line_y = y;
        for line in &sense.meaning {
            draw_line(painter, line, text_x, line_y);
            line_y += line.height + glass::MEANING_LINE_SPACING;
        }
        if !sense.example.is_empty() {
            line_y += glass::MEANING_EXAMPLE_GAP - glass::MEANING_LINE_SPACING;
            let bar = Frame::new(
                text_x,
                line_y,
                glass::MEANING_EXAMPLE_BAR_WIDTH,
                lines_height(&sense.example),
            );
            painter.draws.push(Draw::RoundRect {
                frame: bar,
                radius: bar.width / 2.0,
                fill: Some(
                    theme
                        .selection
                        .with_alpha(opacity::glass::MEANING_EXAMPLE_BAR),
                ),
                stroke: None,
            });
            for line in &sense.example {
                draw_line(
                    painter,
                    line,
                    bar.max_x() + glass::MEANING_EXAMPLE_INDENT,
                    line_y,
                );
                line_y += line.height + glass::MEANING_LINE_SPACING;
            }
        }
        y += sense.height + glass::MEANING_SENSE_GAP;
    }
    if card.others.is_empty() {
        return;
    }
    y += glass::MEANING_OTHERS_GAP - glass::MEANING_SENSE_GAP;
    painter.rect(
        Frame::new(left, y.round(), right - left, candidate::FRAME_WIDTH),
        theme.line,
    );
    y += candidate::FRAME_WIDTH + glass::MEANING_OTHERS_GAP;
    others(
        painter,
        &card.others,
        left,
        right,
        y + glass::TAG_HEIGHT / 2.0,
    );
}

/// 1 行を x から左寄せで描く．書体の変わり目で字の間が空かないよう，次の字の位置は切り上げない幅で進める
fn draw_line(painter: &mut Painter, line: &Line, x: f32, y: f32) {
    let row = Frame::new(x, y, 0.0, line.height);
    let mut x = x;
    for run in &line.runs {
        painter.text(&run.text, run.style.font, run.style.color, x, row);
        x += painter.measure.width(&run.text, run.style.font);
    }
}

/// 見出し: 辞書のアイコン・語・品詞の札．語が長ければ品詞の札の手前で省く
fn header(painter: &mut Painter, card: &Card, left: f32, right: f32, y: f32) {
    let theme = painter.theme;
    let mid_y = y + card.header_height / 2.0;
    let icon = glass::MEANING_ICON_SIZE;
    painter.icon(
        Icon::Book,
        Frame::new(left, (mid_y - icon / 2.0).round(), icon, icon),
        theme.selection,
    );
    let mut x = left + icon + glass::NOTE_GAP;
    let tag_width = card
        .part_of_speech
        .map_or(0.0, |name| tag_width(painter, name));
    let available = right
        - x
        - if tag_width > 0.0 {
            tag_width + glass::NOTE_GAP
        } else {
            0.0
        };
    let shown = painter.truncated(&card.word, Font::MeaningHeadword, available);
    let row = Frame::new(x, y, 0.0, card.header_height);
    painter.text(&shown, Font::MeaningHeadword, theme.text, x, row);
    x += painter.width(&shown, Font::MeaningHeadword) + glass::NOTE_GAP;
    if let Some(name) = card.part_of_speech {
        // 品詞の札: アクセントの色を薄く敷いた地にアクセントの色の字
        let height = glass::MEANING_POS_HEIGHT;
        let frame = Frame::new(x.round(), (mid_y - height / 2.0).round(), tag_width, height);
        painter.draws.push(Draw::RoundRect {
            frame,
            radius: if theme.is_rounded() {
                height / 2.0
            } else {
                0.0
            },
            fill: Some(theme.meaning_tint()),
            stroke: None,
        });
        painter.centered(name, Font::MeaningTag, theme.selection, frame);
    }
}

fn tag_width(painter: &Painter, name: &str) -> f32 {
    (painter.width(name, Font::MeaningTag) + glass::MEANING_POS_PADDING_X * 2.0).ceil()
}

/// 同音語の行: 耳のアイコン・「同音語」・札．入らない札は「+n」にまとめる
fn others(painter: &mut Painter, others: &[String], left: f32, right: f32, mid_y: f32) {
    let theme = painter.theme;
    let icon = glass::MEANING_ICON_SIZE;
    painter.icon(
        Icon::Ear,
        Frame::new(left, (mid_y - icon / 2.0).round(), icon, icon),
        theme.text_muted,
    );
    let row = Frame::new(
        left,
        (mid_y - glass::TAG_HEIGHT / 2.0).round(),
        0.0,
        glass::TAG_HEIGHT,
    );
    let mut x = left + icon + glass::NOTE_GAP / 2.0;
    painter.text(
        strings::HOMOPHONE_OTHERS,
        Font::Label,
        theme.text_muted,
        x,
        row,
    );
    x += painter.width(strings::HOMOPHONE_OTHERS, Font::Label);
    for (index, word) in others.iter().enumerate() {
        let tag = painter.tag_width(word);
        let rest = others.len() - index - 1;
        let reserve = if rest > 0 {
            glass::USAGE_TAG_GAP + painter.width(&strings::more(rest), Font::Label)
        } else {
            0.0
        };
        if x + glass::USAGE_TAG_GAP + tag + reserve > right {
            painter.text(
                &strings::more(others.len() - index),
                Font::Label,
                theme.text_muted,
                x + glass::USAGE_TAG_GAP,
                row,
            );
            return;
        }
        x += glass::USAGE_TAG_GAP + tag;
        painter.tag(word, x, mid_y, false, TagStyle::Plain);
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

/// 幅 width で折り返した行．行の高さは行の中のいちばん大きい書体の高さ
fn lines(
    measure: &dyn Measure,
    characters: &[(char, Style)],
    width: f32,
    max_lines: usize,
) -> Vec<Line> {
    wrap(measure, characters, width, max_lines)
        .into_iter()
        .map(|runs| {
            let height = runs
                .iter()
                .map(|run| measure.height(run.style.font).ceil())
                .fold(0.0, f32::max);
            Line { runs, height }
        })
        .collect()
}

fn lines_height(lines: &[Line]) -> f32 {
    lines.iter().map(|line| line.height).sum::<f32>()
        + glass::MEANING_LINE_SPACING * lines.len().saturating_sub(1) as f32
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
        lines.push(runs(&characters[start..end]));
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
        );
        let sense = &card.senses[0];
        assert_eq!(sense.meaning.len(), glass::MEANING_MEANING_LINES as usize);
        assert_eq!(sense.example.len(), glass::MEANING_EXAMPLE_LINES as usize);
        let last = |lines: &[Line]| -> String {
            lines
                .last()
                .map(|line| line.runs.iter().map(|run| run.text.as_str()).collect())
                .unwrap_or_default()
        };
        assert!(last(&sense.meaning).ends_with(ELLIPSIS));
        assert!(last(&sense.example).ends_with(ELLIPSIS));
        // 意味が 1 つなら番号を付けない
        assert_eq!(sense.number, None);
    }

    #[test]
    fn 意味が2つ以上なら番号を付け_文字の幅を番号の分だけ狭める() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let text = "意".repeat(28);
        let one = list_card(&painter(&look), &note(&[(text.as_str(), None)], &[]));
        let two = list_card(
            &painter(&look),
            &note(&[(text.as_str(), None), ("働く", None)], &[]),
        );
        assert_eq!(one.senses[0].meaning.len(), 1);
        assert_eq!(two.senses[0].meaning.len(), 2);
        assert_eq!(two.senses[0].number.as_deref(), Some("1"));
        assert_eq!(two.senses[1].number.as_deref(), Some("2"));
        assert_eq!(
            one.width,
            glass::MEANING_CARD_WIDTH + glass::MEANING_PADDING * 2.0
        );
    }

    #[test]
    fn 同音語の行は区切りの線の下に並べ_入らない札は数にまとめる() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let few = list_card(
            &painter(&look),
            &note(&[("撮影する", None)], &["取る", "採る"]),
        );
        let none = list_card(&painter(&look), &note(&[("撮影する", None)], &[]));
        assert_eq!(
            few.height - none.height,
            glass::MEANING_OTHERS_GAP * 2.0 + candidate::FRAME_WIDTH + glass::TAG_HEIGHT
        );
        let mut drawn = painter(&look);
        draw(
            &mut drawn,
            Some(&few),
            Frame::new(0.0, 0.0, few.width, few.height),
            None,
        );
        let shown: Vec<String> = drawn
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Text { text, .. } => Some(text.clone()),
                _ => None,
            })
            .collect();
        for text in ["撮る", "動詞", "撮影する", "同音語", "取る", "採る"] {
            assert!(shown.contains(&text.to_string()), "{text}");
        }
        assert!(drawn.draws.iter().any(|draw| matches!(
            draw,
            Draw::Icon {
                icon: Icon::Ear,
                ..
            }
        )));

        let many: Vec<String> = (0..30).map(|index| format!("語{index}")).collect();
        let many: Vec<&str> = many.iter().map(String::as_str).collect();
        let crowded = list_card(&painter(&look), &note(&[("撮影する", None)], &many));
        let mut drawn = painter(&look);
        let rect = Frame::new(0.0, 0.0, crowded.width, crowded.height);
        draw(&mut drawn, Some(&crowded), rect, None);
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
            glass::MEANING_BRANCH_WIDTH,
        );
        assert_eq!(card.others, ["採る", "執る"]);
    }

    #[test]
    fn 空けておくカードは辞書のアイコンだけを薄く出す() {
        for name in ["washi", "platinum"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut drawn = painter(&look);
            draw(
                &mut drawn,
                None,
                Frame::new(0.0, 0.0, 300.0, 120.0),
                Some(40.0),
            );
            assert!(!drawn
                .draws
                .iter()
                .any(|draw| matches!(draw, Draw::Text { .. })));
            assert!(drawn.draws.iter().any(|draw| matches!(draw,
                Draw::Icon { icon: Icon::Book, color, .. } if color.alpha == opacity::glass::MEANING_EMPTY_ICON)));
            // 選んでいる候補を三角で指す
            assert_eq!(count_polygons(&drawn.draws), 1, "{name}");
        }
    }

    fn count_polygons(draws: &[Draw]) -> usize {
        draws
            .iter()
            .filter(|draw| matches!(draw, Draw::Polygon { .. }))
            .count()
    }

    #[test]
    fn 指す三角はカードの角にかからない高さに収める() {
        for name in ["washi", "platinum"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let rect = Frame::new(20.0, 10.0, 300.0, 120.0);
            for wanted in [0.0, 70.0, 500.0] {
                let mut drawn = painter(&look);
                background(&mut drawn, rect, Some(wanted));
                let tip = drawn.draws.iter().find_map(|draw| match draw {
                    Draw::Polygon { points, .. } => Some(points[1]),
                    _ => None,
                });
                let tip = tip.expect("三角を描く");
                assert_eq!(tip.x, rect.x - glass::MEANING_NOTCH);
                assert!(
                    tip.y - glass::MEANING_NOTCH >= rect.y + 1.0,
                    "{name} {wanted}"
                );
                assert!(
                    tip.y + glass::MEANING_NOTCH <= rect.max_y() - 1.0,
                    "{name} {wanted}"
                );
            }
        }
    }

    #[test]
    fn つなぐ線は曲線の枝のテーマでs字_直線の枝のテーマで折れ線() {
        let start = Point::new(100.0, 50.0);
        let end = Point::new(140.0, 90.0);
        let curved = theme("washi");
        let mut drawn = painter(&Look::new(&curved, 15.0));
        connector(&mut drawn, start, end);
        assert!(
            matches!(drawn.draws[0], Draw::Curve { from, to, color, .. } if from == start && to == end && color == curved.selection)
        );
        assert!(
            matches!(drawn.draws.last(), Some(Draw::Ellipse { frame, .. }) if frame.mid_x() == end.x && frame.mid_y() == end.y)
        );

        for name in ["platinum", "automatic"] {
            let straight = theme(name);
            let mut drawn = painter(&Look::new(&straight, 15.0));
            connector(&mut drawn, start, end);
            assert!(
                !drawn
                    .draws
                    .iter()
                    .any(|draw| matches!(draw, Draw::Curve { .. })),
                "{name}"
            );
            let rects: Vec<Frame> = drawn
                .draws
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Rect { frame, .. } => Some(*frame),
                    _ => None,
                })
                .collect();
            assert_eq!(rects.len(), 3, "{name}");
            // 候補の行の端から出て，カードの辺で終わる
            assert_eq!(rects[0].x, start.x);
            assert_eq!(rects[2].max_x(), end.x);
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
        let height = list_card(&painter(&look), &short).height;
        assert_eq!(first, Some(height));
        // 意味の無い候補に移っても，同じ並びなら空けたまま
        assert_eq!(
            reservation.list(&list(&entries, None), &look, &Fixed),
            Some(height)
        );
        // 高いカードを出したら，その高さを空けておく
        let taller = list_card(&painter(&look), &tall).height;
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
