# InputMethodKit の注意点

azooKey-Desktop(`../upstream/azooKey-Desktop/azooKeyMac/`)の実装を読むときに気を付けること．

## 入力メソッドの登録

- `Info.plist` の `InputMethodConnectionName`，`InputMethodServerControllerClass`，`tsInputModeListKey` で入力モード(ひらがな・英数など)を宣言する
- バンドル ID は `men.haji.inputmethod` を使う．入力モードの ID はその下に `.Japanese`，`.Roman` を付ける
- インストール先は `~/Library/Input Methods/`(開発中)か `/Library/Input Methods/`(配布物)

## コントローラ

- `IMKInputController` はクライアントごとに作られ，`activateServer(_:)` / `deactivateServer(_:)` で切り替わる．非アクティブになるときは変換中の文字を確定するか捨て，候補ウィンドウを閉じる
- `inputText(_:client:)` ではなく `handle(_:client:)` を使い，修飾キーと keyDown を自分で解釈する
- `recognizedEvents(_:)` で `.keyDown` と `.flagsChanged` を受け取る

## 文字の反映

- 変換中の文字は `setMarkedText(_:selectionRange:replacementRange:)`．下線の種類は属性で指定する(`NSAttributedString.Key.underlineStyle` と，`markedClauseSegment` で文節を分ける)
- 確定は `insertText(_:replacementRange:)`
- 候補ウィンドウの位置は `attributes(forCharacterIndex:lineHeightRectangle:)` で得る．返ってくる座標は画面の左下が原点なので，`NSScreen` の座標に直してから使う
- 一部のアプリ(ターミナル・Electron)は `selectedRange` や `attributes` が正しく返らない．そのときの位置の決め方は core の `WindowPositioning` にまとめる(azooKey-Desktop の `Core/Sources/Core/Windows/WindowPositioning.swift` を参考にする)

## アプリの識別

- `client().bundleIdentifier()` でプロファイルを決める．取れないときは既定のプロファイル
- ターミナル(`com.apple.Terminal`，`com.googlecode.iterm2`，`com.mitchellh.ghostty`，`net.kovidgoyal.kitty`，`dev.warp.Warp-Stable`)とエディタ(`com.microsoft.VSCode`，`com.jetbrains.*`，`dev.zed.Zed`，`com.apple.dt.Xcode`)の既定の一覧は `DefaultSettings.swift` に置く
