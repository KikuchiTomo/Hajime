# s90.tokyo IME

[![check](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/check.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
[![Engine](https://img.shields.io/badge/engine-azooKey%20%2B%20Zenzai-6b4fbb.svg)](https://github.com/azooKey/AzooKeyKanaKanjiConverter)

macOS / Windows / Linux 向けの日本語入力システムです。
かな漢字変換エンジンには、 [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) のエンジンを使用しています。

開発中のため，動きや設定は予告なく変わります．

## 機能

- ライブ変換機能
- 英単語変換機能 (日本語で入力すると固有名詞等を推測して英単語に変換します)
- 分岐図を使用した変換メニュー
- タイピングミスの補正 (Zenzaiで補正します)
- ローカルへの記録結果の保存 (補正した回数などを記録します)


## 今後開発される予定の機能および内容

Windows 版はまだありません．変換中のキーの割り当ては，設定の「キー操作」で変えられます．作る予定の一覧は [docs/specs/REQUIREMENTS.md](docs/specs/REQUIREMENTS.md) にあります．

## 入力内容について

IME 自体は通信を行いません。
セキュリティの観点から入力した文字列や前の文字列はメモリの中だけで扱います。ログ等にも出力することはありません。
詳しくは [docs/dev/SECURITY-MODEL.md](docs/dev/SECURITY-MODEL.md) にあります．

## インストール方法

ダウンロードサイト (準備中) からそれぞれの環境に合ったリリースをダウンロードしてください。

### Windows

### macOS

### Linux 


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

また、脆弱性については [SECURITY.md](SECURITY.md) の手順でお知らせいただけますとタスカリアス。

## ライセンス

MIT License です([LICENSE](LICENSE))．

### 謝辞

本ソフトウェアは、azooKey(MIT)と Zenzai のモデル(Apache-2.0)を使用しています。
著作権表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にあります．

English: [README.en.md](README.en.md)

