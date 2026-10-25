# apps/macos

macOS の入力メソッド(InputMethodKit)・候補ウィンドウ(AppKit)・設定アプリ(SwiftUI)を置く．
Xcode のプロジェクトは `project.yml`(XcodeGen)から作り，`.xcodeproj` はコミットしない．

ここに書くのは，`NSEvent` から `KeyEvent` への変換と，`ClientAction` を `IMKTextInput` に反映する処理だけ．判断は `core/` に置く．
