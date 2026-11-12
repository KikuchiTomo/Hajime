#![forbid(unsafe_code)]

//! 候補ウィンドウ・分岐図・案内・モード表示の中身を，描く順の部品(Draw)の並びにする．
//! 配置と色はここで決め(macOS の CandidateView・BranchView・GlassDrawing と同じ決め方)，描く層(app::render)は部品をなぞるだけにする．
//! そのため，配置と線の座標を Windows でなくても確かめられる

mod association;
mod branch;
mod branch_lines;
pub mod bubble;
mod card_layout;
pub(crate) mod fitting;
mod list;
mod list_layout;
mod meaning;
pub(crate) mod paint;
pub mod sample;
mod small;
#[cfg(test)]
mod svg;

pub use crate::geometry::{Frame, Point};
pub use crate::theme::{Color, Font, ResolvedTheme};
pub use branch::branch_map;
pub use list::candidate_list;
pub use small::{mode, note, prediction};

use crate::keys::Icon;
use tokens::size;

#[derive(Debug, Clone, PartialEq)]
pub enum Draw {
    /// 長方形を塗る
    Rect {
        frame: Frame,
        color: Color,
    },
    /// 角丸の長方形を塗る・縁取る．縁は stroke の太さの線で，frame の上をなぞる
    RoundRect {
        frame: Frame,
        radius: f32,
        fill: Option<Color>,
        stroke: Option<(Color, f32)>,
    },
    Ellipse {
        frame: Frame,
        color: Color,
    },
    /// 多角形を塗る．点を順につなぎ，最後の点から最初の点へ閉じる
    Polygon {
        points: Vec<Point>,
        color: Color,
    },
    /// 3 次ベジェの曲線(端は丸い)
    Curve {
        from: Point,
        control1: Point,
        control2: Point,
        to: Point,
        color: Color,
        width: f32,
    },
    /// 線をつないだ図形(分岐図の幹と枝)．すべての図形をまとめて 1 回でなぞり，重なったところを濃くしない．
    /// 端は平らにし，直角の角は尖らせる
    Path {
        figures: Vec<Figure>,
        color: Color,
        width: f32,
    },
    /// 閉じた図形(吹き出しの形)を塗る・枠線取る．figure の終わりから始まりへ閉じる．枠線は stroke の太さの線で図形の上をなぞる
    Shape {
        figure: Figure,
        fill: Option<Color>,
        stroke: Option<(Color, f32)>,
    },
    /// 直線(端は丸い)．dot_pitch があれば，その間隔の丸い点にする
    Line {
        from: Point,
        to: Point,
        color: Color,
        width: f32,
        dot_pitch: Option<f32>,
    },
    /// キーのアイコン(icon::figures の折れ線を width の線でなぞる)
    Icon {
        icon: Icon,
        frame: Frame,
        color: Color,
        width: f32,
    },
    /// 文字．frame の左端から書き，縦は frame の中央にそろえる
    Text {
        frame: Frame,
        text: String,
        font: Font,
        color: Color,
    },
    /// ぼかした影．frame の角丸の形を blur の幅でぼかす
    Shadow {
        frame: Frame,
        radius: f32,
        blur: f32,
        color: Color,
    },
    /// 中の部品を clip の中だけに，opacity の濃さで描く．scale が 1 でなければ clip の真ん中を中心に大きさを変える
    /// (パレットの印を滑らせる・中身を送る・部品を弾ませる動き)
    Group {
        clip: Frame,
        opacity: f32,
        scale: f32,
        draws: Vec<Draw>,
    },
}

/// start から segments を順につないだ 1 本の線
#[derive(Debug, Clone, PartialEq)]
pub struct Figure {
    pub start: Point,
    pub segments: Vec<Segment>,
}

/// 線の 1 区間．前の区間の終わり(最初は Figure の start)から to まで
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Segment {
    Line(Point),
    /// 半径 radius の円弧(半円より小さい方)．clockwise は y が下へ増える画面で見た向き
    Arc {
        to: Point,
        radius: f32,
        clockwise: bool,
    },
}

impl Figure {
    fn offset(self, dx: f32, dy: f32) -> Self {
        Self {
            start: self.start.offset(dx, dy),
            segments: self
                .segments
                .into_iter()
                .map(|segment| match segment {
                    Segment::Line(to) => Segment::Line(to.offset(dx, dy)),
                    Segment::Arc {
                        to,
                        radius,
                        clockwise,
                    } => Segment::Arc {
                        to: to.offset(dx, dy),
                        radius,
                        clockwise,
                    },
                })
                .collect(),
        }
    }
}

impl Draw {
    /// 部品を dx, dy だけずらす
    pub fn offset(self, dx: f32, dy: f32) -> Self {
        match self {
            Self::Rect { frame, color } => Self::Rect {
                frame: frame.offset(dx, dy),
                color,
            },
            Self::RoundRect {
                frame,
                radius,
                fill,
                stroke,
            } => Self::RoundRect {
                frame: frame.offset(dx, dy),
                radius,
                fill,
                stroke,
            },
            Self::Ellipse { frame, color } => Self::Ellipse {
                frame: frame.offset(dx, dy),
                color,
            },
            Self::Polygon { points, color } => Self::Polygon {
                points: points
                    .into_iter()
                    .map(|point| point.offset(dx, dy))
                    .collect(),
                color,
            },
            Self::Curve {
                from,
                control1,
                control2,
                to,
                color,
                width,
            } => Self::Curve {
                from: from.offset(dx, dy),
                control1: control1.offset(dx, dy),
                control2: control2.offset(dx, dy),
                to: to.offset(dx, dy),
                color,
                width,
            },
            Self::Path {
                figures,
                color,
                width,
            } => Self::Path {
                figures: figures
                    .into_iter()
                    .map(|figure| figure.offset(dx, dy))
                    .collect(),
                color,
                width,
            },
            Self::Shape {
                figure,
                fill,
                stroke,
            } => Self::Shape {
                figure: figure.offset(dx, dy),
                fill,
                stroke,
            },
            Self::Line {
                from,
                to,
                color,
                width,
                dot_pitch,
            } => Self::Line {
                from: from.offset(dx, dy),
                to: to.offset(dx, dy),
                color,
                width,
                dot_pitch,
            },
            Self::Icon {
                icon,
                frame,
                color,
                width,
            } => Self::Icon {
                icon,
                frame: frame.offset(dx, dy),
                color,
                width,
            },
            Self::Text {
                frame,
                text,
                font,
                color,
            } => Self::Text {
                frame: frame.offset(dx, dy),
                text,
                font,
                color,
            },
            Self::Shadow {
                frame,
                radius,
                blur,
                color,
            } => Self::Shadow {
                frame: frame.offset(dx, dy),
                radius,
                blur,
                color,
            },
            Self::Group {
                clip,
                opacity,
                scale,
                draws,
            } => Self::Group {
                clip: clip.offset(dx, dy),
                opacity,
                scale,
                draws: draws.into_iter().map(|draw| draw.offset(dx, dy)).collect(),
            },
        }
    }
}

/// 描く部品の並び．width・height はウィンドウの大きさ，body はその中の候補ウィンドウの本体(影や余白を除いた部分)．
/// hits はマウスで押せる範囲と押したときの対象．描く位置と同じ計算で決める．
/// keep_clear は語の意味の吹き出しに覆わせない範囲(選んでいない候補・幹の文節・足元の案内など)
#[derive(Debug, Clone, PartialEq)]
pub struct Scene {
    pub width: f32,
    pub height: f32,
    pub body: Frame,
    pub draws: Vec<Draw>,
    pub hits: Vec<Hit>,
    pub keep_clear: Vec<Frame>,
}

/// マウスで押せる範囲と，押したときの対象(macOS の BranchView・CandidateView の target(at:) と同じ)
#[derive(Debug, Clone, PartialEq)]
pub struct Hit {
    pub frame: Frame,
    pub target: ipc::PointerTarget,
}

impl Scene {
    /// (x, y)(場面の座標)を押したときの対象．押せる範囲の外なら None
    pub fn target_at(&self, x: f32, y: f32) -> Option<ipc::PointerTarget> {
        self.hits
            .iter()
            .find(|hit| {
                x >= hit.frame.x
                    && x < hit.frame.max_x()
                    && y >= hit.frame.y
                    && y < hit.frame.max_y()
            })
            .map(|hit| hit.target.clone())
    }
}

/// 一覧の候補のタグに出したユーザー辞書の語のコメント(長ければ先頭だけ)．タグがコメントでなければ None
pub fn entry_comment(entry: &ipc::CandidateEntry) -> Option<&str> {
    if entry.has_comment == Some(true) {
        entry.annotation.as_deref()
    } else {
        None
    }
}

/// 分岐図の下の枝の index 番目の候補に添えたユーザー辞書の語のコメント(macOS の LatticePanel.Column.comment(at:))．コメントでなければ None
pub fn alternative_comment(column: &ipc::BranchColumn, index: usize) -> Option<&str> {
    let comments = column.alternative_comments.as_ref()?;
    if comments.get(index).copied() == Some(true) {
        column.alternative_notes.get(index)?.as_deref()
    } else {
        None
    }
}

/// 文字の幅と高さを測る．描く層が OS の書体で測る
pub trait Measure {
    fn width(&self, text: &str, font: Font) -> f32;
    fn height(&self, font: Font) -> f32;

    /// text を 1 行に並べたときの行の高さと，行の上の端からベースラインまで．
    /// 書体の代わりに使う字(日本語の字など)があると行の高さが変わるので，文字ごとに測る．
    /// 描くとき(Draw::Text)は，枠の高さをこの行の高さにすると，枠の上の端からこの位置にベースラインが来る
    fn line(&self, text: &str, font: Font) -> (f32, f32) {
        let _ = text;
        let height = self.height(font);
        (height, (height * 0.75).round())
    }

    /// font の書体に glyph の字があるか(パレットのアイコン)．無ければ代わりの文字を描く
    fn has_glyph(&self, _font: Font, _glyph: char) -> bool {
        false
    }

    /// text を，幅 width(text)・高さ line(text).0 の枠の左上に描いたときの実際の外形(ink)．枠の左上からの位置．
    /// 絵文字を箱の真ん中に置くのに使う(行の箱で真ん中に置くと，字面が行の中で寄っている分だけ余白がずれる)．測れなければ None
    fn ink(&self, _text: &str, _font: Font) -> Option<Frame> {
        None
    }
}

/// 描く層が使い回す書体の組(Rc で共有する)も，そのまま測るのに使う
impl<T: Measure + ?Sized> Measure for std::rc::Rc<T> {
    fn width(&self, text: &str, font: Font) -> f32 {
        (**self).width(text, font)
    }

    fn height(&self, font: Font) -> f32 {
        (**self).height(font)
    }

    fn line(&self, text: &str, font: Font) -> (f32, f32) {
        (**self).line(text, font)
    }

    fn has_glyph(&self, font: Font, glyph: char) -> bool {
        (**self).has_glyph(font, glyph)
    }

    fn ink(&self, text: &str, font: Font) -> Option<Frame> {
        (**self).ink(text, font)
    }
}

/// どう描くか．テーマと文字の大きさと，出し始めの濃さ
#[derive(Debug, Clone, Copy)]
pub struct Look<'a> {
    pub theme: &'a ResolvedTheme,
    pub font_size: f32,
    /// 第 1 候補と選んでいる候補以外の濃さ(0〜1)．出した直後は薄くし，すぐに濃くする
    pub rest_opacity: f32,
    /// 窓の大きさ(影の分を含む)を外から決める．窓の大きさが変わる途中に，地と縁をその大きさで描く．
    /// 中身は中身に合わせた配置のまま描き，はみ出した分は窓で切れる．None なら中身に合わせる
    pub size: Option<(f32, f32)>,
    /// 1 ドットあたりのデバイスのピクセル数(画面の DPI の倍率)．枝の線の縁をデバイスのピクセルの境にそろえるのに使う
    pub pixel_scale: f32,
    /// 候補の一覧の足元の行(案内と位置)を出すか．設定の画面の見本では出さない
    pub shows_footer: bool,
}

impl<'a> Look<'a> {
    pub fn new(theme: &'a ResolvedTheme, font_size: f32) -> Self {
        Self {
            theme,
            font_size: font_size.clamp(
                size::candidate::FONT_SIZE_MIN,
                size::candidate::FONT_SIZE_MAX,
            ),
            rest_opacity: 1.0,
            size: None,
            pixel_scale: 1.0,
            shows_footer: true,
        }
    }

    /// 中身に合わせた窓の大きさ(width, height)を，外から決めた大きさがあればそれにする
    pub(super) fn sized(&self, width: f32, height: f32) -> (f32, f32) {
        self.size.unwrap_or((width, height))
    }
}

/// 本体のまわりに付けるもの
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Surround {
    /// 何も付けない(地のすりガラスと影を OS が描くとき)
    Bare,
    /// 角丸のテーマに，ぼかした窓の影を付ける
    Shadow,
    /// 見本の画像．影の代わりに余白を付けて下地の上に置く(macOS の SnapshotRenderer と同じ)
    Snapshot { dark: bool },
}

/// 本体のまわりに影や余白を付け，ウィンドウの大きさにする
pub fn surround(scene: Scene, theme: &ResolvedTheme, surround: Surround) -> Scene {
    let (margin_x, margin_top, margin_bottom, mut prefix) = match surround {
        Surround::Bare => return scene,
        Surround::Shadow if !theme.is_rounded() || theme.backdrop => return scene,
        Surround::Shadow => {
            let blur = size::glass::SHADOW_RADIUS;
            let offset = size::glass::SHADOW_OFFSET_Y;
            let shadow = Draw::Shadow {
                frame: Frame::new(blur, blur + offset, scene.body.width, scene.body.height),
                radius: theme.corner_radius,
                blur,
                color: Color::rgb(tokens::GLASS_SHADOW).with_alpha(tokens::opacity::shadow::WINDOW),
            };
            (blur, blur, blur + offset, vec![shadow])
        }
        Surround::Snapshot { .. } => {
            let margin = size::snapshot::MARGIN;
            (margin, margin, margin, Vec::new())
        }
    };
    let width = scene.width + margin_x * 2.0;
    let height = scene.height + margin_top + margin_bottom;
    if let Surround::Snapshot { dark } = surround {
        let ground = if dark {
            tokens::GLASS_SNAPSHOT_DARK
        } else {
            tokens::GLASS_SNAPSHOT_LIGHT
        };
        prefix.push(Draw::Rect {
            frame: Frame::new(0.0, 0.0, width, height),
            color: Color::rgb(ground),
        });
    }
    prefix.extend(
        scene
            .draws
            .into_iter()
            .map(|draw| draw.offset(margin_x, margin_top)),
    );
    Scene {
        width,
        height,
        body: scene.body.offset(margin_x, margin_top),
        draws: prefix,
        hits: scene
            .hits
            .into_iter()
            .map(|hit| Hit {
                frame: hit.frame.offset(margin_x, margin_top),
                target: hit.target,
            })
            .collect(),
        keep_clear: scene
            .keep_clear
            .into_iter()
            .map(|frame| frame.offset(margin_x, margin_top))
            .collect(),
    }
}

#[cfg(test)]
pub(crate) mod testing {
    use super::*;
    use crate::theme::SystemLook;

    /// 書体の大きさで幅を測り，書体ごとに行の高さとベースラインを変える(ベースラインで合わせないと縦がそろわない)．
    /// 日本語の字を含む行は，代わりの書体で行が高くなるものとして測る
    pub struct Uneven;

    impl Uneven {
        fn size(font: Font) -> f32 {
            match font {
                Font::Sized(_, points) => f32::from(points),
                _ => 12.0,
            }
        }
    }

    impl Measure for Uneven {
        fn width(&self, text: &str, font: Font) -> f32 {
            text.chars()
                .map(|c| if c.is_ascii() { 0.6 } else { 1.0 } * Self::size(font))
                .sum()
        }

        fn height(&self, font: Font) -> f32 {
            (Self::size(font) * 1.3).round()
        }

        fn line(&self, text: &str, font: Font) -> (f32, f32) {
            let tall = if text.is_ascii() { 0.0 } else { 2.0 };
            (
                self.height(font) + tall,
                (Self::size(font) * 0.95).round() + tall / 2.0,
            )
        }
    }

    /// 文字 1 つを 10 ドットとして測る
    pub struct Fixed;

    impl Measure for Fixed {
        fn width(&self, text: &str, _font: Font) -> f32 {
            text.chars().count() as f32 * 10.0
        }

        fn height(&self, _font: Font) -> f32 {
            12.0
        }
    }

    pub fn theme(name: &str) -> ResolvedTheme {
        ResolvedTheme::resolve(name, None, &SystemLook::default())
    }

    /// 部品を，まとめた部品(Draw::Group)の中も含めて描く順に並べる
    pub fn flattened(draws: &[Draw]) -> Vec<&Draw> {
        let mut all = Vec::new();
        for draw in draws {
            all.push(draw);
            if let Draw::Group { draws, .. } = draw {
                all.extend(flattened(draws));
            }
        }
        all
    }

    pub fn texts(scene: &Scene) -> Vec<(String, Color)> {
        flattened(&scene.draws)
            .into_iter()
            .filter_map(|draw| match draw {
                Draw::Text { text, color, .. } => Some((text.clone(), *color)),
                _ => None,
            })
            .collect()
    }

    pub fn text_frame(scene: &Scene, wanted: &str) -> Option<Frame> {
        flattened(&scene.draws)
            .into_iter()
            .find_map(|draw| match draw {
                Draw::Text { text, frame, .. } if text == wanted => Some(*frame),
                _ => None,
            })
    }

    pub fn count(scene: &Scene, matches: impl Fn(&Draw) -> bool) -> usize {
        flattened(&scene.draws)
            .into_iter()
            .filter(|draw| matches(draw))
            .count()
    }
}

#[cfg(test)]
mod tests {
    use super::testing::*;
    use super::*;
    use crate::theme::SystemLook;

    #[test]
    fn 角丸のテーマには窓の影を付け_本体をずらす() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let bare = mode("あ", &look, &Fixed);
        let shadowed = surround(bare.clone(), &theme, Surround::Shadow);
        let blur = size::glass::SHADOW_RADIUS;
        assert_eq!(shadowed.body.x, blur);
        assert_eq!(shadowed.width, bare.width + blur * 2.0);
        assert!(matches!(shadowed.draws[0], Draw::Shadow { .. }));
        // platinum は影を付けない(desk は本体の中に 2 ドットの影を描く)
        let platinum = super::testing::theme("platinum");
        let flat = mode("あ", &Look::new(&platinum, 15.0), &Fixed);
        assert_eq!(surround(flat.clone(), &platinum, Surround::Shadow), flat);
    }

    #[test]
    fn 窓の大きさを外から決めると_地をその大きさで描き_中身の位置は変えない() {
        for name in ["washi", "platinum", "desk"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let map = sample::branch();
            let natural = branch_map(&map, &look, &Fixed);
            let wider = (natural.width + 40.0, natural.height + 20.0);
            let sized = branch_map(
                &map,
                &Look {
                    size: Some(wider),
                    ..look
                },
                &Fixed,
            );
            assert_eq!((sized.width, sized.height), wider, "{name}");
            assert_eq!(texts(&sized), texts(&natural), "{name}");
            let first = texts(&natural)[0].0.clone();
            assert_eq!(
                text_frame(&sized, &first),
                text_frame(&natural, &first),
                "{name}"
            );
        }
    }

    #[test]
    fn すりガラスの地は_os_が影を描くので付けない() {
        let theme = ResolvedTheme {
            backdrop: true,
            ..ResolvedTheme::resolve("nordic", None, &SystemLook::default())
        };
        let scene = mode("あ", &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(surround(scene.clone(), &theme, Surround::Shadow), scene);
    }

    #[test]
    fn 見本の画像は下地の上に余白を付けて置く() {
        let theme = theme("platinum");
        let scene = mode("A", &Look::new(&theme, 15.0), &Fixed);
        let snapshot = surround(scene.clone(), &theme, Surround::Snapshot { dark: false });
        let margin = size::snapshot::MARGIN;
        assert_eq!(snapshot.width, scene.width + margin * 2.0);
        assert_eq!(
            snapshot.draws[0],
            Draw::Rect {
                frame: Frame::new(0.0, 0.0, snapshot.width, snapshot.height),
                color: Color::rgb(tokens::GLASS_SNAPSHOT_LIGHT)
            }
        );
        assert_eq!(
            text_frame(&snapshot, "A").map(|frame| frame.x),
            text_frame(&scene, "A").map(|frame| frame.x + margin)
        );
    }
}
