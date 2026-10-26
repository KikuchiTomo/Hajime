#![forbid(unsafe_code)]

//! 入力位置の下の案内(macOS の NoteView)とモードの札(ModeIndicatorView)

use super::paint::Painter;
use super::{Frame, Look, Measure, Scene};
use crate::theme::Font;
use tokens::size::{candidate, glass, mode_indicator};

/// 打ち間違いを直したこと・「もしかして」を知らせる 1 行
pub fn note(text: &str, look: &Look, measure: &dyn Measure) -> Scene {
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
    let width = (painter.width(text, Font::Note) + (padding + inset) * 2.0).ceil();
    let height = glass::FOOTER_HEIGHT
        .max(measure.height(Font::Note) + (candidate::SECTION_PADDING_Y + inset) * 2.0)
        .ceil();
    let body = Frame::new(0.0, 0.0, width, height);
    painter.panel(body);
    painter.centered(text, Font::Note, look.theme.correction, body);
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

    #[test]
    fn 案内は補正の色で中央に出す() {
        let theme = theme("washi");
        let scene = note("もしかして", &Look::new(&theme, 15.0), &Fixed);
        let frame = text_frame(&scene, "もしかして");
        assert_eq!(frame.map(|frame| frame.x), Some(glass::PADDING));
        assert!(texts(&scene).contains(&("もしかして".into(), theme.correction)));
    }
}
