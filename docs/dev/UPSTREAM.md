# azooKey の fork との付き合い方

はじめは azooKey から分かれて独自に進めます．ただし変換エンジンの改善は今後も azooKey 側で続くので，取り込める状態は保っておきます．

## fork

| fork | 元 | 使いかた |
|---|---|---|
| [KikuchiTomo/AzooKeyKanaKanjiConverter](https://github.com/KikuchiTomo/AzooKeyKanaKanjiConverter) | azooKey/AzooKeyKanaKanjiConverter | `core/` が SwiftPM で revision を指定して使う．エンジンに手を入れるときはここで変える |
| [KikuchiTomo/azooKey-Desktop](https://github.com/KikuchiTomo/azooKey-Desktop) | azooKey/azooKey-Desktop | macOS の入力メソッドの実装の参照元．コードはこのリポジトリに移しながら作り直す |
| [KikuchiTomo/azooKey-Windows](https://github.com/KikuchiTomo/azooKey-Windows) | fkunn1326/azooKey-Windows | Windows の TSF とエンジンの分け方の参照元 |

いずれも MIT License です．コードを移したファイルには，元のリポジトリとコミットを先頭のコメントに書き，`THIRD_PARTY_NOTICES.md` に著作権表示を残します．

## 手元の置き場所

```
~/repos/s90.tokyo-IME/
├── .bare/ , .git         このリポジトリ(bare とワークツリーの構成)
├── default/              main のワークツリー
└── upstream/             fork の clone．origin が fork，upstream が元のリポジトリ
    ├── AzooKeyKanaKanjiConverter/
    ├── azooKey-Desktop/
    └── azooKey-Windows/
```

## 取り込む手順

1. `upstream/<名前>` で `git fetch upstream` し，前回取り込んだコミットからの差分を読む
2. 取り込むコミットを決め，fork の `main` に merge する(エンジンの場合)．アプリのコードは，必要な部分だけをこのリポジトリの設計に合わせて書き直す
3. エンジンの場合は `core/Package.swift` の revision を上げ，`make test` を通す
4. PR に元のコミットの URL と，取り込んだ理由・取り込まなかった部分を書く

取り込みの作業の進め方は `.claude/skills/hajime-upstream-port/SKILL.md` にまとめています．
