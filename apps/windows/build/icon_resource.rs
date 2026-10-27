// アプリのアイコン(apps/windows/resources/s90.ico)を，実行ファイル・DLL のリソースにする．
// 各 crate の build.rs から include! で読み込む．rc.exe や依存の crate を使わず，リソースのファイル(.res)を
// ここで書いてリンカーに渡す(link.exe は .res をそのまま受け取る)．
// アイコンの組(RT_GROUP_ICON)の番号は 1．入力の一覧に出すアイコン(RegisterProfile の 0 番目)と窓のアイコンに使う

use std::path::{Path, PathBuf};

const RT_ICON: u16 = 3;
const RT_GROUP_ICON: u16 = 14;
/// アイコンの組の番号(LoadIconW の MAKEINTRESOURCE(1))
const GROUP_ID: u16 = 1;
/// MOVEABLE | PURE | DISCARDABLE(rc.exe がアイコンに付ける値)
const ICON_FLAGS: u16 = 0x1030;
const ICONDIR_SIZE: usize = 6;
const ICONDIRENTRY_SIZE: usize = 16;

/// ICO の 1 枚分
struct IconImage {
    width: u8,
    height: u8,
    colors: u8,
    planes: u16,
    bit_count: u16,
    data: Vec<u8>,
}

fn read_u16(bytes: &[u8], at: usize) -> Option<u16> {
    Some(u16::from_le_bytes([*bytes.get(at)?, *bytes.get(at + 1)?]))
}

fn read_u32(bytes: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_le_bytes([
        *bytes.get(at)?,
        *bytes.get(at + 1)?,
        *bytes.get(at + 2)?,
        *bytes.get(at + 3)?,
    ]))
}

/// ICO を 1 枚ずつに分ける
fn parse_ico(bytes: &[u8]) -> Option<Vec<IconImage>> {
    if read_u16(bytes, 0)? != 0 || read_u16(bytes, 2)? != 1 {
        return None;
    }
    let count = usize::from(read_u16(bytes, 4)?);
    (0..count)
        .map(|index| {
            let entry = ICONDIR_SIZE + index * ICONDIRENTRY_SIZE;
            let size = read_u32(bytes, entry + 8)? as usize;
            let offset = read_u32(bytes, entry + 12)? as usize;
            Some(IconImage {
                width: *bytes.get(entry)?,
                height: *bytes.get(entry + 1)?,
                colors: *bytes.get(entry + 2)?,
                planes: read_u16(bytes, entry + 4)?,
                bit_count: read_u16(bytes, entry + 6)?,
                data: bytes.get(offset..offset.checked_add(size)?)?.to_vec(),
            })
        })
        .collect()
}

/// .res の 1 項目(種類と名前は番号)．データは 4 バイトの境目までそろえる
fn push_resource(out: &mut Vec<u8>, kind: u16, name: u16, flags: u16, data: &[u8]) {
    const HEADER_SIZE: u32 = 32;
    out.extend_from_slice(&(data.len() as u32).to_le_bytes());
    out.extend_from_slice(&HEADER_SIZE.to_le_bytes());
    out.extend_from_slice(&0xFFFFu16.to_le_bytes());
    out.extend_from_slice(&kind.to_le_bytes());
    out.extend_from_slice(&0xFFFFu16.to_le_bytes());
    out.extend_from_slice(&name.to_le_bytes());
    // DataVersion・MemoryFlags・LanguageId(言語に依らない)・Version・Characteristics
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&flags.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(&0u32.to_le_bytes());
    out.extend_from_slice(data);
    while !out.len().is_multiple_of(4) {
        out.push(0);
    }
}

/// ICO から .res を作る
fn icon_res(ico: &[u8]) -> Option<Vec<u8>> {
    let images = parse_ico(ico)?;
    let mut out = Vec::new();
    // .res の先頭は中身の無い項目
    push_resource(&mut out, 0, 0, 0, &[]);
    let mut group = Vec::new();
    group.extend_from_slice(&0u16.to_le_bytes());
    group.extend_from_slice(&1u16.to_le_bytes());
    group.extend_from_slice(&(images.len() as u16).to_le_bytes());
    for (index, image) in images.iter().enumerate() {
        let id = u16::try_from(index + 1).ok()?;
        push_resource(&mut out, RT_ICON, id, ICON_FLAGS, &image.data);
        group.extend_from_slice(&[image.width, image.height, image.colors, 0]);
        group.extend_from_slice(&image.planes.to_le_bytes());
        group.extend_from_slice(&image.bit_count.to_le_bytes());
        group.extend_from_slice(&(image.data.len() as u32).to_le_bytes());
        group.extend_from_slice(&id.to_le_bytes());
    }
    push_resource(&mut out, RT_GROUP_ICON, GROUP_ID, ICON_FLAGS, &group);
    Some(out)
}

/// アイコンのリソースを書き，リンカーに渡す．link_kind は "cdylib" か "bins"(cargo:rustc-link-arg-<種類>)．
/// MSVC で Windows 向けにビルドするときだけ行う
fn embed_icon(link_kind: &str) {
    let windows = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows");
    let msvc = std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let ico = manifest.join("../../resources/s90.ico");
    println!("cargo:rerun-if-changed={}", ico.display());
    if !(windows && msvc) {
        return;
    }
    let Some(res) = std::fs::read(&ico).ok().and_then(|bytes| icon_res(&bytes)) else {
        println!("cargo:warning=アイコンを読めませんでした: {}", ico.display());
        return;
    };
    let out = Path::new(&std::env::var("OUT_DIR").unwrap_or_default()).join("s90-icon.res");
    if std::fs::write(&out, res).is_ok() {
        println!("cargo:rustc-link-arg-{link_kind}={}", out.display());
    }
}
