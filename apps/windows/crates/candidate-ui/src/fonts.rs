//! カスタムテーマで選ぶ書体(macOS の ThemeFontPicker・InstalledFonts)．
//! 値は選んだ書体の PostScript 名で，macOS と同じ値を指す．古い版で保存したファミリー名(「Meiryo UI」など)もそのファミリーとして読む．
//! 書体の一覧は OS から読む(app::fonts)．ここは一覧から選ぶ決まりだけを持ち，OS に依らない

use std::collections::HashMap;

/// 入っている書体 1 つ
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstalledFace {
    /// 書体を作るときに渡すファミリーの名前(英語の名前)
    pub family: String,
    /// 画面に出すファミリーの名前(日本語の名前があればそれ)
    pub family_label: String,
    pub postscript: String,
    /// 画面に出すスタイルの名前(「Bold」など)
    pub label: String,
    /// 太さ(100〜950．400 が標準)
    pub weight: u32,
    pub italic: bool,
    /// 幅(1〜9．5 が標準)
    pub stretch: u32,
}

/// 保存した値が指す書体
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Selection<'a> {
    /// PostScript 名で選んだ書体
    Face(&'a InstalledFace),
    /// ファミリーの名前(古い版で保存した値)．太さは用途ごとに決める
    Family(&'a str),
}

impl Selection<'_> {
    pub fn family(&self) -> &str {
        match self {
            Self::Face(face) => &face.family,
            Self::Family(family) => family,
        }
    }
}

/// 標準の太さ
const STANDARD_WEIGHT: u32 = 400;
/// 斜体の違いは太さの違いより大きく数える
const ITALIC_DISTANCE: u32 = 1000;

/// ファミリーの一覧(ファミリーの名前と画面に出す名前)．画面に出す名前の順
pub fn families(faces: &[InstalledFace]) -> Vec<(&str, &str)> {
    let mut families: Vec<(&str, &str)> = faces
        .iter()
        .map(|face| (face.family.as_str(), face.family_label.as_str()))
        .collect();
    families.sort_by_cached_key(|(family, label)| (label.to_lowercase(), *family));
    families.dedup_by(|lhs, rhs| lhs.0 == rhs.0);
    families
}

/// ファミリーの中の書体．細いものから
pub fn faces_of<'a>(faces: &'a [InstalledFace], family: &str) -> Vec<&'a InstalledFace> {
    let mut members: Vec<&InstalledFace> = faces
        .iter()
        .filter(|face| face.family.eq_ignore_ascii_case(family))
        .collect();
    members.sort_by_key(|face| (face.weight, face.italic, face.stretch));
    members
}

/// 保存した値の書体．PostScript 名を先に探し，無ければファミリーの名前として探す．入っていなければ None
pub fn find<'a>(faces: &'a [InstalledFace], value: &str) -> Option<Selection<'a>> {
    if value.is_empty() {
        return None;
    }
    if let Some(face) = faces.iter().find(|face| face.postscript == value) {
        return Some(Selection::Face(face));
    }
    faces
        .iter()
        .find(|face| face.family.eq_ignore_ascii_case(value) || face.family_label == value)
        .map(|face| Selection::Family(&face.family))
}

/// ファミリーを選び直したときの書体．今の書体と太さと斜体が近いものを選ぶ．今の書体がなければ標準の太さ
pub fn closest<'a>(
    faces: &'a [InstalledFace],
    family: &str,
    current: Option<Selection<'_>>,
) -> Option<&'a InstalledFace> {
    closest_in(&faces_of(faces, family), current)
}

/// members(同じファミリーの書体)の中で，今の書体と太さと斜体が近いもの
pub fn closest_in<'a>(
    members: &[&'a InstalledFace],
    current: Option<Selection<'_>>,
) -> Option<&'a InstalledFace> {
    let (weight, italic) = match current {
        Some(Selection::Face(face)) => (face.weight, face.italic),
        _ => (STANDARD_WEIGHT, false),
    };
    members.iter().copied().min_by_key(|face| {
        face.weight.abs_diff(weight)
            + if face.italic == italic {
                0
            } else {
                ITALIC_DISTANCE
            }
    })
}

/// ファミリーごとの書体(ファミリーの名前は小文字にそろえる)．選択肢を作るときに 1 度だけまとめる
pub fn by_family(faces: &[InstalledFace]) -> HashMap<String, Vec<&InstalledFace>> {
    let mut groups: HashMap<String, Vec<&InstalledFace>> = HashMap::new();
    for face in faces {
        groups
            .entry(face.family.to_lowercase())
            .or_default()
            .push(face);
    }
    groups
}

#[cfg(test)]
mod tests {
    use super::*;

    fn face(family: &str, postscript: &str, weight: u32, italic: bool) -> InstalledFace {
        InstalledFace {
            family: family.into(),
            family_label: family.into(),
            postscript: postscript.into(),
            label: postscript.into(),
            weight,
            italic,
            stretch: 5,
        }
    }

    fn installed() -> Vec<InstalledFace> {
        vec![
            face("Yu Gothic", "YuGothic-Bold", 700, false),
            face("Yu Gothic", "YuGothic-Regular", 400, false),
            face("Yu Gothic", "YuGothic-Light", 300, false),
            face("Arial", "Arial-ItalicMT", 400, true),
            face("Arial", "ArialMT", 400, false),
            face("Arial", "Arial-BoldMT", 700, false),
        ]
    }

    #[test]
    fn families_are_sorted_and_unique() {
        let faces = installed();
        assert_eq!(
            families(&faces),
            vec![("Arial", "Arial"), ("Yu Gothic", "Yu Gothic")]
        );
    }

    #[test]
    fn faces_are_sorted_by_weight() {
        let faces = installed();
        let names: Vec<&str> = faces_of(&faces, "yu gothic")
            .iter()
            .map(|face| face.postscript.as_str())
            .collect();
        assert_eq!(
            names,
            vec!["YuGothic-Light", "YuGothic-Regular", "YuGothic-Bold"]
        );
    }

    #[test]
    fn finds_postscript_name_then_family() {
        let faces = installed();
        assert!(matches!(
            find(&faces, "YuGothic-Bold"),
            Some(Selection::Face(face)) if face.weight == 700
        ));
        assert_eq!(
            find(&faces, "Yu Gothic"),
            Some(Selection::Family("Yu Gothic"))
        );
        assert_eq!(find(&faces, "Meiryo UI"), None);
        assert_eq!(find(&faces, ""), None);
    }

    #[test]
    fn closest_keeps_weight_and_italic() {
        let faces = installed();
        let bold = find(&faces, "YuGothic-Bold");
        assert_eq!(
            closest(&faces, "Arial", bold).map(|face| face.postscript.as_str()),
            Some("Arial-BoldMT")
        );
        let italic = find(&faces, "Arial-ItalicMT");
        assert_eq!(
            closest(&faces, "Arial", italic).map(|face| face.postscript.as_str()),
            Some("Arial-ItalicMT")
        );
        assert_eq!(
            closest(&faces, "Yu Gothic", None).map(|face| face.postscript.as_str()),
            Some("YuGothic-Regular")
        );
    }
}
