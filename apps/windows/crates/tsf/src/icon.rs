#![forbid(unsafe_code)]

//! タスクバーの入力モードの表示(「あ」「A」)の形．macOS の入力メニューのアイコン(tools/icons/make_input_icons.swift)と同じく，
//! 角丸の面を塗って字を抜き，右下の角だけ丸めない(分岐図の幹から枝が出る角に見立てる)．
//! 字の形は OS の書体で描いたもの(覆う割合)を受け取り，ここでは面と合わせるだけにする

/// 16 を 1 としたときの寸法(make_input_icons.swift と同じ比)
const CANVAS: f32 = 16.0;
const RADIUS: f32 = 3.5;
/// 字の大きさ．大きめで細い字にし，字の周りに面が見えるようにする
const HIRAGANA_SIZE: f32 = 11.5;
const LATIN_SIZE: f32 = 12.0;
/// 面の縁をなめらかにするために 1 ピクセルを何×何に分けて調べるか
const SAMPLES: usize = 4;

/// 字の高さ(ピクセル)．英字は少し大きくする
pub fn glyph_size(text: &str, height: i32) -> i32 {
    let size = if text.is_ascii() {
        LATIN_SIZE
    } else {
        HIRAGANA_SIZE
    };
    (height as f32 * size / CANVAS).round() as i32
}

/// 面が各ピクセルを覆う割合(0.0〜1.0．行ごとに並べる)
pub fn plate_coverage(width: usize, height: usize) -> Vec<f32> {
    let radius = RADIUS * height as f32 / CANVAS;
    let mut coverage = Vec::with_capacity(width * height);
    for y in 0..height {
        for x in 0..width {
            let mut inside = 0;
            for sy in 0..SAMPLES {
                for sx in 0..SAMPLES {
                    let px = x as f32 + (sx as f32 + 0.5) / SAMPLES as f32;
                    let py = y as f32 + (sy as f32 + 0.5) / SAMPLES as f32;
                    if in_plate(px, py, width as f32, height as f32, radius) {
                        inside += 1;
                    }
                }
            }
            coverage.push(inside as f32 / (SAMPLES * SAMPLES) as f32);
        }
    }
    coverage
}

/// 点が面の中か．右下の角だけ丸めない
fn in_plate(x: f32, y: f32, width: f32, height: f32, radius: f32) -> bool {
    let left = x < radius;
    let right = x > width - radius;
    let top = y < radius;
    let bottom = y > height - radius;
    let corner = match (left, right, top, bottom) {
        (true, _, true, _) => Some((radius, radius)),
        (_, true, true, _) => Some((width - radius, radius)),
        (true, _, _, true) => Some((radius, height - radius)),
        _ => None,
    };
    corner.is_none_or(|(cx, cy)| (x - cx).powi(2) + (y - cy).powi(2) <= radius * radius)
}

/// 字の覆う割合(0〜255)を，字面(覆っている範囲)が面の中央に来るよう動かす
pub fn centered(glyph: &[u8], width: usize, height: usize) -> Vec<u8> {
    let mut bounds: Option<(usize, usize, usize, usize)> = None;
    for y in 0..height {
        for x in 0..width {
            if glyph.get(y * width + x).copied().unwrap_or(0) > 0 {
                bounds = Some(match bounds {
                    None => (x, y, x, y),
                    Some((left, top, right, bottom)) => {
                        (left.min(x), top.min(y), right.max(x), bottom.max(y))
                    }
                });
            }
        }
    }
    let Some((left, top, right, bottom)) = bounds else {
        return glyph.to_vec();
    };
    // 字面の中心と面の中心の差(ピクセル単位に丸める)
    let dx = ((width as f32 - (right + left + 1) as f32) / 2.0).round() as isize;
    let dy = ((height as f32 - (bottom + top + 1) as f32) / 2.0).round() as isize;
    let mut moved = vec![0; width * height];
    for y in 0..height {
        for x in 0..width {
            let from_x = x as isize - dx;
            let from_y = y as isize - dy;
            if (0..width as isize).contains(&from_x) && (0..height as isize).contains(&from_y) {
                moved[y * width + x] = glyph[from_y as usize * width + from_x as usize];
            }
        }
    }
    moved
}

/// 面から字を抜いた不透明度(0〜255)
pub fn compose(plate: &[f32], glyph: &[u8]) -> Vec<u8> {
    plate
        .iter()
        .zip(glyph)
        .map(|(plate, glyph)| {
            let opacity = plate * (1.0 - f32::from(*glyph) / 255.0);
            (opacity * 255.0).round().clamp(0.0, 255.0) as u8
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 右下の角だけ丸めない() {
        let size = 16;
        let plate = plate_coverage(size, size);
        let at = |x: usize, y: usize| plate[y * size + x];
        // 丸めた角の隅は覆わない
        assert_eq!(at(0, 0), 0.0);
        assert_eq!(at(size - 1, 0), 0.0);
        assert_eq!(at(0, size - 1), 0.0);
        // 右下の隅は覆う
        assert_eq!(at(size - 1, size - 1), 1.0);
        // 真ん中は覆う
        assert_eq!(at(8, 8), 1.0);
        // 丸めた角の縁は途中の濃さになる
        assert!(at(1, 0) > 0.0 && at(1, 0) < 1.0);
    }

    #[test]
    fn 字を抜いたところは透ける() {
        let plate = vec![1.0, 1.0, 0.5];
        let glyph = vec![0, 255, 0];
        assert_eq!(compose(&plate, &glyph), vec![255, 0, 128]);
    }

    #[test]
    fn 字面を中央にそろえる() {
        // 4×4 の左上に 1 ピクセルの字
        let mut glyph = vec![0; 16];
        glyph[0] = 200;
        let moved = centered(&glyph, 4, 4);
        // 中心は (1.5, 1.5) か (2, 2) に丸まる
        assert_eq!(moved.iter().filter(|value| **value == 200).count(), 1);
        let position = moved.iter().position(|value| *value == 200);
        assert!(matches!(position, Some(5 | 10)));
        // 字が無ければそのまま
        assert_eq!(centered(&[0; 4], 2, 2), vec![0; 4]);
    }

    #[test]
    fn 英字は少し大きく描く() {
        assert_eq!(glyph_size("あ", 16), 12);
        assert_eq!(glyph_size("A", 16), 12);
        assert!(glyph_size("A", 32) > glyph_size("あ", 32));
    }
}
