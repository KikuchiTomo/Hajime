# ドキュメント

s90.tokyo IME のドキュメントはすべてこのディレクトリに置きます．
`user/` はそのままドキュメントサイトの本文になり，`dev/` と `specs/` はサイトの「開発」の節として載せます(`site/PLAN.md`)．

```
docs/
├── user/                 使う人向け．サイトの本文
│   ├── tutorials/        はじめての人が順に進める手順(インストールから最初の変換まで)
│   ├── how-to/           目的別の手順(¥ キーを \ にする，ターミナルで英数に戻す など)
│   ├── reference/        設定項目・キー操作・プロファイルの一覧
│   └── explanation/      考え方の説明(ライブ変換と補正のしくみ，プライバシー)
├── dev/                  作る人向け
│   ├── ARCHITECTURE.md   構成と層
│   ├── GUIDELINES.md     置き場所・名前・書き方
│   ├── SECURITY-MODEL.md 守るものと決まり
│   ├── DESIGN-SYSTEM.md  見た目の決まり
│   ├── UPSTREAM.md       azooKey の fork との付き合い方
│   ├── REPOSITORY.md     GitHub の設定・ブランチ・PR・マージの決まり
│   ├── WINDOWS.md        Windows 版のプロセス・ビルド・確かめ方
│   ├── research/         設計の根拠にした調査(候補の出し方など)
│   └── adr/              設計の判断の記録
├── specs/                要件(REQUIREMENTS.md)と機能ごとの仕様
└── site/PLAN.md          ドキュメントサイトの計画
```

`user/` の 4 つの分け方は Diátaxis(https://diataxis.fr/)に従っています．書く前に，その文書が「学ぶため」「作業するため」「調べるため」「理解するため」のどれなのかを決め，1 つの文書に混ぜないようにします．

## 書き方

- 書き方の決まりは `.claude/skills/s90-docs/SKILL.md` にあります．Claude Code に書かせるときも，人が書くときも同じ決まりに従います
- 日本語を先に書き，英語は `<名前>.en.md` として後から足します．英語が無いページは，サイトでは日本語を表示します
- ページの先頭には frontmatter で `title` と `description` を書きます．サイトの生成器が読む項目です

```md
---
title: ¥ キーで \ を入力する
description: JIS キーボードの ¥ キーに割り当てる文字を変える手順
---
```

- 画像は同じディレクトリの `_images/` に置き，ファイル名は kebab-case にします
