//! DLL の置き場所からインストール先のフォルダを求める．
//!
//! DLL はバージョンごとのフォルダ(インストール先\tsf\<バージョン>\hajime_tsf.dll，32 ビットは …\x86\hajime_tsf.dll)に置く
//! (apps/windows/installer/hajime.wxs)．上書きで入れても，動いているアプリが読み込んだ古い DLL と場所が重ならないので，
//! 再起動を待たずに新しい DLL を登録できる．前のバージョンはインストール先の直下(と x86\)に置いていた

use std::path::{Path, PathBuf};

/// バージョンごとの DLL のフォルダを置くフォルダ(インストール先の下)
pub const TSF_FOLDER: &str = "tsf";
/// 32 ビットの DLL を置くフォルダ
pub const X86_FOLDER: &str = "x86";

/// module(読み込まれた DLL のパス)からインストール先のフォルダを求める
pub fn installation_folder(module: &Path) -> Option<PathBuf> {
    let mut folder = module.parent()?;
    if is_named(folder, X86_FOLDER) {
        folder = folder.parent()?;
    }
    // tsf\<バージョン>\ に置いた DLL なら，tsf の 1 つ上がインストール先
    if let Some(parent) = folder
        .parent()
        .filter(|parent| is_named(parent, TSF_FOLDER))
    {
        folder = parent.parent()?;
    }
    Some(folder.to_path_buf())
}

/// module(読み込まれた DLL のパス)が tsf\<バージョン>\ に置いたものなら，tsf のフォルダとそのバージョンのフォルダの名前
pub fn version_folder(module: &Path) -> Option<(PathBuf, String)> {
    let mut folder = module.parent()?;
    if is_named(folder, X86_FOLDER) {
        folder = folder.parent()?;
    }
    let tsf = folder
        .parent()
        .filter(|parent| is_named(parent, TSF_FOLDER))?;
    let name = folder.file_name()?.to_str()?.to_string();
    Some((tsf.to_path_buf(), name))
}

/// tsf のフォルダの中の names のうち，今のバージョン(current)でないもの(前の版の DLL を置いたフォルダ)
pub fn stale_versions<'a>(names: &'a [String], current: &str) -> Vec<&'a str> {
    names
        .iter()
        .map(String::as_str)
        .filter(|name| !name.eq_ignore_ascii_case(current))
        .filter(|name| !name.is_empty() && *name != "." && *name != "..")
        .collect()
}

fn is_named(folder: &Path, name: &str) -> bool {
    folder
        .file_name()
        .and_then(|folder| folder.to_str())
        .is_some_and(|folder| folder.eq_ignore_ascii_case(name))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn バージョンごとのフォルダを_dll_の場所から求める() {
        let module = path(&[
            "C:",
            "Program Files",
            "Hajime",
            "tsf",
            "0.3.4",
            "hajime_tsf.dll",
        ]);
        let tsf = path(&["C:", "Program Files", "Hajime", "tsf"]);
        assert_eq!(
            version_folder(&module),
            Some((tsf.clone(), "0.3.4".to_string()))
        );
        let module = path(&[
            "C:",
            "Program Files",
            "Hajime",
            "tsf",
            "0.3.4",
            "x86",
            "hajime_tsf.dll",
        ]);
        assert_eq!(version_folder(&module), Some((tsf, "0.3.4".to_string())));
        // tsf の下でなければ(前の置き方)何も消さない
        let module = path(&["C:", "Program Files", "Hajime", "hajime_tsf.dll"]);
        assert_eq!(version_folder(&module), None);
    }

    #[test]
    fn 今のバージョンでないフォルダだけを選ぶ() {
        let names = vec![
            "0.3.3".to_string(),
            "0.3.4".to_string(),
            "0.2.7".to_string(),
        ];
        assert_eq!(stale_versions(&names, "0.3.4"), vec!["0.3.3", "0.2.7"]);
        assert!(stale_versions(&["0.3.4".to_string()], "0.3.4").is_empty());
    }

    fn path(parts: &[&str]) -> PathBuf {
        parts.iter().collect()
    }

    #[test]
    fn バージョンごとのフォルダの_dll_からインストール先を求める() {
        let root = path(&["C:", "Program Files", "Hajime"]);
        let module = path(&[
            "C:",
            "Program Files",
            "Hajime",
            "tsf",
            "0.2.7",
            "hajime_tsf.dll",
        ]);
        assert_eq!(installation_folder(&module), Some(root.clone()));
        let module = path(&[
            "C:",
            "Program Files",
            "Hajime",
            "TSF",
            "0.2.7",
            "X86",
            "hajime_tsf.dll",
        ]);
        assert_eq!(installation_folder(&module), Some(root));
    }

    #[test]
    fn 前のバージョンの置き場所でもインストール先を求める() {
        let root = path(&["C:", "Program Files", "Hajime"]);
        let module = path(&["C:", "Program Files", "Hajime", "hajime_tsf.dll"]);
        assert_eq!(installation_folder(&module), Some(root.clone()));
        let module = path(&["C:", "Program Files", "Hajime", "x86", "hajime_tsf.dll"]);
        assert_eq!(installation_folder(&module), Some(root));
    }
}
