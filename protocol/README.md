# protocol

Windows の TSF の DLL・候補ウィンドウと `hajime-engine-host` のあいだのメッセージの定義を置く．
形式は長さ付きの JSON(ADR [0010](../docs/dev/adr/0010-ipc-message-format.md))．安全の決まりは [docs/dev/SECURITY-MODEL.md](../docs/dev/SECURITY-MODEL.md) の「Windows のプロセス間通信」．

| ファイル | 中身 |
|---|---|
| `schema.json` | メッセージの型の定義 |
| `fixtures/messages.json` | 見本．Swift と Rust の両方のテストが読み，読み戻して同じ JSON になることを確かめる |

## 型を変える

1. `schema.json` を変える
2. `make protocol` で Swift と Rust の型を作り直す
   - Swift: `core/Sources/HajimeIPC/Generated/WireMessages.swift`(名前の前に `Wire` を付ける．core の `KeyEvent` などとぶつけないため)
   - Rust: `apps/windows/crates/ipc/src/generated.rs`
3. 足した型や種類を `fixtures/messages.json` に足す
4. 互換のない変更(名前を変える・必須の項目を足す)では `version` を 1 つ上げる．DLL とエンジンのバージョンが違えば接続を断る

生成物は手で直さない．`make check` が定義と合っているかを確かめる．

## 定義の書き方

`types` に型を並べる．種類(`kind`)は 3 つ．

| kind | 意味 | JSON の形 |
|---|---|---|
| `struct` | 項目(`fields`)の組 | `{"name": 値, ...}` |
| `enum` | 文字列の値のどれか(`cases`) | `"japanese"` |
| `union` | 種類ごとに違う項目を持つ(`cases`) | `{"<tag>": "種類", "項目": 値, ...}` |

項目の型は `bool`・`string`・`u8`・`u32`・`i32`・`f64` と定義した型の名前．`[T]` は列，末尾の `?` は省ける値．
名前は型が PascalCase，項目と種類が camelCase．

## 流れ

```
TSF の DLL ──Request──→ hajime-engine-host ──UiCommand──→ 候補ウィンドウ
           ←─Response──
```

- DLL はキーを `key` で送り，返った `edit` の `operations` を入力欄に反映する．`state` は OnTestKeyDown に答えるための写し
- 候補・分岐図・案内・モードの札はエンジンが候補ウィンドウに直接送る．DLL は入力位置(`caret`)だけを知らせる
- 候補の札がユーザー辞書の語のコメントのときは，一覧の行に `hasComment`，分岐図の枝に `alternativeComments` を付ける．候補ウィンドウは札を押せるようにし，押したら `chooseCandidate` の `comment` で返す．エンジンは候補の代わりにコメントを入れる
- 絵文字と記号のパレット(R-26)も，エンジンが `showPalette`・`hidePalette` で候補ウィンドウに出す．候補ウィンドウでマウスで操作した対象は `choosePalette` で返し，エンジンは DLL の次の `wake` でキーと同じに処理する．パレットを開いているあいだは，状態の `isComposing` を真にして DLL にすべてのキーを送ってもらう．入力メニューの「絵文字と記号」は，DLL が `openPalette` で頼む(手書き入力の `openHandwriting` と同じく edit で返り，前に見ていた種類で開く．メニューに出すかは設定の `palette`)
- 設定の画面(`hajime-settings.exe`)は `readSettingsFields`・`writeSettingsFields` で，設定の項目を設定のファイル(`settings.json`)と同じ名前と JSON の形で読み書きする．値は文字列に入れた JSON のオブジェクトで，項目を足しても定義は変えない．キー設定のひな形は `readKeymapPreset`，表の知らせ(使われない行・文字を打てなくなる行・キーの無い確定と取り消し)は `checkKeymap` で頼む
- 設定のファイルの外にあるものは別の要求で頼む．学習を消す `resetLearning`，使い方の記録 `readUsage`・`resetUsage`，英語と日本語の「試す」`previewLanguage`，ユーザー辞書 `readUserDictionary`(ページごと．1 回 500 語まで)・`addUserDictionaryEntry`・`removeUserDictionaryEntry`・`mergeUserDictionary`(取り込み)．ユーザー辞書は大きくなるので `readSettingsFields` では読まない．語の品詞 `wordClass` とコメント `comment` は省ける(品詞を省いた語は名詞として登録する)．同じ読みと語を別の品詞で足すと品詞を書き換え，消すときは品詞を問わない
