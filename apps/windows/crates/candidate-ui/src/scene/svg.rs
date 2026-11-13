#![forbid(unsafe_code)]

//! 描く順の部品(Draw)を SVG にする(テストだけ)．Windows でなくても窓の見た目を画像にして見比べるのに使う．
//! 文字の幅は書体の大きさから見積もる(日本語の字は 1 字が書体の大きさ，英数字は 0.6 倍)．本物の描画は app::render

use super::{Draw, Figure, Frame, Measure, Scene, Segment};
use crate::icon;
use crate::theme::{Color, Face, Font, ResolvedTheme, Weight};
use std::fmt::Write;

/// 書体の大きさで文字の幅と行の高さを見積もる
pub struct Approximate<'a> {
    pub theme: &'a ResolvedTheme,
    pub font_size: f32,
}

impl Measure for Approximate<'_> {
    fn width(&self, text: &str, font: Font) -> f32 {
        let size = self.theme.font(font, self.font_size).size;
        text.chars()
            .map(|character| {
                if character == ' ' {
                    0.3
                } else if character.is_ascii() {
                    0.6
                } else {
                    1.0
                }
            })
            .sum::<f32>()
            * size
    }

    fn height(&self, font: Font) -> f32 {
        self.theme.font(font, self.font_size).size * 1.33
    }
}

fn paint(color: Color) -> String {
    format!(
        "rgb({},{},{})\" fill-opacity=\"{:.3}",
        (color.red * 255.0).round(),
        (color.green * 255.0).round(),
        (color.blue * 255.0).round(),
        color.alpha
    )
}

fn stroke(color: Color) -> String {
    format!(
        "rgb({},{},{})\" stroke-opacity=\"{:.3}",
        (color.red * 255.0).round(),
        (color.green * 255.0).round(),
        (color.blue * 255.0).round(),
        color.alpha
    )
}

fn escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// 窓の見た目を SVG にする．背景のすりガラスは写せないので，角丸のテーマは窓の背景と枠線も描く．margin は窓のまわりの空き
pub fn scene(
    scene: &Scene,
    theme: &ResolvedTheme,
    font_size: f32,
    background: Color,
    margin: f32,
) -> String {
    let width = scene.width + margin * 2.0;
    let height = scene.height + margin * 2.0;
    let mut out = String::new();
    let _ = write!(
        out,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">"
    );
    let _ = write!(
        out,
        "<rect width=\"{width}\" height=\"{height}\" fill=\"{}\"/>",
        paint(background)
    );
    let _ = write!(out, "<g transform=\"translate({margin},{margin})\">");
    if theme.is_rounded() && theme.backdrop {
        let body = scene.body.inset(0.5, 0.5);
        let _ = write!(
            out,
            "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"{}\" fill=\"{}\" stroke=\"{}\" stroke-width=\"1\"/>",
            body.x,
            body.y,
            body.width,
            body.height,
            theme.corner_radius,
            paint(theme.surface),
            stroke(theme.frame)
        );
    }
    for draw in &scene.draws {
        write_draw(&mut out, draw, theme, font_size);
    }
    out.push_str("</g></svg>");
    out
}

/// いくつかの窓を，画面に見立てた背景の上の (x, y) に並べて 1 枚の SVG にする．
/// backdrop が真の窓は，背景のすりガラスの代わりに窓の背景と枠線を描く(吹き出しのように自分で背景を描く窓は偽)
pub fn composite(
    width: f32,
    height: f32,
    background: Color,
    windows: &[(&Scene, f32, f32, bool)],
    theme: &ResolvedTheme,
    font_size: f32,
) -> String {
    let mut out = String::new();
    let _ = write!(
        out,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\">"
    );
    let _ = write!(
        out,
        "<rect width=\"{width}\" height=\"{height}\" fill=\"{}\"/>",
        paint(background)
    );
    for (scene, x, y, backdrop) in windows {
        let _ = write!(out, "<g transform=\"translate({x},{y})\">");
        if *backdrop && theme.is_rounded() && theme.backdrop {
            let body = scene.body.inset(0.5, 0.5);
            let _ = write!(
                out,
                "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" rx=\"{}\" fill=\"{}\" stroke=\"{}\" stroke-width=\"1\"/>",
                body.x,
                body.y,
                body.width,
                body.height,
                theme.corner_radius,
                paint(theme.surface),
                stroke(theme.frame)
            );
        }
        for draw in &scene.draws {
            write_draw(&mut out, draw, theme, font_size);
        }
        out.push_str("</g>");
    }
    out.push_str("</svg>");
    out
}

/// 図形の SVG のパス．円弧は y が下へ増える画面で見た向き(SVG の sweep と同じ)
fn figure_path(figure: &Figure) -> String {
    let mut d = format!("M{} {}", figure.start.x, figure.start.y);
    for segment in &figure.segments {
        match segment {
            Segment::Line(to) => {
                let _ = write!(d, " L{} {}", to.x, to.y);
            }
            Segment::Arc {
                to,
                radius,
                clockwise,
            } => {
                let _ = write!(
                    d,
                    " A{radius} {radius} 0 0 {} {} {}",
                    u8::from(*clockwise),
                    to.x,
                    to.y
                );
            }
        }
    }
    d
}

fn rect(out: &mut String, frame: Frame, extra: &str) {
    let _ = write!(
        out,
        "<rect x=\"{}\" y=\"{}\" width=\"{}\" height=\"{}\" {extra}/>",
        frame.x, frame.y, frame.width, frame.height
    );
}

fn write_draw(out: &mut String, draw: &Draw, theme: &ResolvedTheme, font_size: f32) {
    match draw {
        Draw::Rect { frame, color } => rect(out, *frame, &format!("fill=\"{}\"", paint(*color))),
        Draw::RoundRect {
            frame,
            radius,
            fill,
            stroke: line,
        } => {
            let fill = fill.map_or("none".to_string(), paint);
            let line = line.map_or(String::new(), |(color, width)| {
                format!(" stroke=\"{}\" stroke-width=\"{width}\"", stroke(color))
            });
            rect(
                out,
                *frame,
                &format!("rx=\"{radius}\" fill=\"{fill}\"{line}"),
            );
        }
        Draw::Ellipse { frame, color } => {
            let _ = write!(
                out,
                "<ellipse cx=\"{}\" cy=\"{}\" rx=\"{}\" ry=\"{}\" fill=\"{}\"/>",
                frame.mid_x(),
                frame.mid_y(),
                frame.width / 2.0,
                frame.height / 2.0,
                paint(*color)
            );
        }
        Draw::Polygon { points, color } => {
            let points: Vec<String> = points.iter().map(|p| format!("{},{}", p.x, p.y)).collect();
            let _ = write!(
                out,
                "<polygon points=\"{}\" fill=\"{}\"/>",
                points.join(" "),
                paint(*color)
            );
        }
        Draw::Curve {
            from,
            control1,
            control2,
            to,
            color,
            width,
        } => {
            let _ = write!(
                out,
                "<path d=\"M{} {} C{} {} {} {} {} {}\" fill=\"none\" stroke=\"{}\" stroke-width=\"{width}\" stroke-linecap=\"round\"/>",
                from.x, from.y, control1.x, control1.y, control2.x, control2.y, to.x, to.y,
                stroke(*color)
            );
        }
        Draw::Path {
            figures,
            color,
            width,
        } => {
            // 端は平らにし，直角の角は尖らせる(描く層と同じ)
            let d: Vec<String> = figures.iter().map(figure_path).collect();
            let d = d.join(" ");
            let _ = write!(
                out,
                "<path d=\"{}\" fill=\"none\" stroke=\"{}\" stroke-width=\"{width}\" stroke-linecap=\"butt\" stroke-linejoin=\"miter\"/>",
                d,
                stroke(*color)
            );
        }
        Draw::Shape {
            figure,
            fill,
            stroke: line,
        } => {
            let d = format!("{} Z", figure_path(figure));
            let fill = fill.map_or("none".to_string(), paint);
            let line = line.map_or(String::new(), |(color, width)| {
                format!(
                    " stroke=\"{}\" stroke-width=\"{width}\" stroke-linejoin=\"miter\"",
                    stroke(color)
                )
            });
            let _ = write!(out, "<path d=\"{d}\" fill=\"{fill}\"{line}/>");
        }
        Draw::Line {
            from,
            to,
            color,
            width,
            dot_pitch,
        } => {
            let dash = dot_pitch.map_or(String::new(), |pitch| {
                format!(" stroke-dasharray=\"0 {pitch}\"")
            });
            let _ = write!(
                out,
                "<line x1=\"{}\" y1=\"{}\" x2=\"{}\" y2=\"{}\" stroke=\"{}\" stroke-width=\"{width}\" stroke-linecap=\"round\"{dash}/>",
                from.x, from.y, to.x, to.y,
                stroke(*color)
            );
        }
        Draw::Icon {
            icon,
            frame,
            color,
            width,
        } => {
            for figure in icon::figures(*icon, *frame) {
                let points: Vec<String> = figure
                    .points
                    .iter()
                    .map(|p| format!("{},{}", p.x, p.y))
                    .collect();
                let tag = if figure.closed { "polygon" } else { "polyline" };
                let _ = write!(
                    out,
                    "<{tag} points=\"{}\" fill=\"none\" stroke=\"{}\" stroke-width=\"{width}\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
                    points.join(" "),
                    stroke(*color)
                );
            }
        }
        Draw::Text {
            frame,
            text,
            font,
            color,
        } => {
            let spec = theme.font(*font, font_size);
            let family = match spec.face {
                Face::Mincho => "Hiragino Mincho ProN",
                Face::Monospaced => "Menlo, Hiragino Sans",
                Face::Rounded => "Hiragino Maru Gothic ProN",
                _ => "Hiragino Sans",
            };
            let weight = match spec.weight {
                Weight::Regular => 400,
                Weight::Medium => 500,
                Weight::Semibold => 600,
            };
            let _ = write!(
                out,
                "<text x=\"{}\" y=\"{}\" font-family=\"{family}\" font-size=\"{}\" font-weight=\"{weight}\" fill=\"{}\" dominant-baseline=\"central\">{}</text>",
                frame.x,
                frame.mid_y(),
                spec.size,
                paint(*color),
                escape(text)
            );
        }
        Draw::Shadow { .. } => {}
        Draw::Group { opacity, draws, .. } => {
            let _ = write!(out, "<g opacity=\"{opacity}\">");
            for draw in draws {
                write_draw(out, draw, theme, font_size);
            }
            out.push_str("</g>");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::theme;
    use super::super::{branch_map, candidate_list, mode, note, prediction, Look};
    use super::*;
    use ipc::{
        BranchColumn, BranchMap, CandidateEntry, CandidateFocus, CandidateList, HomophoneNote,
        HomophoneSense, KeyHint, MeaningPlacement, PartOfSpeech,
    };

    fn strings(texts: &[&str]) -> Vec<String> {
        texts.iter().map(|text| (*text).to_string()).collect()
    }

    fn homophone() -> HomophoneNote {
        HomophoneNote {
            word: "撮る".into(),
            part_of_speech: Some(PartOfSpeech::Verb),
            senses: vec![
                HomophoneSense {
                    meaning: "写真や動画を写す".into(),
                    example: Some("記念写真を撮った".into()),
                },
                HomophoneSense {
                    meaning: "映画やテレビ番組などを撮影する".into(),
                    example: Some("ドラマを撮る".into()),
                },
            ],
            others: strings(&["取る", "採る", "執る", "捕る"]),
        }
    }

    fn list() -> CandidateList {
        CandidateList {
            association: None,
            association_hint: None,
            association_key: None,
            homophone: Some(homophone()),
            shows_numbers: None,
            column_length: None,
            variants: vec![],
            selected_variant: None,
            entries: ["撮る", "取る", "採る", "執る"]
                .iter()
                .map(|text| CandidateEntry {
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
            focus: CandidateFocus::Candidate,
            position: 1,
            total: 6,
            note: None,
            meaning_placement: Some(MeaningPlacement::Side),
            hints: Some(vec![KeyHint {
                keys: "Shift+Space".into(),
                label: "文字種".into(),
            }]),
        }
    }

    fn branch() -> BranchMap {
        let alternatives = strings(&["取る", "撮る", "とる", "採る"]);
        BranchMap {
            association: None,
            association_hint: None,
            association_key: None,
            columns: vec![
                super::super::sample::column("写真を"),
                BranchColumn {
                    text: "撮る".into(),
                    selected_alternative: Some(1),
                    is_focused: true,
                    is_uncertain: true,
                    homophone: Some(homophone()),
                    alternative_notes: vec![None; alternatives.len()],
                    alternatives,
                    ..super::super::sample::column("撮る")
                },
            ],
            position: 1,
            total: 7,
            note: None,
            hints: vec![],
            meaning_placement: Some(MeaningPlacement::Side),
        }
    }

    /// 語の意味の見本(一覧・分岐図，候補の右・候補の下，意味の無い候補を選んだところ)を，標準のテーマと platinum・desk で SVG に書き出す．
    /// HAJIME_SCENE_SVG に書き出し先のディレクトリを渡したときだけ動く:
    /// HAJIME_SCENE_SVG=<ディレクトリ> cargo test -p candidate-ui --lib scene::svg -- --ignored
    #[test]
    #[ignore = "見本を書き出すときだけ動かす"]
    fn 語の意味の見本を書き出す() {
        let Ok(directory) = std::env::var("HAJIME_SCENE_SVG") else {
            return;
        };
        for name in [
            "automatic",
            "platinum",
            "desk",
            "washi",
            "neon",
            "terminal",
            "nordic",
            "contrast",
        ] {
            let theme = theme(name);
            // 文字が明るいテーマは暗い背景に置く
            let dark = theme.text.red + theme.text.green + theme.text.blue > 1.5;
            let font_size = tokens::size::candidate::FONT_SIZE;
            let measure = Approximate {
                theme: &theme,
                font_size,
            };
            let look = Look::new(&theme, font_size);
            let background = if dark {
                Color {
                    red: 0.15,
                    green: 0.15,
                    blue: 0.15,
                    alpha: 1.0,
                }
            } else {
                Color {
                    red: 0.63,
                    green: 0.63,
                    blue: 0.63,
                    alpha: 1.0,
                }
            };
            let below_list = CandidateList {
                meaning_placement: Some(MeaningPlacement::Below),
                ..list()
            };
            let below_branch = BranchMap {
                meaning_placement: Some(MeaningPlacement::Below),
                ..branch()
            };
            // 意味の無い候補を選んだところ(吹き出しを出さず，窓の大きさは変えない)
            let empty = CandidateList {
                homophone: None,
                meaning_placement: None,
                selected_entry: Some(1),
                ..list()
            };
            let mut empty_branch = branch();
            empty_branch.columns[1].homophone = None;
            empty_branch.columns[1].selected_alternative = Some(2);
            empty_branch.meaning_placement = None;
            // 候補を表に広げた一覧(1 列 9 個．2 列目を選んでいる)
            let grid = CandidateList {
                entries: (1..=20)
                    .map(|number| CandidateEntry {
                        text: format!("缶{number}"),
                        annotation: None,
                        corrected_start: None,
                        corrected_length: None,
                        command: None,
                        has_comment: None,
                        detail: None,
                    })
                    .collect(),
                column_length: Some(9),
                selected_entry: Some(10),
                homophone: None,
                meaning_placement: None,
                position: 11,
                total: 20,
                ..list()
            };
            let list_scene = candidate_list(&list(), &look, &measure);
            let branch_scene = branch_map(&branch(), &look, &measure);
            let shown_list = super::super::bubble::for_list(&list(), &list_scene)
                .map(|(note, others, row)| (note.clone(), others, row));
            let shown_branch = super::super::bubble::for_branch(&branch(), &branch_scene)
                .map(|(note, others, row)| (note.clone(), others, row));
            let scenes = [
                ("list", list_scene.clone(), shown_list),
                (
                    "list-below",
                    candidate_list(&below_list, &look, &measure),
                    None,
                ),
                ("list-empty", candidate_list(&empty, &look, &measure), None),
                ("list-grid", candidate_list(&grid, &look, &measure), None),
                ("branch", branch_scene.clone(), shown_branch),
                (
                    "branch-below",
                    branch_map(&below_branch, &look, &measure),
                    None,
                ),
                (
                    "branch-empty",
                    branch_map(&empty_branch, &look, &measure),
                    None,
                ),
            ];
            for (kind, drawn, shown) in scenes {
                let svg = match shown {
                    // 吹き出しは画面が十分に広いとみなして候補の窓の右に置く
                    Some((note, others, row)) => {
                        let margin = 16.0;
                        let shown = super::super::bubble::bubble(&note, others, &look, &measure);
                        let keep_clear: Vec<Frame> = drawn
                            .keep_clear
                            .iter()
                            .map(|frame| frame.offset(margin, margin))
                            .collect();
                        let placement = super::super::bubble::place(
                            row.offset(margin, margin),
                            drawn.body.offset(margin, margin),
                            (shown.width, shown.height),
                            Frame::new(-1000.0, -1000.0, 4000.0, 4000.0),
                            &keep_clear,
                            drawn
                                .inside
                                .as_ref()
                                .map(|inside| inside.offset(margin, margin))
                                .as_ref(),
                            &super::super::bubble::Metrics::tokens(theme.is_rounded()),
                        );
                        let bubble =
                            super::super::bubble::bubble_scene(&shown, &placement, &look, &measure);
                        let width = placement.window.max_x() + margin;
                        let height =
                            (drawn.height.max(placement.window.max_y() - margin)) + margin * 2.0;
                        composite(
                            width,
                            height,
                            background,
                            &[
                                (&drawn, margin, margin, true),
                                (
                                    &bubble,
                                    placement.window.x - bubble.body.x,
                                    placement.window.y - bubble.body.y,
                                    false,
                                ),
                            ],
                            &theme,
                            font_size,
                        )
                    }
                    None => scene(&drawn, &theme, font_size, background, 16.0),
                };
                let path =
                    std::path::Path::new(&directory).join(format!("meaning-{kind}-{name}.svg"));
                std::fs::write(path, svg).expect("書き出せる");
            }
        }
    }

    /// 語の意味の吹き出しの見本(一覧と分岐図．画面の右に入るときは右，入らないときは左，下の端では上へ寄せる)を SVG に書き出す．
    /// HAJIME_SCENE_SVG=<ディレクトリ> cargo test -p candidate-ui --lib scene::svg -- --ignored
    #[test]
    #[ignore = "見本を書き出すときだけ動かす"]
    fn 吹き出しの見本を書き出す() {
        use super::super::bubble;
        let Ok(directory) = std::env::var("HAJIME_SCENE_SVG") else {
            return;
        };
        for name in ["automatic", "washi"] {
            let theme = theme(name);
            let font_size = tokens::size::candidate::FONT_SIZE;
            let measure = Approximate {
                theme: &theme,
                font_size,
            };
            let look = Look::new(&theme, font_size);
            let dark = theme.text.red + theme.text.green + theme.text.blue > 1.5;
            let background = if dark {
                Color {
                    red: 0.15,
                    green: 0.15,
                    blue: 0.15,
                    alpha: 1.0,
                }
            } else {
                Color {
                    red: 0.63,
                    green: 0.63,
                    blue: 0.63,
                    alpha: 1.0,
                }
            };
            // 候補の窓には語の意味を入れない(吹き出しに出す)
            let plain_list = CandidateList {
                homophone: None,
                meaning_placement: None,
                ..list()
            };
            let mut plain_branch = branch();
            plain_branch.columns[1].homophone = None;
            plain_branch.meaning_placement = None;
            let list_scene = candidate_list(&plain_list, &look, &measure);
            // 画面の下の端の近くで，いちばん下の候補を選んでいるところ
            let last_list = CandidateList {
                selected_entry: Some(3),
                ..plain_list.clone()
            };
            let last_scene = candidate_list(&last_list, &look, &measure);
            let branch_scene = branch_map(&plain_branch, &look, &measure);
            let row = |scene: &Scene, target: ipc::PointerTarget| {
                scene
                    .hits
                    .iter()
                    .find(|hit| hit.target == target)
                    .map(|hit| hit.frame)
                    .expect("選んでいる行")
            };
            let list_row = row(&list_scene, ipc::PointerTarget::Entry { index: 0 });
            let last_row = row(&last_scene, ipc::PointerTarget::Entry { index: 3 });
            let branch_row = row(&branch_scene, ipc::PointerTarget::Alternative { index: 1 });
            let shown = bubble::bubble(&homophone(), homophone().others, &look, &measure);
            // いちばん下の「執る」を選んだときは「執る」の意味
            let held = HomophoneNote {
                word: "執る".into(),
                part_of_speech: Some(PartOfSpeech::Verb),
                senses: vec![HomophoneSense {
                    meaning: "仕事や事務を取り扱う".into(),
                    example: Some("指揮を執る".into()),
                }],
                others: strings(&["取る", "撮る", "採る", "捕る"]),
            };
            let last_bubble = bubble::bubble(&held, held.others.clone(), &look, &measure);
            let branch_bubble =
                bubble::bubble(&homophone(), strings(&["執る", "捕る"]), &look, &measure);
            // 分岐図で 1 番目(取る)といちばん下(採る)を選んだところ
            let picked = |index: u32| {
                let mut map = plain_branch.clone();
                map.columns[1].selected_alternative = Some(index);
                branch_map(&map, &look, &measure)
            };
            let first_branch = picked(0);
            let lower_branch = picked(3);
            let first_branch_row = row(&first_branch, ipc::PointerTarget::Alternative { index: 0 });
            let lower_branch_row = row(&lower_branch, ipc::PointerTarget::Alternative { index: 3 });
            let note = |word: &str, meaning: &str, example: &str| HomophoneNote {
                word: word.into(),
                part_of_speech: Some(PartOfSpeech::Verb),
                senses: vec![HomophoneSense {
                    meaning: meaning.into(),
                    example: Some(example.into()),
                }],
                others: strings(&["執る", "捕る"]),
            };
            let took = note("取る", "手に持つ", "本を手に取る");
            let adopted = note("採る", "選んで用いる", "新人を採る");
            let first_branch_bubble = bubble::bubble(&took, took.others.clone(), &look, &measure);
            let lower_branch_bubble =
                bubble::bubble(&adopted, adopted.others.clone(), &look, &measure);
            // (名前，候補の窓，選んでいる行，吹き出し，画面の大きさ，候補の窓の位置)
            let cases = [
                (
                    "list-right",
                    &list_scene,
                    list_row,
                    &shown,
                    (900.0, 320.0),
                    (40.0, 40.0),
                ),
                (
                    "list-left",
                    &list_scene,
                    list_row,
                    &shown,
                    (900.0, 320.0),
                    (560.0, 40.0),
                ),
                (
                    "list-lower",
                    &last_scene,
                    last_row,
                    &last_bubble,
                    (900.0, 320.0),
                    (40.0, 40.0),
                ),
                (
                    "branch-first",
                    &first_branch,
                    first_branch_row,
                    &first_branch_bubble,
                    (1000.0, 340.0),
                    (40.0, 40.0),
                ),
                (
                    "branch-lower",
                    &lower_branch,
                    lower_branch_row,
                    &lower_branch_bubble,
                    (1000.0, 340.0),
                    (40.0, 40.0),
                ),
                (
                    "list-bottom",
                    &last_scene,
                    last_row,
                    &last_bubble,
                    (900.0, 320.0),
                    (40.0, 320.0 - last_scene.height - 8.0),
                ),
                (
                    "branch-right",
                    &branch_scene,
                    branch_row,
                    &branch_bubble,
                    (1000.0, 340.0),
                    (40.0, 40.0),
                ),
                (
                    "branch-left",
                    &branch_scene,
                    branch_row,
                    &branch_bubble,
                    (1000.0, 340.0),
                    (520.0, 40.0),
                ),
            ];
            for (kind, window, selected, shown, (width, height), (x, y)) in cases {
                let metrics = bubble::Metrics::tokens(theme.is_rounded());
                let keep_clear: Vec<Frame> = window
                    .keep_clear
                    .iter()
                    .map(|frame| frame.offset(x, y))
                    .collect();
                let placement = bubble::place(
                    selected.offset(x, y),
                    window.body.offset(x, y),
                    (shown.width, shown.height),
                    Frame::new(0.0, 0.0, width, height),
                    &keep_clear,
                    window
                        .inside
                        .as_ref()
                        .map(|inside| inside.offset(x, y))
                        .as_ref(),
                    &metrics,
                );
                let drawn = bubble::bubble_scene(shown, &placement, &look, &measure);
                let svg = composite(
                    width,
                    height,
                    background,
                    &[
                        (window, x, y, true),
                        (
                            &drawn,
                            placement.window.x - drawn.body.x,
                            placement.window.y - drawn.body.y,
                            false,
                        ),
                    ],
                    &theme,
                    font_size,
                );
                let path =
                    std::path::Path::new(&directory).join(format!("bubble-{kind}-{name}.svg"));
                std::fs::write(path, svg).expect("書き出せる");
            }
        }
    }

    /// 候補の窓の見本(分岐図・文字種の行のある一覧・入力中の候補・予測・モード表示・案内)を，標準のテーマと platinum で SVG に書き出す．
    /// HAJIME_SCENE_SVG=<ディレクトリ> cargo test -p candidate-ui --lib scene::svg -- --ignored
    #[test]
    #[ignore = "見本を書き出すときだけ動かす"]
    fn 窓の見本を書き出す() {
        let Ok(directory) = std::env::var("HAJIME_SCENE_SVG") else {
            return;
        };
        for (name, theme_name, dark) in [
            ("glass-dark", "automatic", true),
            ("platinum", "platinum", false),
        ] {
            let theme = theme(theme_name);
            let font_size = tokens::size::candidate::FONT_SIZE;
            let measure = Approximate {
                theme: &theme,
                font_size,
            };
            let look = Look::new(&theme, font_size);
            let background = if dark {
                Color {
                    red: 0.15,
                    green: 0.15,
                    blue: 0.15,
                    alpha: 1.0,
                }
            } else {
                Color {
                    red: 0.63,
                    green: 0.63,
                    blue: 0.63,
                    alpha: 1.0,
                }
            };
            let suggestion = CandidateList {
                homophone: None,
                meaning_placement: None,
                shows_numbers: Some(false),
                selected_entry: None,
                position: 0,
                entries: list().entries,
                ..list()
            };
            let shown = ipc::Prediction {
                typed: "エピ".into(),
                completion: "ソード".into(),
                key: Some("Tab".into()),
            };
            let correction = ipc::Note {
                tone: ipc::NoteTone::Correction,
                title: "修正".into(),
                subject: Some("オン外します".into()),
                key: Some("Esc".into()),
                key_action: Some("元に戻す".into()),
                text: "修正「オン外します」　Esc 元に戻す".into(),
            };
            // 文字種の行が先頭の一覧(候補の窓の上の余白と足元の並びを見る)
            let variants = CandidateList {
                homophone: None,
                meaning_placement: None,
                variants: ["カタカナ", "全角英数", "半角英数"]
                    .iter()
                    .map(|label| ipc::CandidateVariant {
                        label: (*label).into(),
                        is_available: true,
                    })
                    .collect(),
                ..list()
            };
            let scenes = [
                (
                    "branch",
                    branch_map(&super::super::sample::branch(), &look, &measure),
                ),
                ("list", candidate_list(&variants, &look, &measure)),
                ("suggestion", candidate_list(&suggestion, &look, &measure)),
                ("prediction", prediction(&shown, &look, &measure)),
                ("mode", mode("あ", &look, &measure)),
                ("note", note(&correction, &look, &measure)),
            ];
            for (kind, drawn) in scenes {
                let svg = scene(&drawn, &theme, font_size, background, 16.0);
                let path = std::path::Path::new(&directory).join(format!("{kind}-{name}.svg"));
                std::fs::write(path, svg).expect("書き出せる");
            }
        }
    }
}
