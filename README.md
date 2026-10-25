# s90.tokyo IME

[![check](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/check.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
[![Engine](https://img.shields.io/badge/engine-azooKey%20%2B%20Zenzai-6b4fbb.svg)](https://github.com/azooKey/AzooKeyKanaKanjiConverter)

macOS 向けの日本語入力システムです．かな漢字変換は [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) のエンジンで行い，文と入力位置の前の文字列を手がかりに第 1 候補を選ぶ Zenzai を使っています．Windows 版は作っている途中です．

開発中のため，動きや設定は予告なく変わります．

## 今できること

| 機能 | 内容 |
|---|---|
| ライブ変換 | 打ちながら漢字かな混じりで表示し，Enter で確定します．打っている途中の短い語はかなのまま見せ(「らい」を「雷」にしない)，打鍵が止まると変換して見せます |
| 文脈を見た変換 | 「Cloudflareで取ったドメイン」「AAA」のあとの「まで」のように，文や前の文字列から候補を選びます |
| 英単語の補正 | ローマ字のまま打った英単語(`pyてょn`)や綴りの誤り(`pthon`)を `python` に直します．補正の直後に Space を押すと打ったままに戻ります．文の途中でも直り，続けて日本語を打てます |
| 分岐図 | Space で変換すると，文を 1 本の幹として文節を並べ，注目している文節から下へ変換の候補，上へ字種(そのまま・カタカナ・半角カタカナ)の枝を伸ばします．迷う文節には点線を引いて次の候補を添え，Tab で迷う文節だけを渡り歩けます |
| 日本語の打ち間違い | Space で変換するときに，Zenzai で打ち間違いを直します(`kyounotenkihayoudesune` → 今日の天気は良いですね)．直したときは知らせを出し，Esc で打ったままに戻ります |
| 記号 | `->` は →，`<-` は ←，`=>` は ⇒ になります．`zh` `zj` `zk` `zl` で ← ↓ ↑ →，`z.` で …，`z[` で『 を入れられます．「やじるし」「ほし」「こめ」「まるいち」などの読みからも記号を選べます |
| ¥ キー | JIS キーボードの ¥ キーで入れる文字を選べます．既定は `\` です |
| 入力方式 | ローマ字入力，かな入力(JIS かな配列)，英語のまま打って Tab で日本語にする EN 入力．Option+かな で切り替えます |
| エディタとターミナル | VS Code や Xcode，ターミナルでは括弧などの記号を半角のまま入れます．ターミナルで行の頭に `git` などのコマンドの名前を打って Space を押すと，その行は英字のまま流し，引用符の中だけ日本語にします |
| 設定の画面 | 入力メニューの「設定を開く…」で開きます．句読点，括弧，空白と数字の幅，学習，ユーザー辞書(取り込みと書き出し)，日付の変換，アプリごとの扱いなどを変えられます．一覧は [docs/user/reference/settings.md](docs/user/reference/settings.md) |
| 使い方の記録 | 選び直さずに確定した割合などを，回数だけこの Mac の中に記録して設定の画面で見せます．入力した文字は記録しません |

ローマ字の「nn」は必ず「ん」になります．「こんにちは」は `konnnitiha`，「おんな」は `onnna` と打ちます．

## まだできないこと

Windows 版，キー割り当ての編集，ローマ字テーブルの編集はまだありません．作る予定の一覧は [docs/specs/REQUIREMENTS.md](docs/specs/REQUIREMENTS.md) にあります．

## 入力した内容の扱い

IME 自体は通信しません．入力した文字列や前の文字列はメモリの中だけで扱い，ログにも書きません．通信が起きるのは，入れるときに Zenzai のモデルを Hugging Face から取得する 1 回だけで，取得したファイルは SHA-256 を確かめてから使います．詳しくは [docs/dev/SECURITY-MODEL.md](docs/dev/SECURITY-MODEL.md) にあります．

## macOS に入れる

Xcode 26，XcodeGen(`brew install xcodegen`)と，署名に使う Apple Development の証明書が要ります．

```sh
make install-macos
```

Zenzai のモデル(約 70MB)を取得し，ビルドしたアプリを `/Library/Input Methods` に入れます．管理者のパスワードを聞かれます．

初めて入れたときは，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から「s90.tokyo IME」を足してください．設定は，入力メニューで s90.tokyo IME を選んでいるときに同じメニューの「設定を開く…」から変えられます．

配布物(.pkg)は `make package-macos` で作れます(`docs/dev/RELEASE.md`)．

## 開発

手元で試す方法，ブランチと PR の決まりは [CONTRIBUTING.md](CONTRIBUTING.md) にあります．設計の文書は次のとおりです．

| 文書 | 内容 |
|---|---|
| [docs/dev/ARCHITECTURE.md](docs/dev/ARCHITECTURE.md) | 構成と層 |
| [docs/dev/GUIDELINES.md](docs/dev/GUIDELINES.md) | 置き場所・名前・書き方 |
| [docs/dev/DESIGN-SYSTEM.md](docs/dev/DESIGN-SYSTEM.md) | 見た目の決まり |
| [docs/dev/adr/README.md](docs/dev/adr/README.md) | 設計の判断の記録 |
| [docs/README.md](docs/README.md) | ドキュメントの地図 |

脆弱性は Issue に書かず，[SECURITY.md](SECURITY.md) の手順で知らせてください．

## ライセンス

MIT License です([LICENSE](LICENSE))．azooKey と Zenzai のモデル(Apache-2.0)の著作権表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にあります．

English: [README.en.md](README.en.md)
