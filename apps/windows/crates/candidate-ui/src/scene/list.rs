#![forbid(unsafe_code)]

//! 候補の一覧(macOS の CandidateView)．上から，文字種の行・候補・足元の 3 つの区画．
//! 語の意味のカードは，候補の右(候補の列と同じ高さ)か，候補と足元のあいだに出す

use super::list_layout::{self, ListLayout, Style};
use super::meaning::{self, CardFrame};
use super::paint::{Painter, TagStyle};
use super::{Frame, Look, Measure, Point, Scene};
use crate::strings;
use crate::theme::Font;
use ipc::{CandidateFocus, CandidateList, KeyHint, MeaningPlacement};
use tokens::opacity;
use tokens::size::meaning as card_size;
use tokens::size::{branch, candidate, glass};

/// 区画の寸法(list_layout)と，行の中の寸法
struct Metrics {
    layout: list_layout::Metrics,
    style: Style,
    /// 行の地の内側の左右の余白．番号の丸(番号)の左と注釈の札の右，足元の案内と位置の左右の端をここにそろえる
    row_padding_x: f32,
    /// 番号の幅(番号から候補の文字まで)
    lead: f32,
}

impl Metrics {
    fn new(look: &Look, measure: &dyn Measure) -> Self {
        let rounded = look.theme.is_rounded();
        let scale = look.font_size / candidate::FONT_SIZE;
        let label = measure.height(Font::Label).ceil();
        if rounded {
            // 足元の行は，キーの札・案内のアイコン・文字の行の箱のいちばん高いもの
            let footer = glass::KEYCAP_HEIGHT.max(glass::NOTE_ICON_SIZE).max(label);
            Self {
                layout: list_layout::Metrics::rounded(
                    (glass::ROW_HEIGHT * scale).round(),
                    glass::HEADER_HEIGHT,
                    footer,
                ),
                style: Style::Rounded,
                row_padding_x: glass::ROW_PADDING_X,
                lead: glass::BADGE_SIZE + candidate::PADDING_X,
            }
        } else {
            let section = label.max(glass::KEYCAP_HEIGHT) + candidate::SECTION_PADDING_Y * 2.0;
            Self {
                layout: list_layout::Metrics::bevel(
                    (candidate::ROW_HEIGHT * scale).round(),
                    section,
                    look.theme.has_drop_shadow(),
                ),
                style: Style::Bevel,
                row_padding_x: candidate::PADDING_X,
                lead: candidate::INDEX_WIDTH,
            }
        }
    }
}

struct Footer {
    hints: Vec<KeyHint>,
    note: Option<ipc::Note>,
    position: String,
    /// 選んでいる候補に連想があることの知らせ(R-18)のうち，キーの割り当てが無いときの語．
    /// キーがあればキーキャップの札として hints に入れる(キーを文字で書かない)
    association_hint: Option<String>,
}

fn footer(list: &CandidateList) -> Footer {
    if list.focus == CandidateFocus::Variants {
        let index = list.selected_variant.map_or(1, |index| index + 1);
        return Footer {
            hints: list.hints.clone().unwrap_or_default(),
            note: list.note.clone(),
            position: strings::variants_position(index, list.variants.len() as u32),
            association_hint: None,
        };
    }
    // キーの案内はエンジンが，キー設定の表と「キーの案内を表示」の設定に従って作る(FooterHints)
    let mut hints = list.hints.clone().unwrap_or_default();
    let mut association_hint = None;
    if let Some(label) = &list.association_hint {
        match &list.association_key {
            Some(key) => hints.push(KeyHint {
                keys: key.clone(),
                label: label.clone(),
            }),
            None => association_hint = Some(label.clone()),
        }
    }
    Footer {
        hints,
        note: list.note.clone(),
        // まだ選んでいない(入力中の候補の窓で選び始める前の)ときは，何番目かを出さない
        position: if list.position == 0 {
            String::new()
        } else {
            strings::position(list.position, list.position, list.total)
        },
        association_hint,
    }
}

pub fn candidate_list(list: &CandidateList, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let padding = candidate::PADDING_X;
    let footer = footer(list);

    // 候補の右に出す語の意味のカード．幅は決まっているので，候補の列より先に決める
    let side = (meaning::placement(list.meaning_placement) == MeaningPlacement::Side)
        .then(|| {
            let card = list
                .homophone
                .as_ref()
                .map(|note| meaning::list_card(&painter, note));
            meaning::side_slot(card, card_size::LIST_WIDTH, look.reserved_card)
        })
        .flatten();
    let side_extent = side.as_ref().map_or(0.0, |slot| {
        metrics
            .layout
            .separator_gap
            .max(metrics.layout.separator_width)
            + slot.width
    });
    let outer = (metrics.layout.edge + metrics.layout.padding) * 2.0 + metrics.layout.shadow;

    // 長い文の候補は，窓の幅の上限に収まるよう省く．ほかの候補と違うところの少し手前から見せる
    // (頭が同じ文が並ぶので，末尾を省くと見分けられない．macOS の CandidateView と同じ)
    let text_limit = candidate::MAX_WIDTH
        - metrics.lead
        - metrics.row_padding_x
        - candidate::PADDING_X
        - outer
        - side_extent;
    let shown: Vec<String> = list
        .entries
        .iter()
        .map(|entry| {
            let annotation = entry
                .annotation
                .as_deref()
                .map_or(0.0, |note| painter.tag_width(note) + padding)
                + entry.command.map_or(0.0, |_| Painter::command_width());
            let available = (text_limit - annotation).max(0.0);
            let measure = |text: &str| painter.width(text, Font::Candidate);
            if measure(&entry.text) <= available {
                return entry.text.clone();
            }
            let shared = super::fitting::shared_prefix_length(
                &entry.text,
                list.entries.iter().map(|other| other.text.as_str()),
            )
            .saturating_sub(candidate::TRUNCATION_CONTEXT as usize);
            super::fitting::truncated_keeping(&entry.text, available, shared, &measure)
        })
        .collect();

    // 大きさ
    let entry_width = list
        .entries
        .iter()
        .zip(&shown)
        .map(|(entry, text)| {
            entry.command.map_or(0.0, |_| Painter::command_width())
                + painter.width(text, Font::Candidate)
                + entry
                    .annotation
                    .as_deref()
                    .map_or(0.0, |note| painter.tag_width(note) + padding)
        })
        .fold(0.0, f32::max);
    let variants_width: f32 = list
        .variants
        .iter()
        .map(|variant| {
            painter.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0
        })
        .sum();
    let hints_width = match &footer.note {
        Some(note) => painter.note_width(note),
        None => painter.hints_width(&footer.hints),
    };
    let association_hint = footer
        .association_hint
        .as_deref()
        .map_or(0.0, |hint| painter.width(hint, Font::Label) + padding);
    let footer_width = (hints_width
        + association_hint
        + painter.width(&footer.position, Font::Label)
        + metrics.row_padding_x * 2.0
        + padding)
        .ceil();
    let heading_width = list.association.as_ref().map_or(0.0, |heading| {
        super::association::width(&painter, heading) - padding * 2.0 + metrics.row_padding_x * 2.0
    });
    // 候補の列(行の地)の幅: 左の余白・番号・文字・右の余白(文字の右は番号の左より広く空ける)
    let list_width = candidate::MIN_WIDTH
        .max(metrics.row_padding_x + metrics.lead + entry_width + padding)
        .max(variants_width + (metrics.row_padding_x - candidate::VARIANT_PADDING_X) * 2.0)
        .max(heading_width)
        .ceil();
    let limit = candidate::MAX_WIDTH.max(candidate::MIN_WIDTH);
    let (slot, card) = match side {
        Some(slot) => {
            let card = list_layout::Card::Side {
                width: slot.width,
                height: slot.height,
            };
            (Some(slot), Some(card))
        }
        None => {
            // 候補の下のカードは窓の中身の幅いっぱいにし，その幅で折り返す
            let below = (list.meaning_placement == Some(MeaningPlacement::Below))
                .then_some(list.homophone.as_ref())
                .flatten();
            let slot = below.map(|note| {
                let width =
                    list_layout::below_card_width(list_width, footer_width, card_size::LIST_WIDTH)
                        .min(limit - outer)
                        .floor();
                meaning::below_slot(meaning::Card::new(
                    &painter,
                    note,
                    note.others.clone(),
                    width,
                ))
            });
            let card = slot.as_ref().map(|slot| list_layout::Card::Below {
                width: slot.width,
                height: slot.height,
            });
            (slot, card)
        }
    };
    let has_header = !list.variants.is_empty() || list.association.is_some();
    let layout = list_layout::place(
        metrics.style,
        list_width,
        footer_width,
        has_header,
        list.entries.len(),
        card,
        limit,
        &metrics.layout,
        look.size,
    );
    draw_list(
        &mut painter,
        list,
        &footer,
        &shown,
        &metrics,
        &layout,
        slot.as_ref(),
        look.rest_opacity,
    );
    painter.finish(layout.width, layout.height)
}

/// 区画の配置のとおりに描く．rest_opacity は第 1 候補と選んでいる候補以外の濃さ
#[allow(clippy::too_many_arguments)]
fn draw_list(
    painter: &mut Painter,
    list: &CandidateList,
    footer: &Footer,
    shown: &[String],
    metrics: &Metrics,
    layout: &ListLayout,
    slot: Option<&meaning::Slot>,
    rest_opacity: f32,
) {
    let theme = painter.theme;
    painter.panel(layout.body);
    if let Some(header) = layout.header {
        match &list.association {
            Some(heading) => super::association::draw(
                painter,
                heading,
                header.inset(metrics.row_padding_x - candidate::PADDING_X, 0.0),
            ),
            None => variants(painter, list, header, metrics.row_padding_x),
        }
    }
    if let Some(line) = layout.header_separator {
        painter.rect(line, theme.line);
    }
    let mut selected_mid_y = None;
    for (index, (entry, row)) in list.entries.iter().zip(&layout.rows).enumerate() {
        let row = *row;
        painter.hit(
            layout.hit_rows[index],
            ipc::PointerTarget::Entry {
                index: index as u32,
            },
        );
        let selected =
            list.focus == CandidateFocus::Candidate && list.selected_entry == Some(index as u32);
        if selected {
            selected_mid_y = Some(row.mid_y());
            if theme.is_rounded() {
                painter.capsule(row, theme.selection);
            } else {
                painter.rect(row, theme.selection);
            }
        }
        // 出した直後は，第 1 候補と選んでいる候補だけを濃く出す
        let opacity = if selected || index == 0 {
            1.0
        } else {
            rest_opacity
        };
        let text_color = if selected {
            theme.selection_text
        } else {
            theme.text
        }
        .faded(opacity);
        let muted_color = if selected {
            theme.selection_text
        } else {
            theme.text_muted
        }
        .faded(opacity);
        let number = (index + 1).to_string();
        let number_x = row.x + metrics.row_padding_x;
        let mut text_x = number_x + metrics.lead;
        if let Some(kind) = entry.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            painter.command(kind, text_x, row.mid_y(), selected, opacity);
            text_x += Painter::command_width();
        }
        // 番号キーで選べない窓(選び始める前の入力中の候補など)では番号を振らない．
        // 文字の位置は変えない(選び始めて番号が出たときに候補が横に動かないように)
        if list.shows_numbers.unwrap_or(true) {
            if theme.is_rounded() {
                let center = Point::new(number_x + glass::BADGE_SIZE / 2.0, row.mid_y());
                painter.badge(
                    &number,
                    center,
                    selected,
                    opacity,
                    glass::BADGE_SIZE,
                    Font::Key,
                );
            } else {
                painter.text(&number, Font::Label, muted_color, number_x, row);
            }
        }
        painter.text(&shown[index], Font::Candidate, text_color, text_x, row);
        // 省いたときは補正の下線を引かない(位置が合わない)
        let whole = shown[index] == entry.text;
        if let (true, Some(start), Some(length)) =
            (whole, entry.corrected_start, entry.corrected_length)
        {
            // 打ち間違いを直した語句に，入力中の文字と同じ補正の点線を引く．位置は char の数で届く
            let before: String = entry.text.chars().take(start as usize).collect();
            let corrected: String = entry
                .text
                .chars()
                .skip(start as usize)
                .take(length as usize)
                .collect();
            let from = (text_x + painter.width(&before, Font::Candidate)).round();
            let to = (from + painter.width(&corrected, Font::Candidate)).round();
            // 角丸のテーマの行の地は行の間隔より上下に縮めてあるので，その分を引く
            let offset = if theme.is_rounded() {
                glass::UNDERLINE_OFFSET - glass::SELECTION_INSET_Y
            } else {
                branch::UNDERLINE_OFFSET
            };
            let color = if selected {
                theme.selection_text
            } else {
                theme.correction
            }
            .faded(opacity);
            painter.underline(from, to, row.max_y() - offset, color, true);
        }
        if let Some(annotation) = entry.annotation.as_deref() {
            painter.tag(
                annotation,
                row.max_x() - metrics.row_padding_x,
                row.mid_y(),
                selected,
                TagStyle::of(annotation, entry.command.is_some()),
            );
        }
    }
    if let (Some(slot), Some(card)) = (slot, layout.card) {
        if let Some(line) = layout.card_separator {
            painter.rect(line, theme.line);
        }
        // 候補の右のカードは，選んでいる候補を左の辺の三角で指す
        let pointer_y = match slot.placement {
            MeaningPlacement::Side => selected_mid_y,
            MeaningPlacement::Below => None,
        };
        let frame = if theme.is_rounded() {
            CardFrame::Boxed
        } else {
            CardFrame::Pane
        };
        meaning::draw(painter, slot.card.as_ref(), card, pointer_y, frame);
    }
    painter.rect(layout.footer_separator, theme.line);
    footer_section(painter, footer, layout.footer, metrics.row_padding_x);
}

/// 文字種の行．ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)．
/// 最初の文字種の文字を候補の番号の左(行の地の内側の余白 inset)にそろえる
fn variants(painter: &mut Painter, list: &CandidateList, section: Frame, inset: f32) {
    let theme = painter.theme;
    let mut x = section.x + inset - candidate::VARIANT_PADDING_X;
    for (index, variant) in list.variants.iter().enumerate() {
        let selected =
            list.focus == CandidateFocus::Variants && list.selected_variant == Some(index as u32);
        let color = match (selected, variant.is_available) {
            (true, _) => theme.selection_text,
            (false, true) => theme.text_muted,
            (false, false) => theme.text_muted.faded(opacity::variant::UNAVAILABLE),
        };
        let width = painter.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0;
        let cell = Frame::new(x, section.y, width, section.height);
        if variant.is_available {
            painter.hit(
                cell,
                ipc::PointerTarget::ListVariant {
                    index: index as u32,
                },
            );
        }
        if selected {
            if theme.is_rounded() {
                painter.capsule(cell, theme.selection);
            } else {
                painter.rect(cell, theme.selection);
            }
        }
        painter.text(
            &variant.label,
            Font::Label,
            color,
            cell.x + candidate::VARIANT_PADDING_X,
            cell,
        );
        x += width;
    }
}

/// 角丸のテーマは案内を左，位置を右．platinum と desk は位置を左，案内を右(漢字Talk 7 の候補ウィンドウにならう)．
/// 左右の端は候補の行の番号の左と注釈の札の右(行の地の内側の余白 inset)にそろえる
fn footer_section(painter: &mut Painter, footer: &Footer, section: Frame, inset: f32) {
    let theme = painter.theme;
    let left = section.x + inset;
    let right = section.max_x() - inset;
    if theme.is_rounded() {
        match &footer.note {
            Some(note) => painter.note(note, left, section.mid_y()),
            None => {
                painter.hints(&footer.hints, left, section.mid_y());
                if let Some(hint) = &footer.association_hint {
                    // 選んでいる候補に連想があることを，キーの案内のあとに小さく出す(R-18)
                    let x = left + painter.hints_width(&footer.hints) + candidate::PADDING_X;
                    painter.text(hint, Font::Label, theme.text_muted, x, section);
                }
            }
        }
        painter.text_right(
            &footer.position,
            Font::Label,
            theme.text_muted,
            right,
            section,
        );
        return;
    }
    painter.text(
        &footer.position,
        Font::Label,
        theme.text_muted,
        left,
        section,
    );
    match &footer.note {
        Some(note) => {
            let width = painter.note_width(note);
            painter.note(note, right - width, section.mid_y());
        }
        None => {
            let width = painter.hints_width(&footer.hints);
            painter.hints(&footer.hints, right - width, section.mid_y());
            if let Some(hint) = &footer.association_hint {
                let end = right - width - candidate::PADDING_X;
                painter.text_right(hint, Font::Label, theme.text_muted, end, section);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::super::Draw;
    use super::*;
    use ipc::{CandidateEntry, CandidateVariant};

    #[test]
    fn 窓の大きさを外から決めると_その大きさで描く() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let natural = candidate_list(&list(Some(0)), &look, &Fixed);
        let narrower = (natural.width - 10.0, natural.height - 10.0);
        let sized = candidate_list(
            &list(Some(0)),
            &Look {
                size: Some(narrower),
                ..look
            },
            &Fixed,
        );
        assert_eq!((sized.width, sized.height), narrower);
        assert_eq!(texts(&sized), texts(&natural));
    }

    fn list(selected: Option<u32>) -> CandidateList {
        CandidateList {
            association: None,
            association_hint: None,
            association_key: None,
            homophone: None,
            shows_numbers: None,
            variants: vec![CandidateVariant {
                label: "カタカナ".into(),
                is_available: true,
            }],
            selected_variant: None,
            entries: vec![
                CandidateEntry {
                    text: "変換".into(),
                    annotation: None,
                    corrected_start: None,
                    corrected_length: None,
                    command: None,
                },
                CandidateEntry {
                    text: "へんかん".into(),
                    annotation: Some("入力のまま".into()),
                    corrected_start: None,
                    corrected_length: None,
                    command: None,
                },
            ],
            selected_entry: selected,
            focus: CandidateFocus::Candidate,
            position: 2,
            total: 30,
            note: None,
            meaning_placement: None,
            hints: Some(vec![hint("↑", "文字種")]),
        }
    }

    fn hint(keys: &str, label: &str) -> KeyHint {
        KeyHint {
            keys: keys.into(),
            label: label.into(),
        }
    }

    #[test]
    fn 押した位置から行と字種を引く_描いた文字の位置と合う() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
            let at = |text: &str| {
                let frame = text_frame(&scene, text).expect("描いた文字がある");
                scene.target_at(frame.x + 1.0, frame.mid_y())
            };
            assert_eq!(at("へんかん"), Some(ipc::PointerTarget::Entry { index: 1 }));
            assert_eq!(
                at("カタカナ"),
                Some(ipc::PointerTarget::ListVariant { index: 0 })
            );
            // 使えない字種は押せない
            let mut unavailable = list(Some(0));
            unavailable.variants[0].is_available = false;
            let scene = candidate_list(&unavailable, &Look::new(&theme, 15.0), &Fixed);
            let frame = text_frame(&scene, "カタカナ").expect("描いた文字がある");
            assert_eq!(scene.target_at(frame.x + 1.0, frame.mid_y()), None);
        }
    }

    #[test]
    fn 連想の一覧は文字種の行の代わりに見出しを出し_足元に連想の知らせを出す() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut associated = list(Some(0));
            associated.association = Some(ipc::AssociationHeading {
                headword: "速い".into(),
                label: "速度".into(),
                group: 1,
                group_count: 3,
            });
            let scene = candidate_list(&associated, &Look::new(&theme, 15.0), &Fixed);
            let texts: Vec<String> = texts(&scene).into_iter().map(|(text, _)| text).collect();
            assert!(texts.contains(&"速い".to_string()));
            assert!(texts.contains(&"1 / 3".to_string()));
            assert!(!texts.contains(&"カタカナ".to_string()));
            // 連想変換のキーは文字ではなくキーキャップで描き，語だけを文字にする
            let mut hinted = list(Some(0));
            hinted.association_hint = Some("連想".into());
            hinted.association_key = Some("Ctrl+Tab".into());
            let scene = candidate_list(&hinted, &Look::new(&theme, 15.0), &Fixed);
            let hinted_texts = texts_of(&scene);
            assert!(hinted_texts.contains(&"連想".to_string()));
            assert!(!hinted_texts.iter().any(|text| text.contains("Tab")));
            // キーが割り当てられていなければ語だけ
            hinted.association_key = None;
            let scene = candidate_list(&hinted, &Look::new(&theme, 15.0), &Fixed);
            assert!(texts_of(&scene).contains(&"連想".to_string()));
        }
    }

    fn homophone() -> ipc::HomophoneNote {
        ipc::HomophoneNote {
            word: "変換".into(),
            senses: vec![ipc::HomophoneSense {
                meaning: "別の形に変える".into(),
                example: Some("かなを漢字に変換する".into()),
            }],
            others: vec!["返還".into(), "偏官".into()],
            part_of_speech: Some(ipc::PartOfSpeech::Noun),
        }
    }

    fn with_meaning(placement: MeaningPlacement) -> CandidateList {
        CandidateList {
            homophone: Some(homophone()),
            meaning_placement: Some(placement),
            ..list(Some(0))
        }
    }

    /// 描いた多角形(一覧のカードが選んでいる候補を指す三角)
    fn polygons(scene: &Scene) -> Vec<Vec<Point>> {
        scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Polygon { points, .. } => Some(points.clone()),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn 語の意味は候補の右のカードにし_選んでいる候補を三角で指す() {
        for name in ["platinum", "automatic", "desk"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = candidate_list(&with_meaning(MeaningPlacement::Side), &look, &Fixed);
            let texts = texts_of(&scene);
            for text in ["変換", "名詞", "別の形に変える", "同音語", "返還", "偏官"]
            {
                assert!(texts.contains(&text.to_string()), "{name}: {text}");
            }
            // 足元のキーの案内は消さない
            assert!(texts.contains(&"2 / 30".to_string()), "{name}");
            // カードは候補の列の右に置き，候補の行はカードにかからない
            let meaning = text_frame(&scene, "別の形に変える").expect("意味を描く");
            let candidate = text_frame(&scene, "へんかん").expect("候補を描く");
            assert!(meaning.x > candidate.max_x(), "{name}");
            let row = scene
                .hits
                .iter()
                .find(|hit| hit.target == ipc::PointerTarget::Entry { index: 0 })
                .map(|hit| hit.frame)
                .expect("候補の行");
            assert!(
                row.max_x() + glass::SEPARATOR_GAP.min(candidate::FRAME_WIDTH) <= meaning.x,
                "{name}"
            );
            // 三角は選んでいる候補の行の高さを指す(カードの角にかからない範囲で)
            let pointers = polygons(&scene);
            assert_eq!(pointers.len(), 1, "{name}");
            assert!(
                (pointers[0][1].y - row.mid_y()).abs() <= card_size::RADIUS + card_size::NOTCH,
                "{name}"
            );
            assert!(pointers[0][1].x < meaning.x, "{name}");
            // 意味の無い一覧より広い
            let plain = candidate_list(&list(Some(0)), &look, &Fixed);
            assert!(scene.width >= plain.width + card_size::LIST_WIDTH, "{name}");
        }
    }

    #[test]
    fn 文字種の行を選んでいるあいだは三角で指さない() {
        let theme = theme("automatic");
        let mut variants = with_meaning(MeaningPlacement::Side);
        variants.focus = CandidateFocus::Variants;
        variants.selected_variant = Some(0);
        let scene = candidate_list(&variants, &Look::new(&theme, 15.0), &Fixed);
        assert!(polygons(&scene).is_empty());
        assert!(texts_of(&scene).contains(&"別の形に変える".to_string()));
    }

    #[test]
    fn 長い意味はカードの幅で折り返し_候補を窓の幅の上限に収める() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut long = with_meaning(MeaningPlacement::Side);
            if let Some(note) = long.homophone.as_mut() {
                note.senses[0].meaning = "意".repeat(200);
                note.others = (0..30).map(|index| format!("語{index}")).collect();
            }
            long.entries[1].text = "長".repeat(80);
            let scene = candidate_list(&long, &look, &Fixed);
            let texts = texts_of(&scene);
            let lines = texts.iter().filter(|text| text.starts_with('意')).count();
            assert_eq!(lines, card_size::MEANING_LINES as usize, "{name}");
            assert!(texts
                .iter()
                .any(|text| text.starts_with('意') && text.ends_with('…')));
            assert!(texts.iter().any(|text| text.starts_with('+')));
            // 長い候補は省き，カードを含めて窓の幅の上限に収める
            assert!(texts
                .iter()
                .any(|text| text.starts_with('長') && text.ends_with('…')));
            assert!(
                scene.width <= candidate::MAX_WIDTH + 1.0,
                "{name}: {}",
                scene.width
            );
            for draw in &scene.draws {
                if let Draw::Text { frame, .. } = draw {
                    assert!(
                        frame.x >= 0.0 && frame.max_x() <= scene.body.max_x(),
                        "{name}: {draw:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn 候補の下に出す設定では候補と足元のあいだに窓の幅いっぱいのカードを出す() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = candidate_list(&with_meaning(MeaningPlacement::Below), &look, &Fixed);
            let meaning = text_frame(&scene, "別の形に変える").expect("意味を描く");
            let last = text_frame(&scene, "へんかん").expect("候補を描く");
            let footer = text_frame(&scene, "2 / 30").expect("足元を描く");
            assert!(
                meaning.y > last.max_y() && meaning.max_y() < footer.y,
                "{name}"
            );
            // 三角で指さない
            assert!(polygons(&scene).is_empty(), "{name}");
            // 窓の幅はカードの幅に合わせて広げる
            assert!(scene.width >= card_size::LIST_WIDTH);
            let plain = candidate_list(&list(Some(0)), &look, &Fixed);
            assert!(scene.height > plain.height, "{name}");
        }
    }

    #[test]
    fn 意味の無い候補に移っても空けておいたカードで窓の大きさを変えない() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut reservation = crate::scene::CardReservation::default();
            let shown = with_meaning(MeaningPlacement::Side);
            let first = candidate_list(
                &shown,
                &Look {
                    reserved_card: reservation.list(&shown, &look, &Fixed),
                    ..look
                },
                &Fixed,
            );
            let moved = CandidateList {
                homophone: None,
                meaning_placement: None,
                selected_entry: Some(1),
                ..list(Some(1))
            };
            let reserved = reservation.list(&moved, &look, &Fixed);
            assert!(reserved.is_some(), "{name}");
            let empty = candidate_list(
                &moved,
                &Look {
                    reserved_card: reserved,
                    ..look
                },
                &Fixed,
            );
            assert_eq!(
                (empty.width, empty.height),
                (first.width, first.height),
                "{name}"
            );
            assert!(!texts_of(&empty).contains(&"別の形に変える".to_string()));
            assert!(empty.draws.iter().any(|draw| matches!(
                draw,
                Draw::Icon {
                    icon: crate::keys::Icon::Book,
                    ..
                }
            )));
            // 空けておかなければカードを出さない
            let bare = candidate_list(&moved, &look, &Fixed);
            assert!(bare.width < empty.width, "{name}");
        }
    }

    #[test]
    fn 意味が2つ以上なら角丸の四角に番号を入れる() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let mut two = with_meaning(MeaningPlacement::Side);
        if let Some(note) = two.homophone.as_mut() {
            note.senses.push(ipc::HomophoneSense {
                meaning: "向きを変える".into(),
                example: None,
            });
        }
        let single = candidate_list(&with_meaning(MeaningPlacement::Side), &look, &Fixed);
        let double = candidate_list(&two, &look, &Fixed);
        let texts = texts_of(&double);
        assert!(texts.contains(&"向きを変える".to_string()));
        let badges = double
            .draws
            .iter()
            .filter(|draw| matches!(draw, Draw::RoundRect { radius, frame, .. }
                if *radius == card_size::NUMBER_RADIUS && frame.width == card_size::MARKER_WIDTH && frame.height == card_size::MARKER_WIDTH))
            .count();
        assert_eq!(badges, 2);
        assert!(double.height >= single.height);
        // 意味が 1 つなら番号の四角を描かない
        assert!(!single
            .draws
            .iter()
            .any(|draw| matches!(draw, Draw::RoundRect { radius, frame, .. }
            if *radius == card_size::NUMBER_RADIUS && frame.width == card_size::MARKER_WIDTH)));
    }

    fn texts_of(scene: &Scene) -> Vec<String> {
        texts(scene).into_iter().map(|(text, _)| text).collect()
    }

    #[test]
    fn 番号キーで選べない窓は番号を振らず_文字種の行が無ければ文字種の案内を出さない() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let numbered = texts_of(&candidate_list(&list(Some(0)), &look, &Fixed));
            assert!(numbered.contains(&"1".to_string()));
            assert!(numbered.contains(&"文字種".to_string()));
            let mut browsing = list(None);
            browsing.shows_numbers = Some(false);
            browsing.variants.clear();
            // 文字種の行が無い一覧には，エンジンが文字種の案内を送らない(FooterHints)
            browsing.hints = None;
            let scene = candidate_list(&browsing, &look, &Fixed);
            let texts = texts_of(&scene);
            assert!(texts.contains(&"変換".to_string()));
            assert!(!texts.contains(&"1".to_string()));
            assert!(!texts.contains(&"2".to_string()));
            assert!(!texts.contains(&"文字種".to_string()));
            // 番号を振らなくても，候補の文字の位置は変えない
            let natural = candidate_list(&list(None), &look, &Fixed);
            assert_eq!(
                text_frame(&scene, "変換").map(|frame| frame.x),
                text_frame(&natural, "変換").map(|frame| frame.x)
            );
        }
    }

    #[test]
    fn 選んだ行を選択の色にする() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = candidate_list(&list(Some(1)), &Look::new(&theme, 15.0), &Fixed);
            let texts = texts(&scene);
            assert!(texts.contains(&("変換".into(), theme.text)));
            assert!(texts.contains(&("へんかん".into(), theme.selection_text)));
            assert!(texts.contains(&("入力のまま".into(), theme.selection_text)));
            assert!(texts.contains(&("2 / 30".into(), theme.text_muted)));
            assert!(scene.width >= candidate::MIN_WIDTH);
        }
    }

    #[test]
    fn コマンドの候補は種類のアイコンを文字の前に置き_札をアクセントの色にする() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut commands = list(Some(0));
            commands.entries.push(CandidateEntry {
                text: "Claude を開く".into(),
                annotation: Some(strings::COMMAND.into()),
                corrected_start: None,
                corrected_length: None,
                command: Some(ipc::CommandKind::OpenApplication),
            });
            let plain = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
            let scene = candidate_list(&commands, &Look::new(&theme, 15.0), &Fixed);
            let icon = scene.draws.iter().find_map(|draw| match draw {
                Draw::Icon {
                    icon, frame, color, ..
                } if *icon == crate::keys::Icon::Window => Some((*frame, *color)),
                _ => None,
            });
            let (icon, color) = icon.expect("種類のアイコンを描く");
            assert_eq!(color, theme.selection);
            // 文字はアイコンの右から書き，ほかの行の文字より右に寄る
            let title = text_frame(&scene, "Claude を開く").unwrap();
            assert!(title.x >= icon.max_x());
            assert!(title.x > text_frame(&scene, "変換").unwrap().x);
            assert!(texts(&scene).contains(&(strings::COMMAND.into(), theme.selection)));
            // アイコンの幅だけ窓を広げる
            assert!(scene.width > plain.width);
        }
    }

    #[test]
    fn 選んでいるコマンドの候補は_アイコンと札を選択の文字の色にする() {
        let theme = theme("automatic");
        let mut commands = list(Some(2));
        commands.entries.push(CandidateEntry {
            text: "サイト".into(),
            annotation: Some(strings::COMMAND.into()),
            corrected_start: None,
            corrected_length: None,
            command: Some(ipc::CommandKind::OpenURL),
        });
        let scene = candidate_list(&commands, &Look::new(&theme, 15.0), &Fixed);
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Icon { icon: crate::keys::Icon::Globe, color, .. } if *color == theme.selection_text)));
        assert!(texts(&scene).contains(&(strings::COMMAND.into(), theme.selection_text)));
    }

    #[test]
    fn 候補の中の直した語句に補正の点線を引く() {
        let theme = theme("automatic");
        let mut corrected = list(None);
        corrected.entries[0] = CandidateEntry {
            text: "今日は良い".into(),
            annotation: None,
            corrected_start: Some(3),
            corrected_length: Some(2),
            command: None,
        };
        let scene = candidate_list(&corrected, &Look::new(&theme, 15.0), &Fixed);
        let lines: Vec<(f32, f32)> = scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Line {
                    from,
                    to,
                    color,
                    dot_pitch: Some(_),
                    ..
                } if *color == theme.correction => Some((from.x, to.x)),
                _ => None,
            })
            .collect();
        assert_eq!(lines.len(), 1);
        // 「良い」の 2 文字の幅(Fixed は 1 文字 10)
        assert_eq!(lines[0].1 - lines[0].0, 20.0);
        assert!(candidate_list(&list(None), &Look::new(&theme, 15.0), &Fixed)
            .draws
            .iter()
            .all(|draw| !matches!(draw, Draw::Line { color, dot_pitch: Some(_), .. } if *color == theme.correction)));
    }

    #[test]
    fn 高さは行の数で決まる() {
        let theme = theme("platinum");
        let look = Look::new(&theme, 15.0);
        let two = candidate_list(&list(None), &look, &Fixed);
        let mut longer = list(None);
        longer.entries.push(CandidateEntry {
            text: "返還".into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
        });
        let three = candidate_list(&longer, &look, &Fixed);
        assert_eq!(three.height - two.height, (candidate::ROW_HEIGHT).round());
    }

    #[test]
    fn 角丸のテーマは番号を丸に入れ_選択を角丸にする() {
        let theme = theme("washi");
        let scene = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(
            count(&scene, |draw| matches!(draw, Draw::Ellipse { .. })),
            2
        );
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::RoundRect { radius, fill: Some(color), .. } if *radius == glass::SELECTION_RADIUS && *color == theme.selection)));
        // 足元の案内はキーキャップ(↑ のアイコン)と説明
        assert!(scene.draws.iter().any(|draw| matches!(
            draw,
            Draw::Icon {
                icon: crate::keys::Icon::Up,
                ..
            }
        )));
        assert!(texts(&scene).iter().any(|(text, _)| text == "文字種"));
    }

    #[test]
    fn 出した直後は第_1_候補と選んだ候補のほかを薄くする() {
        let theme = theme("nordic");
        let mut look = Look::new(&theme, 15.0);
        look.rest_opacity = 0.0;
        let mut three = list(Some(2));
        three.entries.push(CandidateEntry {
            text: "返還".into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
        });
        three.entries.push(CandidateEntry {
            text: "偏官".into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
        });
        let texts = texts(&candidate_list(&three, &look, &Fixed));
        let alpha = |wanted: &str| {
            texts
                .iter()
                .find(|(text, _)| text == wanted)
                .map(|(_, color)| color.alpha)
        };
        assert_eq!(alpha("変換"), Some(1.0));
        assert_eq!(alpha("へんかん"), Some(0.0));
        assert_eq!(alpha("返還"), Some(1.0));
    }

    #[test]
    fn 文字種の行を選んでいるときは位置と案内を変える() {
        let theme = theme("automatic");
        let mut variants = list(None);
        variants.focus = CandidateFocus::Variants;
        variants.selected_variant = Some(0);
        variants.hints = Some(vec![hint("←→", "選択"), hint("Space", "候補")]);
        let scene = candidate_list(&variants, &Look::new(&theme, 15.0), &Fixed);
        let texts = texts(&scene);
        assert!(texts.contains(&("文字種 1 / 1".into(), theme.text_muted)));
        assert!(texts.contains(&("カタカナ".into(), theme.selection_text)));
        assert!(texts.iter().any(|(text, _)| text == "選択"));
    }

    #[test]
    fn 知らせがあれば案内の代わりに出す() {
        let theme = theme("platinum");
        let mut noted = list(Some(0));
        noted.note = Some(ipc::Note {
            tone: ipc::NoteTone::Correction,
            title: "修正".into(),
            subject: None,
            key: Some("Space".into()),
            key_action: Some("入力のままに戻す".into()),
            text: "修正　Space 入力のままに戻す".into(),
        });
        let scene = candidate_list(&noted, &Look::new(&theme, 15.0), &Fixed);
        // 主な語は補正の色，キーでできることはキーの案内と同じ控えめな色
        assert!(texts(&scene).contains(&("修正".into(), theme.correction)));
        assert!(texts(&scene).contains(&("入力のままに戻す".into(), theme.text_muted)));
        assert!(!texts(&scene).iter().any(|(text, _)| text == "文字種"));
    }

    #[test]
    fn desk_は右と下に影の分だけ大きくする() {
        let desk = theme("desk");
        let platinum = theme("platinum");
        let a = candidate_list(&list(None), &Look::new(&desk, 15.0), &Fixed);
        let b = candidate_list(&list(None), &Look::new(&platinum, 15.0), &Fixed);
        assert_eq!(a.width - b.width, candidate::SHADOW_OFFSET);
        assert!(
            matches!(a.draws[0], Draw::Rect { frame, .. } if frame.x == candidate::SHADOW_OFFSET)
        );
    }
}
