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

- ライブ変換
- 分岐図による候補の表示
- 文節の調整・分割・入力し直し
- 打ち間違いの自動補正と「もしかして」
- 英単語のつづりの補正
- 英字入力
- 連想変換
- 計算・郵便番号・日付と時刻・記号の変換
- 校正支援
- 手書き入力
- 辞書の取り込み
- キー操作とテーマのカスタマイズ
- アプリごとの入力設定
- 設定の同期とバックアップ

## インストール

| OS | 対応バージョン | ダウンロード |
|---|---|---|
| macOS | macOS 14 以降 | [最新のリリース](https://github.com/KikuchiTomo/Hajime/releases?q=macos&expanded=true) |
| Windows | Windows 10 22H2 以降(64 ビット) | [最新のリリース](https://github.com/KikuchiTomo/Hajime/releases?q=windows&expanded=true) |
| Linux (WIP) | | 準備中 |

インストールしたら，一度ログアウトしてから，OS の入力ソースの設定で「はじめ」を追加してください．

## ライセンス

MIT License です([LICENSE](LICENSE))．

本ソフトウェアは azooKey(MIT)と Zenzai のモデル(Apache-2.0)を使用しています．著作権表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) と，アプリの設定画面の「情報」に記載しています．

脆弱性の報告は [SECURITY.md](SECURITY.md) をご覧ください．

English: [README.en.md](README.en.md)
