#![forbid(unsafe_code)]

//! 入力位置の下の案内(macOS の NoteView)とモードの札(ModeIndicatorView)

use super::paint::Painter;
use super::{Frame, Look, Measure, Scene};
use crate::theme::Font;
use tokens::size::{candidate, glass, mode_indicator};

/// 打ち間違いを直したこと・「もしかして」を知らせる 1 行
pub fn note(note: &ipc::Note, look: &Look, measure: &dyn Measure) -> Scene {
    let mut painter = Painter::new(look, measure);
    let rounded = look.theme.is_rounded();
    let padding = if rounded {
        glass::PADDING
    } else {
        candidate::PADDING_X
    };
    let inset = if rounded {
        0.0
    } else {
        candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH
    };
    let width = (painter.note_width(note) + (padding + inset) * 2.0).ceil();
    let content = glass::NOTE_ICON_SIZE
        .max(glass::KEYCAP_HEIGHT)
        .max(measure.height(Font::Label));
    let height = glass::FOOTER_HEIGHT
        .max(content + (candidate::SECTION_PADDING_Y + inset) * 2.0)
        .ceil();
    let body = Frame::new(0.0, 0.0, width, height);
    painter.panel(body);
    painter.note(note, padding + inset, body.mid_y());
    painter.finish(width, height)
}

/// モードの札(入力モードの「あ」「A」や，切り替えた入力方式)．角丸のテーマは角丸の正方形(文字が長いときは横に伸ばす)，platinum と desk は文字に合わせた札
pub fn mode(label: &str, look: &Look, measure: &dyn Measure) -> Scene {
    let mut painter = Painter::new(look, measure);
    let text_width = measure.width(label, Font::Mode);
    let (width, height) = if look.theme.is_rounded() {
        (
            glass::MODE_INDICATOR_SIZE
                .max(text_width + mode_indicator::PADDING_X * 2.0)
                .ceil(),
            glass::MODE_INDICATOR_SIZE,
        )
    } else {
        let inset = candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH;
        (
            (text_width + mode_indicator::PADDING_X * 2.0 + inset * 2.0).ceil(),
            (measure.height(Font::Mode) + mode_indicator::PADDING_Y * 2.0 + inset * 2.0).ceil(),
        )
    };
    let body = Frame::new(0.0, 0.0, width, height);
    painter.panel(body);
    painter.centered(label, Font::Mode, look.theme.text, body);
    painter.finish(width, height)
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::super::Draw;
    use super::*;

    #[test]
    fn 角丸のテーマのモードの札は正方形() {
        let theme = theme("automatic");
        let scene = mode("あ", &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(scene.width, glass::MODE_INDICATOR_SIZE);
        assert_eq!(scene.height, glass::MODE_INDICATOR_SIZE);
        assert!(texts(&scene).contains(&("あ".into(), theme.text)));
    }

    #[test]
    fn 長い札は横に伸ばす() {
        let theme = theme("automatic");
        let scene = mode("ローマ字", &Look::new(&theme, 15.0), &Fixed);
        assert!(scene.width > glass::MODE_INDICATOR_SIZE);
        assert_eq!(scene.height, glass::MODE_INDICATOR_SIZE);
    }

    #[test]
    fn platinum_のモードの札は立体の縁() {
        let theme = theme("platinum");
        let scene = mode("A", &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(
            scene.draws[0],
            Draw::Rect {
                frame: Frame::new(0.0, 0.0, scene.width, scene.height),
                color: theme.frame
            }
        );
    }

    fn correction_note() -> ipc::Note {
        ipc::Note {
            tone: ipc::NoteTone::Correction,
            title: "修正".into(),
            subject: Some("ようですね".into()),
            key: Some("Esc".into()),
            key_action: Some("戻す".into()),
            text: "修正「ようですね」　Esc 戻す".into(),
        }
    }

    #[test]
    fn 案内はアイコンのあとに主な語を補正の色で出し_直す前の字を薄く取り消す() {
        let theme = theme("washi");
        let scene = note(&correction_note(), &Look::new(&theme, 15.0), &Fixed);
        // 頭のアイコンの丸の右に主な語を置く
        let title = text_frame(&scene, "修正").expect("主な語");
        assert_eq!(
            title.x,
            glass::PADDING + glass::NOTE_ICON_SIZE + glass::NOTE_GAP
        );
        assert!(texts(&scene).contains(&("修正".into(), theme.correction)));
        assert!(texts(&scene).contains(&("ようですね".into(), theme.text_muted)));
        assert!(texts(&scene).contains(&("戻す".into(), theme.text_muted)));
        // 直す前の字には取り消し線を引く
        let subject = text_frame(&scene, "ようですね").expect("直す前の字");
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Rect { frame, color } if *color == theme.text_muted && frame.x == subject.x && frame.height <= 1.0)));
    }

    #[test]
    fn ほかの知らせにはアイコンを付けない() {
        let theme = theme("washi");
        let info = ipc::Note {
            tone: ipc::NoteTone::Info,
            title: "学習から削除しました".into(),
            subject: None,
            key: None,
            key_action: None,
            text: "学習から削除しました".into(),
        };
        let scene = note(&info, &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(
            text_frame(&scene, "学習から削除しました").map(|frame| frame.x),
            Some(glass::PADDING)
        );
        assert!(!scene
            .draws
            .iter()
            .any(|draw| matches!(draw, Draw::Ellipse { .. })));
    }
}
