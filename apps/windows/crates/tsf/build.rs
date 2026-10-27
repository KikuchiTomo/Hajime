//! アプリのアイコンを DLL のリソースに入れる．入力の一覧(設定の「言語」・入力の切り替え)に出す IME のアイコンは，
//! RegisterProfile でこの DLL の 0 番目のアイコンを指している(com/registration.rs)

include!("../../build/icon_resource.rs");

fn main() {
    embed_icon("cdylib");
}
