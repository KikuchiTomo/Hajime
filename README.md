# s90.tokyo IME

[![CI](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
[![Engine](https://img.shields.io/badge/engine-azooKey%20%2B%20Zenzai-6b4fbb.svg)](https://github.com/azooKey/AzooKeyKanaKanjiConverter)

macOS / Windows / Linux 向けの日本語入力システムです。
かな漢字変換エンジンには、 [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) のエンジンを使用しています。

開発中のため，仕様は余儀なく変更される可能性があります．

## 機能

- ライブ変換機能
- 英単語変換機能 (日本語で入力すると固有名詞等を推測して英単語に変換します)
- 分岐図を使用した変換メニュー
- タイピングミスの補正 (自動補正機能)
- ローカルへの記録結果の保存 (補正した回数などを記録します)
- 高いカスタマイズ性
- 言い換え変換

## インストール方法

ダウンロードサイト (準備中) からそれぞれの環境に合ったリリースをダウンロードしてください。

### Windows / macOS
最新バージョンをGitHubリリースからダウンロードできます．

### Linux 
開発中のため提供されていません．

## 開発

開発するかたは以下のドキュメントに手順が記載されています。
また、ブランチと PR の規約については [CONTRIBUTING.md](CONTRIBUTING.md) を参照ください。

| 文書 | 内容 |
|---|---|
| [docs/dev/ARCHITECTURE.md](docs/dev/ARCHITECTURE.md) | 構成と層 |
| [docs/dev/GUIDELINES.md](docs/dev/GUIDELINES.md) | 置き場所・名前・書き方 |
| [docs/dev/DESIGN-SYSTEM.md](docs/dev/DESIGN-SYSTEM.md) | 見た目の決まり |
| [docs/dev/adr/README.md](docs/dev/adr/README.md) | 設計の判断の記録 |
| [docs/README.md](docs/README.md) | ドキュメントの地図 |

また、脆弱性については [SECURITY.md](SECURITY.md) の手順でお知らせいただけますと助かります．

## ライセンス

MIT License です([LICENSE](LICENSE))．

### 謝辞

本ソフトウェアは、azooKey(MIT)と Zenzai のモデル(Apache-2.0)を使用しています．
著作権表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 及び本ソフトウェア内で提示されています．

English: [README.en.md](README.en.md)

