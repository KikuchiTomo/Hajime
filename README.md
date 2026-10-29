# はじめ

[![CI](https://github.com/KikuchiTomo/Hajime/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/KikuchiTomo/Hajime/actions/workflows/ci.yml)
[![CI Windows](https://github.com/KikuchiTomo/Hajime/actions/workflows/ci-windows.yml/badge.svg?branch=main)](https://github.com/KikuchiTomo/Hajime/actions/workflows/ci-windows.yml)
[![macOS](https://img.shields.io/github/v/release/KikuchiTomo/Hajime?filter=*-macos&include_prereleases&sort=semver&display_name=release&label=macOS&logo=apple)](https://github.com/KikuchiTomo/Hajime/releases)
[![Windows](https://img.shields.io/github/v/release/KikuchiTomo/Hajime?filter=*-windows&include_prereleases&sort=semver&display_name=release&label=Windows&logo=windows)](https://github.com/KikuchiTomo/Hajime/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Windows%2010%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
![Rust](https://img.shields.io/badge/Rust-1.90-b7410e.svg)
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

[Releases](https://github.com/KikuchiTomo/Hajime/releases) から，お使いの OS 向けのものをダウンロードしてください．

### macOS

macOS 14 以降で使えます．

1. `v0.1.2-macos` のような名前のリリースから `.pkg` をダウンロードし，開いてインストールします．開けないと表示されたら，システム設定 > プライバシーとセキュリティ で「このまま開く」を押し，もう一度開いてください．
2. ログアウトしてログインし直します．
3. システム設定 > キーボード > 入力ソース の「編集」で「+」を押し，日本語の「はじめ」を追加します．

新しいバージョンにするときは，新しい `.pkg` を入れるだけです．

### Windows

Windows 10 22H2 以降の 64 ビット版で使えます．

1. `v0.1.1-windows` のような名前のリリースから `.msi` をダウンロードし，開いてインストールします．SmartScreen の警告が出たら，「詳細情報」から「実行」を選んでください．
2. サインアウトしてサインインし直します．
3. 設定 > 時刻と言語 > 言語と地域 で「日本語」の「言語のオプション」を開き，「キーボードの追加」から「はじめ」を選びます．
4. Windows キー + Space で切り替えます．

詳しい手順は [Windows に入れる](docs/user/how-to/install-windows.md) にあります．

### Linux

まだ提供していません．

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

