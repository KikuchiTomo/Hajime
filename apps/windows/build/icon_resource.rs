// アプリのアイコン(apps/windows/resources/hajime.ico)とバージョンの情報(VERSIONINFO)を，実行ファイル・DLL のリソースにする．
// 各 crate の build.rs から include! で読み込む．rc.exe や依存の crate を使わず，リソースのファイル(.res)を
// ここで書いてリンカーに渡す(link.exe は .res をそのまま受け取る)．
// アイコンの組(RT_GROUP_ICON)の番号は 1．入力の一覧に出すアイコン(RegisterProfile の 0 番目)と窓のアイコンに使う．
// バージョンの情報は，エクスプローラーのプロパティ・タスクマネージャー・スタートアップアプリの一覧に出る名前になる

use std::path::{Path, PathBuf};

const RT_ICON: u16 = 3;
const RT_GROUP_ICON: u16 = 14;
const RT_VERSION: u16 = 16;
/// バージョンの情報の番号(VS_VERSION_INFO)
const VERSION_ID: u16 = 1;
/// MOVEABLE | PURE(rc.exe がバージョンの情報に付ける値)
const VERSION_FLAGS: u16 = 0x0030;
/// 製品名．エクスプローラーのプロパティやタスクマネージャーに出す(製品名は「Hajime IME」と書く決まり)
const PRODUCT_NAME: &str = "Hajime IME";
/// 発行元．インストーラーの Manufacturer(installer/hajime.wxs)と同じにする
const COMPANY_NAME: &str = "haji.men";
/// 文字列の表の言語と文字コード(日本語・UTF-16)
const LANGUAGE: u16 = 0x0411;
const CODE_PAGE: u16 = 1200;
const VFT_APP: u32 = 1;
const VFT_DLL: u32 = 2;
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

/// ICO のアイコンを .res の項目として足す
fn push_icons(out: &mut Vec<u8>, ico: &[u8]) -> Option<()> {
    let images = parse_ico(ico)?;
    let mut group = Vec::new();
    group.extend_from_slice(&0u16.to_le_bytes());
    group.extend_from_slice(&1u16.to_le_bytes());
    group.extend_from_slice(&(images.len() as u16).to_le_bytes());
    for (index, image) in images.iter().enumerate() {
        let id = u16::try_from(index + 1).ok()?;
        push_resource(out, RT_ICON, id, ICON_FLAGS, &image.data);
        group.extend_from_slice(&[image.width, image.height, image.colors, 0]);
        group.extend_from_slice(&image.planes.to_le_bytes());
        group.extend_from_slice(&image.bit_count.to_le_bytes());
        group.extend_from_slice(&(image.data.len() as u32).to_le_bytes());
        group.extend_from_slice(&id.to_le_bytes());
    }
    push_resource(out, RT_GROUP_ICON, GROUP_ID, ICON_FLAGS, &group);
    Some(())
}

fn utf16z(text: &str) -> Vec<u8> {
    text.encode_utf16()
        .chain(std::iter::once(0))
        .flat_map(u16::to_le_bytes)
        .collect()
}

fn pad4(bytes: &mut Vec<u8>) {
    while !bytes.len().is_multiple_of(4) {
        bytes.push(0);
    }
}

/// バージョンの情報の 1 つの塊(wLength・wValueLength・wType・szKey・Value・Children)．
/// value_length は文字列なら NUL を含む文字数，それ以外はバイト数．子の塊はそれぞれ 4 バイトの境目から置く
fn version_block(key: &str, value: &[u8], value_length: u16, text: bool, children: &[Vec<u8>]) -> Vec<u8> {
    let mut block = vec![0, 0];
    block.extend_from_slice(&value_length.to_le_bytes());
    block.extend_from_slice(&u16::from(text).to_le_bytes());
    block.extend_from_slice(&utf16z(key));
    pad4(&mut block);
    block.extend_from_slice(value);
    for child in children {
        pad4(&mut block);
        block.extend_from_slice(child);
    }
    let length = (block.len() as u16).to_le_bytes();
    block[..2].copy_from_slice(&length);
    block
}

fn string_entry(key: &str, value: &str) -> Vec<u8> {
    let length = value.encode_utf16().count() as u16 + 1;
    version_block(key, &utf16z(value), length, true, &[])
}

/// "1.2.3" や "1.2.3-beta.1" を 4 つの数(主・副・修正・0)にする．読めない部分は 0
fn version_numbers(version: &str) -> [u16; 4] {
    let core = version.split(['-', '+']).next().unwrap_or_default();
    let mut numbers = [0u16; 4];
    for (slot, part) in numbers.iter_mut().zip(core.split('.')) {
        *slot = part.parse().unwrap_or(0);
    }
    numbers
}

/// VS_VERSIONINFO を作る．dll なら種類を DLL にする
fn version_info(version: &str, file_name: &str, dll: bool) -> Vec<u8> {
    let [major, minor, patch, build] = version_numbers(version);
    let high = (u32::from(major) << 16) | u32::from(minor);
    let low = (u32::from(patch) << 16) | u32::from(build);
    let mut fixed = Vec::new();
    for value in [
        0xFEEF_04BD, // dwSignature
        0x0001_0000, // dwStrucVersion
        high,        // dwFileVersionMS
        low,         // dwFileVersionLS
        high,        // dwProductVersionMS
        low,         // dwProductVersionLS
        0x3F,        // dwFileFlagsMask(VS_FFI_FILEFLAGSMASK)
        0,           // dwFileFlags
        0x0004_0004, // dwFileOS(VOS_NT_WINDOWS32)
        if dll { VFT_DLL } else { VFT_APP },
        0, // dwFileSubtype
        0, // dwFileDateMS
        0, // dwFileDateLS
    ] {
        fixed.extend_from_slice(&u32::to_le_bytes(value));
    }
    let file_version = format!("{major}.{minor}.{patch}.{build}");
    let internal_name = file_name.rsplit_once('.').map_or(file_name, |(stem, _)| stem);
    let strings = [
        ("CompanyName", COMPANY_NAME),
        ("FileDescription", PRODUCT_NAME),
        ("FileVersion", file_version.as_str()),
        ("InternalName", internal_name),
        ("OriginalFilename", file_name),
        ("ProductName", PRODUCT_NAME),
        ("ProductVersion", version),
    ]
    .map(|(key, value)| string_entry(key, value));
    let table_key = format!("{LANGUAGE:04X}{CODE_PAGE:04X}");
    let table = version_block(&table_key, &[], 0, true, &strings);
    let string_info = version_block("StringFileInfo", &[], 0, true, &[table]);
    let mut translation = LANGUAGE.to_le_bytes().to_vec();
    translation.extend_from_slice(&CODE_PAGE.to_le_bytes());
    let var = version_block("Translation", &translation, 4, false, &[]);
    let var_info = version_block("VarFileInfo", &[], 0, true, &[var]);
    version_block("VS_VERSION_INFO", &fixed, fixed.len() as u16, false, &[string_info, var_info])
}

/// アイコンとバージョンの情報のリソースを書き，リンカーに渡す．link_kind は "cdylib" か "bins"(cargo:rustc-link-arg-<種類>)．
/// file_name はできる実行ファイル・DLL の名前(OriginalFilename)．バージョンは crate のバージョン(ワークスペースで 1 つ)．
/// MSVC で Windows 向けにビルドするときだけ行う
fn embed_resources(link_kind: &str, file_name: &str) {
    let windows = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows");
    let msvc = std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let ico = manifest.join("../../resources/hajime.ico");
    println!("cargo:rerun-if-changed={}", ico.display());
    if !(windows && msvc) {
        return;
    }
    let mut res = Vec::new();
    // .res の先頭は中身の無い項目
    push_resource(&mut res, 0, 0, 0, &[]);
    let icons = std::fs::read(&ico).ok().and_then(|bytes| push_icons(&mut res, &bytes));
    if icons.is_none() {
        println!("cargo:warning=アイコンを読めませんでした: {}", ico.display());
    }
    let version = std::env::var("CARGO_PKG_VERSION").unwrap_or_default();
    let info = version_info(&version, file_name, link_kind == "cdylib");
    push_resource(&mut res, RT_VERSION, VERSION_ID, VERSION_FLAGS, &info);
    let out = Path::new(&std::env::var("OUT_DIR").unwrap_or_default()).join("hajime-resources.res");
    if std::fs::write(&out, res).is_ok() {
        println!("cargo:rustc-link-arg-{link_kind}={}", out.display());
    }
}
