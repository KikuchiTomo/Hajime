//! 結果の知らせ(WinUI 3 の InfoBar)．取り込み・書き出し・保存の結果や，できなかった理由をページの下に出す．
//! 窓の外に出る MessageBox と違い，設定の窓の中に出て，閉じるまで残る(次の知らせで置き換わり，ページを移ると消える)．
//! はい・いいえを選ばせる確認だけは MessageBox のまま(ffi::confirm・ffi::ask．設定の窓の真ん中に出す)

use super::paint::{self, ButtonKind, Canvas, Measure, State, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use crate::layout::Rect;
use tokens::size::settings_windows as size;
use tokens::size::space;

/// 知らせの中身
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notice {
    pub text: String,
    /// できなかった・気を付けてほしい知らせ(警告の印．ほかは情報の印)
    pub warning: bool,
}

/// 知らせの帯の置き場所(窓の中のタイトルバーの下の座標，DIP)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NoticeLayout {
    pub bar: Rect,
    pub icon: Rect,
    pub text: Rect,
    pub close: Rect,
}

impl NoticeLayout {
    /// ページの列(x・幅)の下の端(bottom)の上に置く．文が長ければ折り返して帯を高くする
    pub fn new(x: f32, width: f32, bottom: f32, notice: &Notice, measure: &dyn Measure) -> Self {
        let padding = size::CARD_PADDING_X;
        let icon_size = size::ICON_FONT_SIZE;
        let button = size::CONTROL_HEIGHT;
        let text_x = x + padding + icon_size + space::SECTION;
        let close_x = x + width - space::GROUP - button;
        let text_width = (close_x - space::GROUP - text_x).max(0.0);
        let text_height = measure
            .wrapped_height(&notice.text, TextStyle::Body, text_width)
            .max(size::BODY_LINE_HEIGHT)
            .ceil();
        // 1 行なら閉じるボタンの高さに上下の余白を足した高さ(InfoBar の 48)．長い文は伸ばす
        let first_line = (button - size::BODY_LINE_HEIGHT) / 2.0;
        let content = (first_line + text_height + first_line).max(button);
        let height = content + space::GROUP * 2.0;
        let bar = Rect::new(x, bottom - space::SECTION - height, width, height);
        let top = bar.y + space::GROUP;
        Self {
            bar,
            icon: Rect::new(x + padding, top, icon_size, button),
            text: Rect::new(text_x, top + first_line, text_width, text_height),
            close: Rect::new(close_x, top, button, button),
        }
    }

    /// 帯がページから取る高さ(上下の間を含む)．ページはこの分だけ上で送る
    pub fn reserved(&self) -> f32 {
        self.bar.height + space::SECTION * 2.0
    }
}

/// 帯を描く(カードの背景と枠線，情報か警告の印，文，閉じるボタン)
pub fn paint(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    notice: &Notice,
    layout: &NoticeLayout,
    close: State,
) {
    let palette = &theme.palette;
    canvas.fill_round(layout.bar, size::CARD_RADIUS, Color::from(palette.card));
    canvas.stroke_round(
        layout.bar,
        size::CARD_RADIUS,
        1.0,
        Color::from(palette.card_stroke),
    );
    let (glyph, tone) = if notice.warning {
        (theme.glyphs.warning, palette.caution)
    } else {
        (theme.glyphs.info, palette.accent)
    };
    canvas.text(
        layout.icon,
        glyph,
        TextStyle::Icon,
        Color::from(tone),
        TextLayout::CENTER,
    );
    canvas.text(
        layout.text,
        &notice.text,
        TextStyle::Body,
        Color::from(palette.text),
        TextLayout::WRAP,
    );
    paint::button(
        canvas,
        theme,
        layout.close,
        theme.glyphs.close,
        ButtonKind::Quiet,
        close,
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixed;

    impl Measure for Fixed {
        fn width(&self, text: &str, _: TextStyle) -> f32 {
            text.chars().count() as f32 * 10.0
        }
        fn wrapped_height(&self, text: &str, _: TextStyle, width: f32) -> f32 {
            let lines = (text.chars().count() as f32 * 10.0 / width).ceil().max(1.0);
            lines * size::BODY_LINE_HEIGHT
        }
        fn baseline(&self, _: &str, _: TextStyle) -> f32 {
            16.0
        }
    }

    fn notice(text: &str) -> Notice {
        Notice {
            text: text.into(),
            warning: false,
        }
    }

    #[test]
    fn 帯はページの列の下に置き_閉じるボタンと文は帯に収まる() {
        let layout = NoticeLayout::new(40.0, 600.0, 700.0, &notice("3 単語を追加しました"), &Fixed);
        assert_eq!(layout.bar.x, 40.0);
        assert_eq!(layout.bar.width, 600.0);
        assert_eq!(layout.bar.max_y(), 700.0 - space::SECTION);
        // 1 行なら InfoBar と同じ 48 の高さ
        assert_eq!(layout.bar.height, size::CONTROL_HEIGHT + space::GROUP * 2.0);
        for rect in [layout.icon, layout.text, layout.close] {
            assert!(rect.x >= layout.bar.x && rect.max_x() <= layout.bar.max_x());
            assert!(rect.y >= layout.bar.y && rect.max_y() <= layout.bar.max_y());
        }
        assert!(layout.text.max_x() < layout.close.x);
        assert_eq!(layout.reserved(), layout.bar.height + space::SECTION * 2.0);
    }

    #[test]
    fn 長い文は折り返して帯を高くする() {
        let short = NoticeLayout::new(0.0, 400.0, 700.0, &notice("短い"), &Fixed);
        let long = NoticeLayout::new(0.0, 400.0, 700.0, &notice(&"長".repeat(80)), &Fixed);
        assert!(long.bar.height > short.bar.height);
        assert!(long.text.max_y() <= long.bar.max_y());
        assert_eq!(long.bar.max_y(), short.bar.max_y());
    }
}
