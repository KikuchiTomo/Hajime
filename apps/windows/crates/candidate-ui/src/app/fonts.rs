//! OS に入っている書体の一覧(DirectWrite の書体の集まり)．カスタムテーマの書体を選ぶ画面と，
//! 保存した PostScript 名からファミリーと太さを引く描画で使う(crate::fonts)

use crate::fonts::InstalledFace;
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteFont, IDWriteFontCollection,
    IDWriteLocalizedStrings, DWRITE_FACTORY_TYPE_SHARED, DWRITE_FONT_SIMULATIONS_NONE,
    DWRITE_FONT_STYLE_NORMAL, DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME,
};
use windows_core::{BOOL, HSTRING};

/// 画面に出す名前の言語．無ければ英語，それも無ければ最初の名前
const LABEL_LOCALE: &str = "ja-jp";
const ENGLISH_LOCALE: &str = "en-us";

/// OS に入っている書体の一覧．読めなければ空
pub fn installed() -> Vec<InstalledFace> {
    // SAFETY: 引数は定数
    let Ok(dwrite) = (unsafe { DWriteCreateFactory::<IDWriteFactory>(DWRITE_FACTORY_TYPE_SHARED) })
    else {
        return Vec::new();
    };
    let mut collection = None;
    // SAFETY: collection は書き込める領域
    let _ = unsafe { dwrite.GetSystemFontCollection(&mut collection, false) };
    collection.map_or_else(Vec::new, |collection| faces(&collection))
}

/// 書体の集まりの中の書体．太さや斜体を OS が作ったもの(シミュレーション)と，PostScript 名の無いものは除く
pub(super) fn faces(collection: &IDWriteFontCollection) -> Vec<InstalledFace> {
    let mut faces = Vec::new();
    // SAFETY: collection は生きている COM の参照で，番号は数の範囲の中
    unsafe {
        for index in 0..collection.GetFontFamilyCount() {
            let Ok(family) = collection.GetFontFamily(index) else {
                continue;
            };
            let Ok(names) = family.GetFamilyNames() else {
                continue;
            };
            let Some(name) = text(&names, ENGLISH_LOCALE) else {
                continue;
            };
            let family_label = text(&names, LABEL_LOCALE).unwrap_or_else(|| name.clone());
            for member in 0..family.GetFontCount() {
                let Ok(font) = family.GetFont(member) else {
                    continue;
                };
                if let Some(face) = face(&font, &name, &family_label) {
                    faces.push(face);
                }
            }
        }
    }
    faces
}

/// 書体 1 つ
fn face(font: &IDWriteFont, family: &str, family_label: &str) -> Option<InstalledFace> {
    // SAFETY: font は生きている COM の参照で，postscript と exists は書き込める領域
    unsafe {
        if font.GetSimulations() != DWRITE_FONT_SIMULATIONS_NONE {
            return None;
        }
        let mut postscript = None;
        let mut exists = BOOL(0);
        font.GetInformationalStrings(
            DWRITE_INFORMATIONAL_STRING_POSTSCRIPT_NAME,
            &mut postscript,
            &mut exists,
        )
        .ok()?;
        let postscript = text(
            postscript.as_ref().filter(|_| exists.as_bool())?,
            ENGLISH_LOCALE,
        )?;
        let label = font
            .GetFaceNames()
            .ok()
            .and_then(|names| text(&names, LABEL_LOCALE))
            .unwrap_or_else(|| postscript.clone());
        Some(InstalledFace {
            family: family.to_string(),
            family_label: family_label.to_string(),
            postscript,
            label,
            weight: u32::try_from(font.GetWeight().0).unwrap_or(400),
            italic: font.GetStyle() != DWRITE_FONT_STYLE_NORMAL,
            stretch: u32::try_from(font.GetStretch().0).unwrap_or(5),
        })
    }
}

/// 名前の組から locale の名前を読む．無ければ英語，それも無ければ最初の名前
fn text(strings: &IDWriteLocalizedStrings, locale: &str) -> Option<String> {
    // SAFETY: strings は生きている COM の参照で，index と exists と buffer は書き込める領域
    unsafe {
        let mut index = 0;
        let mut exists = BOOL(0);
        let found = [locale, ENGLISH_LOCALE].iter().any(|locale| {
            strings
                .FindLocaleName(&HSTRING::from(*locale), &mut index, &mut exists)
                .is_ok()
                && exists.as_bool()
        });
        if !found {
            if strings.GetCount() == 0 {
                return None;
            }
            index = 0;
        }
        let length = strings.GetStringLength(index).ok()?;
        let mut buffer = vec![0u16; usize::try_from(length).ok()? + 1];
        strings.GetString(index, &mut buffer).ok()?;
        buffer.truncate(usize::try_from(length).ok()?);
        String::from_utf16(&buffer)
            .ok()
            .filter(|name| !name.is_empty())
    }
}
