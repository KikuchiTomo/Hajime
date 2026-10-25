# 開発に参加する

## はじめに読むもの

1. [docs/dev/ARCHITECTURE.md](docs/dev/ARCHITECTURE.md): 構成と層
2. [docs/dev/GUIDELINES.md](docs/dev/GUIDELINES.md): 置き場所・名前・書き方
3. [docs/dev/SECURITY-MODEL.md](docs/dev/SECURITY-MODEL.md): 入力内容の扱い
4. [docs/specs/REQUIREMENTS.md](docs/specs/REQUIREMENTS.md): 要件

## 手順

1. Issue で何をするかを相談する(小さな修正は不要)
2. ブランチを切る．名前は `<種類>/<内容>`(例: `feat/yen-key-policy`)
3. `make check` と `make test` を通す
4. PR のテンプレートに沿って説明を書く

## コミット

Conventional Commits の形で，日本語で 1 行に書きます．スコープは必ず付けます．

```
feat(core): ¥ キーに割り当てる文字をプロファイルごとに決める
fix(macos): ターミナルで候補ウィンドウが入力位置からずれる
docs(adr): Windows で変換を別のプロセスで行う判断を記録する
```

スコープ: `core`，`macos`，`windows`，`protocol`，`design`，`docs`，`adr`，`skills`，`ci`，`repo`

## Claude Code を使う場合

`.claude/skills/` にこのリポジトリ用のスキルがあります．`CLAUDE.md` の表のとおりに使われます．スキルを直すときは `skill-creator` を使い，`python3 -I tools/check/check_skills.py` を通してください．
