//! アプリのアイコンとバージョンの情報(製品名「Hajime IME」)を実行ファイルのリソースに入れる．
//! タスクマネージャーやエクスプローラーのプロパティに，ファイル名ではなく製品名で出る

include!("../../build/icon_resource.rs");

fn main() {
    embed_resources("bins", "hajime-candidate-ui.exe");
}
