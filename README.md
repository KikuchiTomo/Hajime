# はじめ

[![macOS](https://img.shields.io/github/v/release/KikuchiTomo/Hajime?filter=*-macos&include_prereleases&sort=semver&display_name=release&label=macOS&logo=apple)](https://github.com/KikuchiTomo/Hajime/releases?q=macos&expanded=true)
[![Windows](https://img.shields.io/github/v/release/KikuchiTomo/Hajime?filter=*-windows&include_prereleases&sort=semver&display_name=release&label=Windows&logo=windows)](https://github.com/KikuchiTomo/Hajime/releases?q=windows&expanded=true)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Windows%2010%2B%20%7C%20Linux%20(WIP)-lightgrey.svg)
[![Engine](https://img.shields.io/badge/engine-azooKey%20%2B%20Zenzai-6b4fbb.svg)](https://github.com/azooKey/AzooKeyKanaKanjiConverter)

macOS・Windows 向けの日本語入力システムです．
かな漢字変換には [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) のエンジンと，ニューラル言語モデルの Zenzai を使用しています．

開発中のため，仕様は変更される可能性があります．

## 機能

| 機能 | 内容 |
|---|---|
| ライブ変換 | 入力しながら漢字に変換します．漢字にするまでの待ち時間を設定できます． |
| 分岐図 | 文節ごとに候補が枝分かれして並び，文全体を見ながら必要な文節だけを選び直せます．従来の一覧表示にも切り替えられます． |
| 文節の操作 | 文節の長さは 1 文字単位と単語単位で調整できます．単語の切れ目での分割や，文節の入力し直しにも対応しています． |
| 打ち間違いの補正 | 母音・子音の打ち間違いや打ち忘れを文脈から判断して補正します(「yorosikuonagaisimasu」→「よろしくお願いします」)．確信が持てないときは「もしかして」で候補を示します．Esc で入力どおりに戻せます． |
| 英単語の補正 | ローマ字で入力した英単語のつづりを補正します(「pthon」→「python」)． |
| 英字入力 | 英語のまま入力しながら，必要な語だけを日本語に変換します． |
| 連想変換 | Shift+Space で，似た意味の語や関連する語を候補に出します． |
| 便利な変換 | 計算(「1+2*3=」)，郵便番号からの住所，日付と時刻(「きょう」「なう」)，記号と絵文字に変換できます． |
| 校正支援 | ら抜き言葉・二重敬語・重言や，同音異義語の使い分けを候補に添えます． |
| 手書き入力 | 読みの分からない漢字を，手書きで探して入力できます． |
| 辞書 | ユーザー辞書のほか，数十万語の専門用語辞書なども取り込めます． |
| カスタマイズ | すべてのキー操作を変更でき，Windows 風・Mac 風・Emacs 風・Vim 風のひな形を用意しています．テーマは独自に作成できます． |
| アプリごとの設定 | エディタやターミナルでは記号を半角で入力し，コマンドを英字のまま入力できます． |
| 同期とバックアップ | Dropbox などのフォルダを通じて，複数のパソコンで設定と辞書を同期できます．設定は JSON で書き出せます． |
| プライバシー | 入力した文字を端末の外に送信しません．通信も行いません． |

## インストール

| OS | 対応バージョン | ダウンロード |
|---|---|---|
| macOS | macOS 14 以降 | [最新のリリース](https://github.com/KikuchiTomo/Hajime/releases?q=macos&expanded=true)(`.pkg`) |
| Windows | Windows 10 22H2 以降(64 ビット) | [最新のリリース](https://github.com/KikuchiTomo/Hajime/releases?q=windows&expanded=true)(`.msi`) |
| Linux (WIP) | | 準備中 |

インストールしたら，一度ログアウトしてから，OS の入力ソースの設定で「はじめ」を追加してください．

## ライセンス

MIT License です([LICENSE](LICENSE))．

本ソフトウェアは azooKey(MIT)と Zenzai のモデル(Apache-2.0)を使用しています．著作権表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) と，アプリの設定画面の「情報」に記載しています．

脆弱性の報告は [SECURITY.md](SECURITY.md) をご覧ください．

English: [README.en.md](README.en.md)
