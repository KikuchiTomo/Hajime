//! 共通コントロールのバージョン 6 を使う(ダークの見た目・入力欄の案内の文字・部品を自分で描く知らせに要る)．
//! マニフェストを実行ファイルに埋め込む．アプリのアイコン(タスクバーとタイトルバー)もリソースに入れる

include!("../../build/icon_resource.rs");

fn main() {
    embed_icon("bins");
    let windows = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("windows");
    let msvc = std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("msvc");
    if windows && msvc {
        println!("cargo:rustc-link-arg-bins=/MANIFEST:EMBED");
        // 対応する Windows の宣言(子の窓の WS_EX_LAYERED に要る．s90-settings.manifest)
        let manifest =
            std::path::Path::new(&std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default())
                .join("s90-settings.manifest");
        println!("cargo:rerun-if-changed={}", manifest.display());
        println!(
            "cargo:rustc-link-arg-bins=/MANIFESTINPUT:{}",
            manifest.display()
        );
        println!(
            "cargo:rustc-link-arg-bins=/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
        );
    }
}
