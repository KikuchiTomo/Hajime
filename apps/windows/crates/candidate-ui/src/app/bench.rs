//! 候補の窓の 1 回の描き直し(refresh)にかかる時間を測る．ふだんのテストでは動かさない．
//!
//! 使い方: cargo test --release -p candidate-ui --lib bench -- --ignored --nocapture

use super::render::Renderer;
use super::system;
use crate::scene::{self, Look, Surround};
use crate::theme::ResolvedTheme;
use ipc::{CandidateEntry, CandidateFocus, CandidateList, CandidateVariant, KeyHint};
use std::time::{Duration, Instant};
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_PIXEL_FORMAT,
};
use windows::Win32::Graphics::Direct2D::D2D1_RENDER_TARGET_PROPERTIES;
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_WICPixelFormat32bppPBGRA, IWICImagingFactory,
    WICBitmapCacheOnLoad,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
};

/// 打つたびに変わる候補の並び(読みが 1 字ずつ伸びる)
const WORDS: [&str; 8] = [
    "変換",
    "返還",
    "偏官",
    "へんかん",
    "ヘンカン",
    "変換する",
    "返還した",
    "変換候補",
];

fn list(step: usize) -> CandidateList {
    let entries = (0..9)
        .map(|index| CandidateEntry {
            text: format!(
                "{}{}",
                WORDS[(step + index) % WORDS.len()],
                "ー".repeat(step % 5)
            ),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
        })
        .collect();
    CandidateList {
        association: None,
        association_hint: None,
        association_key: None,
        homophone: None,
        shows_numbers: None,
        variants: ["そのまま", "カタカナ", "ｶﾀｶﾅ", "全角英数", "半角英数"]
            .into_iter()
            .map(|label| CandidateVariant {
                label: label.into(),
                is_available: true,
            })
            .collect(),
        selected_variant: None,
        entries,
        selected_entry: step.is_multiple_of(2).then_some((step % 9) as u32),
        focus: CandidateFocus::Candidate,
        position: (step % 9) as u32 + 1,
        total: 30,
        note: None,
        meaning_placement: None,
        hints: Some(vec![KeyHint {
            keys: "Shift+Space".into(),
            label: "文字種".into(),
        }]),
    }
}

fn per_call(total: Duration, count: u32) -> f64 {
    total.as_secs_f64() * 1e6 / f64::from(count)
}

#[test]
#[ignore = "時間を測るだけ(--ignored で動かす)"]
fn bench_refresh() {
    // SAFETY: このスレッドで COM を使う前に呼ぶ
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    // SAFETY: WIC の工場を作る
    let imaging: IWICImagingFactory =
        unsafe { CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER) }.unwrap();
    let renderer = Renderer::new().unwrap();
    let rounds = 400u32;
    let (mut look_time, mut measure_time, mut scene_time, mut paint_time) = (
        Duration::ZERO,
        Duration::ZERO,
        Duration::ZERO,
        Duration::ZERO,
    );
    // SAFETY: 大きさと形式は定まった値
    let bitmap = unsafe {
        imaging.CreateBitmap(
            800,
            600,
            &GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
        )
    }
    .unwrap();
    let properties = D2D1_RENDER_TARGET_PROPERTIES {
        pixelFormat: D2D1_PIXEL_FORMAT {
            format: DXGI_FORMAT_B8G8R8A8_UNORM,
            alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
        },
        ..Default::default()
    };
    // SAFETY: bitmap は作ったばかりの WIC のビットマップ
    let target = unsafe {
        renderer
            .factory()
            .CreateWicBitmapRenderTarget(&bitmap, &properties)
    }
    .unwrap();
    let font_size = tokens::size::candidate::FONT_SIZE;
    // 候補の窓(App)と同じく，読んだ OS の外観を覚えておく
    let mut cache = system::SystemCache::default();
    for step in 0..rounds as usize {
        let start = Instant::now();
        let system_look = cache.look(false);
        let _ = cache.reduce_motion();
        let _ = system::screen_reader();
        look_time += start.elapsed();
        let theme = ResolvedTheme::resolve("automatic", None, &system_look);
        let start = Instant::now();
        let measure = renderer.measure(&theme, font_size).unwrap();
        measure_time += start.elapsed();
        let start = Instant::now();
        let look = Look::new(&theme, font_size);
        let built = scene::candidate_list(&list(step), &look, &measure);
        let built = scene::surround(built, &theme, Surround::Shadow);
        scene_time += start.elapsed();
        let start = Instant::now();
        // SAFETY: BeginDraw と EndDraw を対にする
        unsafe { target.BeginDraw() };
        renderer.paint(&target, &built, &measure, 1.0, 1.0).unwrap();
        // SAFETY: 同上
        unsafe { target.EndDraw(None, None) }.unwrap();
        paint_time += start.elapsed();
    }
    let total = look_time + measure_time + scene_time + paint_time;
    println!(
        "refresh 1 回あたり (µs): system {:.1} / measure {:.1} / scene {:.1} / paint {:.1} / 合計 {:.1}",
        per_call(look_time, rounds),
        per_call(measure_time, rounds),
        per_call(scene_time, rounds),
        per_call(paint_time, rounds),
        per_call(total, rounds),
    );
}

#[test]
#[ignore = "時間を測るだけ(--ignored で動かす)"]
fn bench_chrome() {
    // 出さない窓に，refresh のたびと同じ地と角と縁を書く
    let window = super::window::Window::create(windows_core::w!("hajime.bench"), false).unwrap();
    let border = crate::theme::Color {
        red: 0.5,
        green: 0.5,
        blue: 0.5,
        alpha: 1.0,
    };
    let rounds = 2000u32;
    let start = Instant::now();
    for _ in 0..rounds {
        window.set_chrome(false, true, border);
    }
    println!(
        "set_chrome 1 回あたり (µs): {:.2}",
        per_call(start.elapsed(), rounds)
    );
}
