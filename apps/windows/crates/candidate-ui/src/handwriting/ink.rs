#![forbid(unsafe_code)]

/// 書く欄の中の点．書く欄の左上が原点で，単位は DIP
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

/// 線の数と 1 本の線の点の数の上限．押したまま動かし続けても，覚える量が増え続けないように
pub const MAXIMUM_STROKES: usize = 128;
pub const MAXIMUM_POINTS: usize = 4096;

/// 書いた線と，認識した候補．線を書き終えるたびに番号(generation)を進め，古い認識の結果は捨てる
#[derive(Debug, Default)]
pub struct Ink {
    strokes: Vec<Vec<Point>>,
    candidates: Vec<String>,
    is_stroking: bool,
    generation: u64,
}

impl Ink {
    pub fn strokes(&self) -> &[Vec<Point>] {
        &self.strokes
    }

    pub fn candidates(&self) -> &[String] {
        &self.candidates
    }

    pub fn is_empty(&self) -> bool {
        self.strokes.is_empty()
    }

    pub fn is_stroking(&self) -> bool {
        self.is_stroking
    }

    /// 新しい線を始める．上限まで書いていれば始めない
    pub fn begin(&mut self, point: Point) -> bool {
        if self.strokes.len() >= MAXIMUM_STROKES {
            return false;
        }
        self.strokes.push(vec![point]);
        self.is_stroking = true;
        self.generation += 1;
        true
    }

    /// 書いている線を point まで伸ばす．同じ点は足さない
    pub fn extend(&mut self, point: Point) -> bool {
        if !self.is_stroking {
            return false;
        }
        let Some(stroke) = self.strokes.last_mut() else {
            return false;
        };
        if stroke.len() >= MAXIMUM_POINTS || stroke.last() == Some(&point) {
            return false;
        }
        stroke.push(point);
        true
    }

    /// 線を書き終えた．認識に回す番号を返す(書いていなければ None)
    pub fn end(&mut self) -> Option<u64> {
        if !self.is_stroking {
            return None;
        }
        self.is_stroking = false;
        self.generation += 1;
        Some(self.generation)
    }

    /// 今の線で認識を頼むときの番号．この番号の結果だけを受け取る
    pub fn generation(&self) -> u64 {
        self.generation
    }

    /// 認識の結果を受け取る．その後に線が変わっていれば(番号が違えば)捨てる
    pub fn accept(&mut self, generation: u64, candidates: Vec<String>) -> bool {
        if generation != self.generation || self.is_stroking {
            return false;
        }
        self.candidates = candidates;
        true
    }

    pub fn clear(&mut self) {
        self.strokes.clear();
        self.candidates.clear();
        self.is_stroking = false;
        self.generation += 1;
    }
}

/// 認識器が区切りごとに返した候補を 1 つの並びにする．区切りが 1 つならその候補，
/// 複数(続けて書いた字)なら各区切りの第 1 候補をつないだもの
pub fn merge_segments(segments: Vec<Vec<String>>) -> Vec<String> {
    if segments.len() <= 1 {
        return segments.into_iter().next().unwrap_or_default();
    }
    let joined: String = segments
        .iter()
        .filter_map(|candidates| candidates.first().cloned())
        .collect();
    if joined.is_empty() {
        Vec::new()
    } else {
        vec![joined]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn point(x: f32, y: f32) -> Point {
        Point { x, y }
    }

    #[test]
    fn 押して動かして離すと一本の線になる() {
        let mut ink = Ink::default();
        assert!(ink.begin(point(1.0, 1.0)));
        assert!(ink.extend(point(2.0, 2.0)));
        assert!(!ink.extend(point(2.0, 2.0)));
        assert!(ink.end().is_some());
        assert_eq!(ink.strokes(), &[vec![point(1.0, 1.0), point(2.0, 2.0)]]);
        assert!(!ink.extend(point(3.0, 3.0)));
        assert!(ink.end().is_none());
    }

    #[test]
    fn 書き足したあとの古い認識の結果は捨てる() {
        let mut ink = Ink::default();
        ink.begin(point(0.0, 0.0));
        let first = ink.end().unwrap();
        ink.begin(point(5.0, 5.0));
        assert!(!ink.accept(first, vec!["一".into()]));
        let second = ink.end().unwrap();
        assert!(!ink.accept(first, vec!["一".into()]));
        assert!(ink.accept(second, vec!["二".into()]));
        assert_eq!(ink.candidates(), &["二".to_string()]);
    }

    #[test]
    fn 消すと線も候補も無くなり認識の結果も受けない() {
        let mut ink = Ink::default();
        ink.begin(point(0.0, 0.0));
        let generation = ink.end().unwrap();
        ink.clear();
        assert!(ink.is_empty());
        assert!(!ink.accept(generation, vec!["一".into()]));
        assert!(ink.candidates().is_empty());
    }

    #[test]
    fn 線と点の数には上限がある() {
        let mut ink = Ink::default();
        for _ in 0..MAXIMUM_STROKES {
            assert!(ink.begin(point(0.0, 0.0)));
            ink.end();
        }
        assert!(!ink.begin(point(0.0, 0.0)));
        let mut ink = Ink::default();
        ink.begin(point(0.0, 0.0));
        for index in 1..MAXIMUM_POINTS {
            assert!(ink.extend(point(index as f32, 0.0)));
        }
        assert!(!ink.extend(point(-1.0, 0.0)));
    }

    #[test]
    fn 区切りが複数なら第1候補をつなぐ() {
        let one = vec![vec!["鬱".to_string(), "欝".to_string()]];
        assert_eq!(
            merge_segments(one),
            vec!["鬱".to_string(), "欝".to_string()]
        );
        let two = vec![
            vec!["山".to_string(), "出".to_string()],
            vec!["川".to_string()],
        ];
        assert_eq!(merge_segments(two), vec!["山川".to_string()]);
        assert!(merge_segments(Vec::new()).is_empty());
    }
}
