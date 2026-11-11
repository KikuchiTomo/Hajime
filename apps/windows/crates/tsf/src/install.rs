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

fn is_named(folder: &Path, name: &str) -> bool {
    folder
        .file_name()
        .and_then(|folder| folder.to_str())
        .is_some_and(|folder| folder.eq_ignore_ascii_case(name))
}

#[cfg(test)]
mod tests {
    use super::*;

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
