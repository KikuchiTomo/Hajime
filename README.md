# s90.tokyo IME

macOS と Windows で使える日本語入力システムです．かな漢字変換には [azooKey](https://github.com/azooKey) のエンジンを使っています．

> 開発中です．macOS 版はローマ字入力・ライブ変換・候補の選択・文節格子・タイプミスの補正・¥ キーの設定が使えます．Windows 版はまだありません．

## macOS に入れる

Xcode 26，XcodeGen(`brew install xcodegen`)と，署名に使う Apple Development の証明書が要ります．

```sh
make install-macos
```

初めて入れたときは，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から「s90.tokyo IME」を足してください．開発中に試す方法は [CONTRIBUTING.md](CONTRIBUTING.md) にあります．

## 目指していること

- ライブ変換．確定キーを押さなくても，打ちながら漢字かな混じりで表示します
- タイプミスの自動補正．`pyてょn` や `pthon` を `python` に直し，Space で打ったままの文字に戻せます
- 変換中，候補の上に「そのまま・カタカナ・半角カタカナ・全角英数・半角英数」の行を出し，上キーで選べます
- 文が長いときは，候補を文節ごとの列に並べる「文節格子」で出し，誤った文節だけを直せます
- JIS キーボードの ¥ キーで何を入れるかを，設定ひとつで変えられます(既定は `\`)
- ローマ字入力・かな入力に加えて，英語のまま打って日本語の候補を出す入力方式があります
- エディタやターミナルでは，記号を半角にし，コマンドの入力を邪魔しません
- 入力した内容は端末の外に出しません．既定では通信しません

要件の一覧は [docs/specs/REQUIREMENTS.md](docs/specs/REQUIREMENTS.md) にあります．

## ドキュメント

- [ドキュメントの地図](docs/README.md)
- [アーキテクチャ](docs/dev/ARCHITECTURE.md)
- [ガイドライン](docs/dev/GUIDELINES.md)
- [セキュリティモデル](docs/dev/SECURITY-MODEL.md)
- [デザインシステム](docs/dev/DESIGN-SYSTEM.md)
- [設計の判断の記録](docs/dev/adr/README.md)

## 開発に参加する

[CONTRIBUTING.md](CONTRIBUTING.md) を読んでください．脆弱性の報告は [SECURITY.md](SECURITY.md) の手順でお願いします．

## ライセンス

MIT License です([LICENSE](LICENSE))．azooKey をはじめとする元のソフトウェアの著作権表示は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にあります．

English: [README.en.md](README.en.md)
