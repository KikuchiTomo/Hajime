#![forbid(unsafe_code)]

//! 描く順の部品(Draw)を SVG にする(テストだけ)．Windows でなくても窓の見た目を画像にして見比べるのに使う．
//! 文字の幅は書体の大きさから見積もる(日本語の字は 1 字が書体の大きさ，英数字は 0.6 倍)．本物の描画は app::render

use super::{Draw, Frame, Measure, Scene};
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

/// 窓の見た目を SVG にする．地のすりガラスは写せないので，角丸のテーマは窓の地と縁も描く．margin は窓のまわりの空き
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
    use super::super::{branch_map, candidate_list, mode, note, prediction, CardReservation, Look};
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
            // 文字が明るいテーマは暗い地に置く
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
            // 意味のある候補から意味の無い候補に移ったところ(場所を空けたまま)
            let mut reservation = CardReservation::default();
            reservation.list(&list(), &look, &measure);
            let empty = CandidateList {
                homophone: None,
                meaning_placement: None,
                selected_entry: Some(1),
                ..list()
            };
            let empty_look = Look {
                reserved_card: reservation.list(&empty, &look, &measure),
                ..look
            };
            let scenes = [
                ("list", candidate_list(&list(), &look, &measure)),
                ("list-below", candidate_list(&below_list, &look, &measure)),
                ("list-empty", candidate_list(&empty, &empty_look, &measure)),
                ("branch", branch_map(&branch(), &look, &measure)),
                ("branch-below", branch_map(&below_branch, &look, &measure)),
            ];
            for (kind, drawn) in scenes {
                let svg = scene(&drawn, &theme, font_size, background, 16.0);
                let path =
                    std::path::Path::new(&directory).join(format!("meaning-{kind}-{name}.svg"));
                std::fs::write(path, svg).expect("書き出せる");
            }
        }
    }

    /// 候補の窓の見本(分岐図・入力中の候補・予測・モードの札・案内)を，標準のテーマと platinum で SVG に書き出す．
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
                key_action: Some("戻す".into()),
                text: "修正「オン外します」　Esc 戻す".into(),
            };
            let scenes = [
                (
                    "branch",
                    branch_map(&super::super::sample::branch(), &look, &measure),
                ),
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
