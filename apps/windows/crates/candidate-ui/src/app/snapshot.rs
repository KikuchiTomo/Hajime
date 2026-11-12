//! 候補ウィンドウとパレットの見た目を PNG に書き出す(デバッグビルドだけ)．macOS の SnapshotRenderer と同じ見本・同じ名前で書き出し，
//! 2 つの OS の絵を見比べられるようにする．CI の Windows のジョブが成果物にする
//!
//! 使い方: hajime-candidate-ui.exe --render-snapshots <書き出し先のディレクトリ>

use super::render::Renderer;
use crate::palette::{
    self,
    layout::{cell_size, Fonts, Layout},
};
use crate::scene::{self, CardReservation, Look, Scene, Surround};
use crate::theme::{ResolvedTheme, SystemLook};
use ipc::{
    BranchColumn, BranchMap, BranchSplit, CandidateEntry, CandidateFocus, CandidateList,
    CandidateVariant, Color as WireColor, CustomTheme, HomophoneNote, HomophoneSense, KeyHint,
    MeaningPlacement, PartOfSpeech,
};
use std::path::{Path, PathBuf};
use windows::Win32::Foundation::GENERIC_WRITE;
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_PIXEL_FORMAT,
};
use windows::Win32::Graphics::Direct2D::D2D1_RENDER_TARGET_PROPERTIES;
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows::Win32::Graphics::Imaging::{
    CLSID_WICImagingFactory, GUID_ContainerFormatPng, GUID_WICPixelFormat32bppPBGRA, IWICBitmap,
    IWICImagingFactory, WICBitmapCacheOnLoad, WICBitmapEncoderNoCache,
};
use windows::Win32::System::Com::StructuredStorage::IPropertyBag2;
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED,
};
use windows_core::{Result, HSTRING};

const ARGUMENT: &str = "--render-snapshots";
const BASE_DPI: f32 = 96.0;

/// 引数に --render-snapshots があれば書き出して true を返す
pub fn run_if_requested() -> bool {
    let arguments: Vec<String> = std::env::args().collect();
    let Some(index) = arguments.iter().position(|argument| argument == ARGUMENT) else {
        return false;
    };
    let output = arguments
        .get(index + 1)
        .map_or_else(|| PathBuf::from("snapshots"), PathBuf::from);
    if let Err(error) = render_all(&output) {
        eprintln!("見本を書き出せませんでした: {error}");
        std::process::exit(1);
    }
    true
}

fn color(red: u8, green: u8, blue: u8) -> WireColor {
    WireColor { red, green, blue }
}

/// macOS の見本と同じ色のカスタムテーマ(夕焼け)．書体は Windows に入っているものにする
fn sample_theme() -> CustomTheme {
    CustomTheme {
        base: "automatic".into(),
        surface: color(0x2B, 0x1B, 0x17),
        text: color(0xFF, 0xE8, 0xD6),
        text_muted: color(0xC9, 0xA6, 0x8F),
        selection: color(0xFF, 0x7A, 0x3D),
        selection_text: color(0x1A, 0x0E, 0x0A),
        correction: color(0xFF, 0xD2, 0x3F),
        line: color(0x6B, 0x4A, 0x3E),
        font_name: Some("Meiryo".into()),
        corner_radius: 4.0,
        straight_branches: true,
    }
}

/// 書き出す見た目: 名前・テーマ・ダークか
const LOOKS: [(&str, &str, bool); 10] = [
    ("custom", "automatic", true),
    ("glass-light", "automatic", false),
    ("glass-dark", "automatic", true),
    ("platinum", "platinum", false),
    ("desk", "desk", true),
    ("washi", "washi", false),
    ("neon", "neon", true),
    ("terminal", "terminal", true),
    ("nordic", "nordic", false),
    ("contrast", "contrast", true),
];

fn render_all(output: &Path) -> Result<()> {
    std::fs::create_dir_all(output).map_err(|_| windows_core::Error::from_thread())?;
    // SAFETY: このスレッドで COM を使う前に 1 度だけ呼ぶ
    let _ = unsafe { CoInitializeEx(None, COINIT_MULTITHREADED) };
    // SAFETY: WIC の工場を作る
    let imaging: IWICImagingFactory =
        unsafe { CoCreateInstance(&CLSID_WICImagingFactory, None, CLSCTX_INPROC_SERVER)? };
    let renderer = Renderer::new()?;
    let custom = sample_theme();
    for (name, theme_name, dark) in LOOKS {
        // 見本はすりガラスの地を写せないので，地を塗る(macOS の fillsSurface と同じ)
        let system = SystemLook {
            dark,
            ..SystemLook::default()
        };
        let theme =
            ResolvedTheme::resolve(theme_name, (name == "custom").then_some(&custom), &system);
        let font_size = tokens::size::candidate::FONT_SIZE;
        let measure = renderer.measure(&theme, font_size)?;
        let look = Look::new(&theme, font_size);
        // 意味のある候補から意味の無い候補に移ったところは，前の窓で空けたカードの場所を引き継ぐ(描く層と同じ手順)
        let mut reservation = CardReservation::default();
        reservation.list(&meaning_list(), &look, &measure);
        let empty_list = Look {
            reserved_card: reservation.list(&meaning_empty_list(), &look, &measure),
            ..look
        };
        reservation.branch(
            &homophone_branch(MeaningPlacement::Side, 1),
            &look,
            &measure,
        );
        let empty_branch = Look {
            reserved_card: reservation.branch(
                &homophone_branch(MeaningPlacement::Side, 2),
                &look,
                &measure,
            ),
            ..look
        };
        let scenes: [(&str, Scene); 15] = [
            ("list", scene::candidate_list(&list(), &look, &measure)),
            (
                "homophone-list",
                scene::candidate_list(&homophone_list(MeaningPlacement::Side), &look, &measure),
            ),
            (
                "homophone-list-below",
                scene::candidate_list(&homophone_list(MeaningPlacement::Below), &look, &measure),
            ),
            (
                "meaning-list",
                scene::candidate_list(&meaning_list(), &look, &measure),
            ),
            (
                "meaning-list-empty",
                scene::candidate_list(&meaning_empty_list(), &empty_list, &measure),
            ),
            (
                "homophone-branch",
                scene::branch_map(
                    &homophone_branch(MeaningPlacement::Side, 1),
                    &look,
                    &measure,
                ),
            ),
            (
                "homophone-branch-below",
                scene::branch_map(
                    &homophone_branch(MeaningPlacement::Below, 1),
                    &look,
                    &measure,
                ),
            ),
            (
                "homophone-branch-empty",
                scene::branch_map(
                    &homophone_branch(MeaningPlacement::Side, 2),
                    &empty_branch,
                    &measure,
                ),
            ),
            (
                "command-list",
                scene::candidate_list(&command_list(), &look, &measure),
            ),
            (
                "correction",
                scene::candidate_list(&correction(), &look, &measure),
            ),
            ("branch", scene::branch_map(&lattice(), &look, &measure)),
            (
                "branch-preview",
                scene::branch_map(&preview(), &look, &measure),
            ),
            ("branch-split", scene::branch_map(&split(), &look, &measure)),
            ("mode", scene::mode("あ", &look, &measure)),
            (
                "note",
                scene::note(
                    &ipc::Note {
                        tone: ipc::NoteTone::Correction,
                        title: "修正".into(),
                        subject: Some("オン外します".into()),
                        key: Some("Esc".into()),
                        key_action: Some("戻す".into()),
                        text: "修正「オン外します」　Esc 戻す".into(),
                    },
                    &look,
                    &measure,
                ),
            ),
        ];
        for (kind, scene) in scenes {
            let scene = scene::surround(scene, &theme, Surround::Snapshot { dark });
            let path = output.join(format!("{kind}-{name}.png"));
            write_png(&imaging, &renderer, &scene, &measure, &path)?;
        }
        // 絵文字と記号のパレット(R-26)．macOS の palette-emoji・palette-search・palette-flag・palette-symbol・palette-kaomoji と同じ見本
        for (kind, panel) in [
            ("palette-emoji", palette::sample::emoji()),
            ("palette-search", palette::sample::search()),
            ("palette-flag", palette::sample::flag()),
            ("palette-symbol", palette::sample::symbol()),
            ("palette-kaomoji", palette::sample::kaomoji()),
        ] {
            let fonts = Fonts::new(cell_size(&panel));
            let measure = renderer.measure_with(&theme, font_size, &fonts.all())?;
            let layout = Layout::new(&panel, &theme, &measure);
            let scene = palette::scene::palette(
                &panel,
                &layout,
                &look,
                &measure,
                palette::motion::Tween::default(),
            );
            let scene = scene::surround(scene, &theme, Surround::Snapshot { dark });
            let path = output.join(format!("{kind}-{name}.png"));
            write_png(&imaging, &renderer, &scene, &measure, &path)?;
        }
        // 動きの途中のコマ(macOS の palette-motion-*)．選択の枠とタブの印が滑る・種類を切り替えて中身を送る・肌の色の帯が浮かび上がる
        for (step, (from, to, milliseconds)) in
            palette::sample::motion_steps().into_iter().enumerate()
        {
            let fonts = Fonts::new(cell_size(&to));
            let measure = renderer.measure_with(&theme, font_size, &fonts.all())?;
            let from_layout = Layout::new(&from, &theme, &measure);
            let layout = Layout::new(&to, &theme, &measure);
            let start = std::time::Instant::now();
            let mut motion = palette::motion::Motion::default();
            motion.start(&from, &from_layout, &to, &layout, start);
            let at = start + std::time::Duration::from_secs_f32(milliseconds / 1000.0);
            let tween = motion.tween(&to, &layout, at);
            let scene = palette::scene::palette(&to, &layout, &look, &measure, tween);
            let scene = scene::surround(scene, &theme, Surround::Snapshot { dark });
            let path = output.join(format!("palette-motion-{}-{name}.png", step + 1));
            write_png(&imaging, &renderer, &scene, &measure, &path)?;
        }
    }
    Ok(())
}

fn write_png(
    imaging: &IWICImagingFactory,
    renderer: &Renderer,
    scene: &Scene,
    measure: &super::render::TextMeasure,
    path: &Path,
) -> Result<()> {
    // 2 倍で描き，1 ドットの線がデバイスのピクセルにそろうかを確かめられるようにする
    let scale = tokens::size::snapshot::SCALE;
    let width = (scene.width * scale).ceil() as u32;
    let height = (scene.height * scale).ceil() as u32;
    // SAFETY: 大きさと形式は定まった値
    let bitmap: IWICBitmap = unsafe {
        imaging.CreateBitmap(
            width,
            height,
            &GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
        )?
    };
    let properties = D2D1_RENDER_TARGET_PROPERTIES {
        pixelFormat: D2D1_PIXEL_FORMAT {
            format: DXGI_FORMAT_B8G8R8A8_UNORM,
            alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
        },
        dpiX: BASE_DPI * scale,
        dpiY: BASE_DPI * scale,
        ..Default::default()
    };
    // SAFETY: bitmap は作ったばかりの WIC のビットマップ
    let target = unsafe {
        renderer
            .factory()
            .CreateWicBitmapRenderTarget(&bitmap, &properties)?
    };
    // SAFETY: BeginDraw と EndDraw を対にする
    unsafe { target.BeginDraw() };
    let painted = renderer.paint(&target, scene, measure, scale, 1.0);
    // SAFETY: 同上
    unsafe { target.EndDraw(None, None)? };
    painted?;
    // SAFETY: WIC の部品を順に作って書く．どれも呼び出しのあいだ有効
    unsafe {
        let stream = imaging.CreateStream()?;
        stream.InitializeFromFilename(&HSTRING::from(path.as_os_str()), GENERIC_WRITE.0)?;
        let encoder = imaging.CreateEncoder(&GUID_ContainerFormatPng, std::ptr::null())?;
        encoder.Initialize(&stream, WICBitmapEncoderNoCache)?;
        let mut frame = None;
        let mut options: Option<IPropertyBag2> = None;
        encoder.CreateNewFrame(&mut frame, &mut options)?;
        let frame = frame.ok_or_else(windows_core::Error::empty)?;
        frame.Initialize(options.as_ref())?;
        frame.SetSize(width, height)?;
        let mut format = GUID_WICPixelFormat32bppPBGRA;
        frame.SetPixelFormat(&mut format)?;
        frame.WriteSource(&bitmap, std::ptr::null())?;
        frame.Commit()?;
        encoder.Commit()?;
    }
    Ok(())
}

// MARK: - 見本(macOS の SnapshotRenderer・SamplePanels と同じ中身)

fn hint(keys: &str, label: &str) -> KeyHint {
    KeyHint {
        keys: keys.into(),
        label: label.into(),
    }
}

fn entries(texts: &[&str]) -> Vec<CandidateEntry> {
    texts
        .iter()
        .map(|text| CandidateEntry {
            text: (*text).into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
            has_comment: None,
        })
        .collect()
}

fn variants() -> Vec<CandidateVariant> {
    ["そのまま", "カタカナ", "ｶﾀｶﾅ", "全角英数", "半角英数"]
        .into_iter()
        .map(|label| CandidateVariant {
            label: label.into(),
            is_available: true,
        })
        .collect()
}

fn list() -> CandidateList {
    CandidateList {
        association: None,
        association_hint: None,
        association_key: None,
        homophone: None,
        shows_numbers: None,
        variants: variants(),
        selected_variant: None,
        entries: entries(&["変換", "返還", "偏官", "へんかん", "ヘンカン"]),
        selected_entry: Some(1),
        focus: CandidateFocus::Candidate,
        position: 2,
        total: 12,
        note: None,
        meaning_placement: None,
        // 既定のキー設定で，一覧の先頭から文字種の行へ移るキー(エンジンの FooterHints が送るもの)
        hints: Some(vec![hint("Shift+Space", "文字種")]),
    }
}

/// 同音異義語の使い分け(R-08．macOS の SamplePanels.homophone)．意味が 2 つあるもの
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

/// 同音異義語の使い分けを一覧で出したところ(macOS の homophoneListView)．既定では候補の右のカードにし，選んでいる候補を三角で指す
fn homophone_list(placement: MeaningPlacement) -> CandidateList {
    CandidateList {
        variants: vec![],
        entries: entries(&["撮る", "取る", "採る", "執る"]),
        hints: None,
        selected_entry: Some(0),
        position: 1,
        total: 6,
        homophone: Some(homophone()),
        meaning_placement: Some(placement),
        ..list()
    }
}

/// 同音異義語の無い語の意味を一覧で出したところ(macOS の meaningListView)．同音語の行を出さず，長い意味は折り返す
fn meaning_list() -> CandidateList {
    CandidateList {
        entries: entries(&["動く", "うごく", "ウゴク"]),
        hints: None,
        selected_entry: Some(0),
        position: 1,
        total: 3,
        homophone: Some(HomophoneNote {
            word: "動く".into(),
            part_of_speech: Some(PartOfSpeech::Verb),
            senses: vec![
                HomophoneSense {
                    meaning: "位置や姿勢が変わる。止まっていたものが移る".into(),
                    example: Some("車がゆっくり動く".into()),
                },
                HomophoneSense {
                    meaning: "機械などが作動する".into(),
                    example: Some("時計が動き始める".into()),
                },
                HomophoneSense {
                    meaning: "気持ちが変わる。心が揺れる".into(),
                    example: Some("心が動く".into()),
                },
            ],
            others: vec![],
        }),
        meaning_placement: Some(MeaningPlacement::Side),
        ..list()
    }
}

/// 意味のある候補から意味の無い候補(ひらがな)に移ったところ(macOS の meaningEmptyListView)．
/// カードの場所は空けたままにし，窓の大きさを変えない
fn meaning_empty_list() -> CandidateList {
    CandidateList {
        homophone: None,
        meaning_placement: None,
        selected_entry: Some(1),
        position: 2,
        ..meaning_list()
    }
}

/// 同音異義語の使い分けを分岐図で出したところ(macOS の homophoneBranchView)．既定では選んでいる候補の先に線を伸ばしてカードをつなぐ．
/// 同音語の札には枝に出ていない語だけを出す．selected を意味の無い候補(2)にすると，カードの場所を空けたままにする
fn homophone_branch(placement: MeaningPlacement, selected: usize) -> BranchMap {
    let alternatives = strings(&["取る", "撮る", "とる", "採る"]);
    let has_meaning = selected == 1;
    BranchMap {
        association: None,
        association_hint: None,
        association_key: None,
        columns: vec![
            column("写真を"),
            BranchColumn {
                text: alternatives[selected].clone(),
                selected_alternative: Some(selected as u32),
                is_focused: true,
                is_uncertain: true,
                homophone: has_meaning.then(homophone),
                alternative_notes: vec![None; alternatives.len()],
                alternatives,
                ..column("撮る")
            },
        ],
        position: 1,
        total: 7,
        note: None,
        hints: vec![],
        meaning_placement: has_meaning.then_some(placement),
    }
}

/// コマンドの候補(R-22)を含む一覧で，アプリを開くコマンドを選んだところ(macOS の command-list-selected)
fn command_list() -> CandidateList {
    let mut entries = entries(&["クロード", "Claude を開く", "Claude のサイト", "黒戸"]);
    for (entry, kind) in entries[1..3]
        .iter_mut()
        .zip([ipc::CommandKind::OpenApplication, ipc::CommandKind::OpenURL])
    {
        entry.annotation = Some(crate::strings::COMMAND.into());
        entry.command = Some(kind);
    }
    CandidateList {
        variants: vec![],
        entries,
        hints: None,
        selected_entry: Some(1),
        position: 2,
        total: 4,
        note: Some(ipc::Note {
            tone: ipc::NoteTone::Info,
            title: String::new(),
            subject: None,
            key: Some("Enter".into()),
            key_action: Some("実行".into()),
            text: "Enter 実行".into(),
        }),
        ..list()
    }
}

fn correction() -> CandidateList {
    let mut entries = entries(&["python", "pyてょn", "Python"]);
    entries[1].annotation = Some("入力のまま".into());
    CandidateList {
        association: None,
        association_hint: None,
        association_key: None,
        homophone: None,
        shows_numbers: None,
        variants: variants(),
        selected_variant: None,
        entries,
        selected_entry: Some(0),
        focus: CandidateFocus::Candidate,
        position: 1,
        total: 3,
        note: Some(ipc::Note {
            tone: ipc::NoteTone::Correction,
            title: "修正".into(),
            subject: None,
            key: Some("Space".into()),
            key_action: Some("入力のままに戻す".into()),
            text: "修正　Space 入力のままに戻す".into(),
        }),
        meaning_placement: None,
        hints: Some(vec![hint("Shift+Space", "文字種")]),
    }
}

fn column(text: &str) -> BranchColumn {
    BranchColumn {
        text: text.into(),
        alternatives: vec![],
        selected_alternative: None,
        variants: vec![],
        selected_variant: None,
        is_focused: false,
        is_uncertain: false,
        is_decided: false,
        is_corrected: None,
        preview: None,
        shorter: None,
        longer: None,
        usage_note: None,
        homophone: None,
        alternative_notes: vec![],
        alternative_commands: None,
        alternative_comments: None,
        source_name: None,
        split: None,
    }
}

fn strings(texts: &[&str]) -> Vec<String> {
    texts.iter().map(|text| (*text).to_string()).collect()
}

fn lattice() -> BranchMap {
    scene::sample::branch()
}

fn preview() -> BranchMap {
    BranchMap {
        association: None,
        association_hint: None,
        association_key: None,
        columns: vec![
            column("Cloudflareで"),
            BranchColumn {
                is_uncertain: true,
                preview: Some("取った".into()),
                ..column("撮った")
            },
            BranchColumn {
                alternatives: strings(&["ドメイン", "どめいん"]),
                selected_alternative: Some(0),
                variants: strings(&["どめいん", "ドメイン", "ﾄﾞﾒｲﾝ"]),
                is_focused: true,
                is_uncertain: true,
                ..column("ドメイン")
            },
        ],
        position: 1,
        total: 2,
        note: None,
        hints: vec![
            hint("↓", "候補"),
            hint("↑", "文字種"),
            hint("←→", "文節"),
            hint("Alt+→", "誤りやすい文節"),
            hint("Shift+←→", "区切り調整"),
        ],
        meaning_placement: None,
    }
}

fn split() -> BranchMap {
    BranchMap {
        association: None,
        association_hint: None,
        association_key: None,
        columns: vec![
            column("それは"),
            BranchColumn {
                is_focused: true,
                is_uncertain: true,
                split: Some(BranchSplit {
                    pieces: strings(&["問題", "が", "ある"]),
                }),
                ..column("問題がある")
            },
            column("と思う"),
        ],
        position: 1,
        total: 4,
        note: None,
        hints: vec![hint("1–2", "区切り"), hint("Esc", "取り消し")],
        meaning_placement: None,
    }
}
