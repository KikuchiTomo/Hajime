#![forbid(unsafe_code)]

//! 候補の一覧(macOS の CandidateView)．上から，文字種の行・候補・足元の 3 つの区画

use super::paint::{Painter, TagStyle};
use super::{Frame, Look, Measure, Point, Scene};
use crate::strings;
use crate::theme::Font;
use ipc::{CandidateFocus, CandidateList, KeyHint};
use tokens::opacity;
use tokens::size::{branch, candidate, glass};

struct Metrics {
    row_height: f32,
    section_height: f32,
    /// 外枠と立体の縁の太さ．角丸のテーマは余白
    inset: f32,
    /// 番号の幅
    lead: f32,
    shadow: f32,
}

impl Metrics {
    fn new(look: &Look, measure: &dyn Measure) -> Self {
        let rounded = look.theme.is_rounded();
        let base_row = if rounded {
            glass::ROW_HEIGHT
        } else {
            candidate::ROW_HEIGHT
        };
        Self {
            row_height: (base_row * look.font_size / candidate::FONT_SIZE).round(),
            section_height: if rounded {
                glass::FOOTER_HEIGHT
            } else {
                measure.height(Font::Label).ceil().max(glass::KEYCAP_HEIGHT)
                    + candidate::SECTION_PADDING_Y * 2.0
            },
            inset: if rounded {
                glass::PADDING / 2.0
            } else {
                candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH
            },
            lead: if rounded {
                glass::BADGE_SIZE + candidate::PADDING_X
            } else {
                candidate::INDEX_WIDTH
            },
            shadow: if look.theme.has_drop_shadow() {
                candidate::SHADOW_OFFSET
            } else {
                0.0
            },
        }
    }
}

struct Footer {
    hints: Vec<KeyHint>,
    note: Option<ipc::Note>,
    position: String,
    /// 選んでいる候補に連想があることの知らせ(「Ctrl+Tab 連想」)
    association_hint: Option<String>,
}

fn footer(list: &CandidateList) -> Footer {
    if list.focus == CandidateFocus::Variants {
        let index = list.selected_variant.map_or(1, |index| index + 1);
        return Footer {
            hints: strings::variants_hints(),
            note: list.note.clone(),
            position: strings::variants_position(index, list.variants.len() as u32),
            association_hint: None,
        };
    }
    Footer {
        // 連想の一覧には文字種の行が無いので，文字種の案内を出さない
        hints: if list.association.is_some() {
            Vec::new()
        } else {
            strings::candidates_hints()
        },
        note: list.note.clone(),
        position: strings::position(list.position, list.position, list.total),
        association_hint: list.association_hint.clone(),
    }
}

pub fn candidate_list(list: &CandidateList, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let padding = candidate::PADDING_X;
    let footer = footer(list);

    // 大きさ
    let entry_width = list
        .entries
        .iter()
        .map(|entry| {
            entry.command.map_or(0.0, |_| Painter::command_width())
                + painter.width(&entry.text, Font::Candidate)
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
    let association_hint = list
        .association_hint
        .as_deref()
        .map_or(0.0, |hint| painter.width(hint, Font::Label) + padding);
    let footer_width = hints_width
        + association_hint
        + painter.width(&footer.position, Font::Label)
        + padding * 3.0;
    let heading_width = list
        .association
        .as_ref()
        .map_or(0.0, |heading| super::association::width(&painter, heading));
    let homophone_width = list.homophone.as_ref().map_or(0.0, |note| {
        super::homophone::width(&painter, note) + padding * 2.0
    });
    let content_width = candidate::MIN_WIDTH
        .max(metrics.lead + entry_width + padding * 2.0)
        .max(variants_width + padding * 2.0)
        .max(heading_width)
        .max(homophone_width)
        .max(footer_width);
    let mut content_height = list.entries.len() as f32 * metrics.row_height
        + metrics.section_height
        + candidate::FRAME_WIDTH;
    // 連想の一覧では，文字種の行の代わりに見出しの行を出す
    if !list.variants.is_empty() || list.association.is_some() {
        content_height += metrics.section_height + candidate::FRAME_WIDTH;
    }
    if list.homophone.is_some() {
        content_height += super::homophone::height() + candidate::FRAME_WIDTH;
    }
    let width = (content_width + metrics.inset * 2.0 + metrics.shadow).ceil();
    let height = (content_height + metrics.inset * 2.0 + metrics.shadow).ceil();
    let (width, height) = look.sized(width, height);

    // 描く
    let body = Frame::new(0.0, 0.0, width - metrics.shadow, height - metrics.shadow);
    painter.panel(body);
    let content = body.inset(metrics.inset, metrics.inset);
    let mut y = content.y;
    if let Some(heading) = &list.association {
        super::association::draw(
            &mut painter,
            heading,
            Frame::new(content.x, y, content.width, metrics.section_height),
        );
        y += metrics.section_height;
        separator(&mut painter, y, content.x, content.max_x());
        y += candidate::FRAME_WIDTH;
    } else if !list.variants.is_empty() {
        variants(
            &mut painter,
            list,
            Frame::new(content.x, y, content.width, metrics.section_height),
        );
        y += metrics.section_height;
        separator(&mut painter, y, content.x, content.max_x());
        y += candidate::FRAME_WIDTH;
    }
    for (index, entry) in list.entries.iter().enumerate() {
        let row = Frame::new(content.x, y, content.width, metrics.row_height);
        painter.hit(
            row,
            ipc::PointerTarget::Entry {
                index: index as u32,
            },
        );
        let selected =
            list.focus == CandidateFocus::Candidate && list.selected_entry == Some(index as u32);
        if selected {
            if theme.is_rounded() {
                painter.capsule(row.inset(0.0, glass::SELECTION_INSET_Y), theme.selection);
            } else {
                painter.rect(row, theme.selection);
            }
        }
        // 出した直後は，第 1 候補と選んでいる候補だけを濃く出す
        let opacity = if selected || index == 0 {
            1.0
        } else {
            look.rest_opacity
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
        let mut text_x = if theme.is_rounded() {
            row.x + padding / 2.0 + metrics.lead
        } else {
            row.x + padding + metrics.lead
        };
        if let Some(kind) = entry.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            painter.command(kind, text_x, row.mid_y(), selected, opacity);
            text_x += Painter::command_width();
        }
        if theme.is_rounded() {
            let center = Point::new(row.x + padding / 2.0 + glass::BADGE_SIZE / 2.0, row.mid_y());
            painter.badge(
                &number,
                center,
                selected,
                opacity,
                glass::BADGE_SIZE,
                Font::Key,
            );
            painter.text(&entry.text, Font::Candidate, text_color, text_x, row);
        } else {
            painter.text(&number, Font::Label, muted_color, row.x + padding, row);
            painter.text(&entry.text, Font::Candidate, text_color, text_x, row);
        }
        if let (Some(start), Some(length)) = (entry.corrected_start, entry.corrected_length) {
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
            let offset = if theme.is_rounded() {
                glass::UNDERLINE_OFFSET
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
                row.max_x() - padding / 2.0,
                row.mid_y(),
                selected,
                TagStyle::of(annotation, entry.command.is_some()),
            );
        }
        y += metrics.row_height;
    }
    if let Some(note) = &list.homophone {
        // 使い分けは候補と足元のあいだに出す．足元のキーの案内は消さない
        separator(&mut painter, y, content.x, content.max_x());
        y += candidate::FRAME_WIDTH;
        super::homophone::draw(
            &mut painter,
            note,
            Frame::new(
                content.x + padding,
                y,
                content.width - padding * 2.0,
                super::homophone::height(),
            ),
        );
        y += super::homophone::height();
    }
    separator(&mut painter, y, content.x, content.max_x());
    y += candidate::FRAME_WIDTH;
    footer_section(
        &mut painter,
        &footer,
        Frame::new(content.x, y, content.width, metrics.section_height),
    );
    painter.finish(width, height)
}

fn separator(painter: &mut Painter, y: f32, from: f32, to: f32) {
    if painter.theme.is_rounded() {
        let half = candidate::PADDING_X / 2.0;
        painter.separator(y, from + half, to - half);
    } else {
        painter.separator(y, from, to);
    }
}

/// 文字種の行．ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)
fn variants(painter: &mut Painter, list: &CandidateList, section: Frame) {
    let theme = painter.theme;
    let inset_y = if theme.is_rounded() {
        glass::VARIANT_INSET_Y
    } else {
        candidate::VARIANT_INSET_Y
    };
    let mut x = section.x + candidate::PADDING_X / 2.0;
    for (index, variant) in list.variants.iter().enumerate() {
        let selected =
            list.focus == CandidateFocus::Variants && list.selected_variant == Some(index as u32);
        let color = match (selected, variant.is_available) {
            (true, _) => theme.selection_text,
            (false, true) => theme.text_muted,
            (false, false) => theme.text_muted.faded(opacity::variant::UNAVAILABLE),
        };
        let width = painter.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0;
        let cell = Frame::new(
            x,
            section.y + inset_y,
            width,
            section.height - inset_y * 2.0,
        );
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

/// 角丸のテーマは案内を左，位置を右．platinum と desk は位置を左，案内を右(漢字Talk 7 の候補ウィンドウにならう)
fn footer_section(painter: &mut Painter, footer: &Footer, section: Frame) {
    let theme = painter.theme;
    let left = section.x + candidate::PADDING_X;
    let right = section.max_x() - candidate::PADDING_X;
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
            homophone: None,
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
            let mut hinted = list(Some(0));
            hinted.association_hint = Some("Ctrl+Tab 連想".into());
            let scene = candidate_list(&hinted, &Look::new(&theme, 15.0), &Fixed);
            assert!(texts_of(&scene).contains(&"Ctrl+Tab 連想".to_string()));
        }
    }

    #[test]
    fn 使い分けは候補と足元のあいだに出し_長い意味と多いほかの語は欄の幅に収める() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut short = list(Some(0));
            short.homophone = Some(ipc::HomophoneNote {
                word: "撮る".into(),
                meaning: "撮影する".into(),
                example: Some("写真を撮る".into()),
                others: vec!["取る".into(), "採る".into()],
            });
            let scene = candidate_list(&short, &Look::new(&theme, 15.0), &Fixed);
            let texts = texts_of(&scene);
            for text in [
                "撮る",
                "撮影する",
                "「写真を撮る」",
                "ほかに",
                "取る",
                "採る",
            ] {
                assert!(texts.contains(&text.to_string()), "{text}");
            }
            // 足元のキーの案内は消さない
            assert!(texts.contains(&"2 / 30".to_string()));

            let mut long = short.clone();
            if let Some(note) = long.homophone.as_mut() {
                note.meaning = "意".repeat(80);
                note.others = (0..30).map(|index| format!("語{index}")).collect();
            }
            let scene = candidate_list(&long, &Look::new(&theme, 15.0), &Fixed);
            let without = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
            assert!(
                scene.width
                    <= without
                        .width
                        .max(glass::USAGE_MAX_WIDTH + candidate::PADDING_X * 2.0 + 40.0)
            );
            let texts = texts_of(&scene);
            assert!(!texts.contains(&"「写真を撮る」".to_string()));
            assert!(texts
                .iter()
                .any(|text| text.starts_with('意') && text.ends_with('…')));
            assert!(texts.iter().any(|text| text.starts_with('+')));
            for draw in &scene.draws {
                if let Draw::Text { frame, .. } = draw {
                    assert!(frame.x >= 0.0 && frame.x < scene.body.max_x(), "{draw:?}");
                }
            }
        }
    }

    fn texts_of(scene: &Scene) -> Vec<String> {
        texts(scene).into_iter().map(|(text, _)| text).collect()
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
