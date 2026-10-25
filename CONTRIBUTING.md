# 開発に参加する

## はじめに読むもの

1. [docs/dev/ARCHITECTURE.md](docs/dev/ARCHITECTURE.md): 構成と層
2. [docs/dev/GUIDELINES.md](docs/dev/GUIDELINES.md): 置き場所・名前・書き方
3. [docs/dev/SECURITY-MODEL.md](docs/dev/SECURITY-MODEL.md): 入力内容の扱い
4. [docs/specs/REQUIREMENTS.md](docs/specs/REQUIREMENTS.md): 要件

## 手順

1. Issue で何をするかを相談する(小さな修正は不要)．Issue はテンプレートから作る
2. ブランチを切る．名前は `<種類>/<内容>`(例: `feat/yen-key-policy`)
3. `make check` と `make test` を通す
4. PR のテンプレートに沿って説明を書き，`type:` のラベルを付ける
5. 検査が通ったらスカッシュマージする

main には直接 push できません．決まりの詳細は [docs/dev/REPOSITORY.md](docs/dev/REPOSITORY.md) にあります．

## 手元で試す

変換に Zenzai を使うには，先に `make fetch-models` でモデルを取得します(約 70MB．リポジトリの外の `../models/` に置かれます)．取得しなくてもビルドはでき，その場合は Zenzai なしで動きます．

目的に合わせて 3 つの方法があります．

| 方法 | コマンド | 向いている場面 |
|---|---|---|
| 入れずに試す | `make try` | 変換・補正・文節格子の結果だけを見たい．ターミナルでローマ字を打つと結果が出る |
| 開発版を入れる | `make dev-macos` | 実際のアプリで打ち心地を試したい．本番と並べて使える |
| 本番を入れる | `make install-macos` | 普段使いにする |

開発版は「s90.tokyo IME Dev」という別の入力ソースです．本番とはバンドル ID・学習データ・設定が分かれていて，メニューバーのアイコンは点線の枠になります．

- 入れる先は `/Library/Input Methods` なので，管理者のパスワードを聞かれます
- 初めて入れたときだけ，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から足す
- 2 回目からは `make dev-macos` で入れ直すだけでよい．古いプロセスは止まり，次にキーを打ったときに新しい版が動く
- 試し終わったら `make uninstall-dev-macos` で消す．学習データと設定も消すときは `make uninstall-dev-macos PURGE=--purge`

署名には Apple Development の証明書を使います(`security find-identity -v -p codesigning` で確かめられます)．証明書が複数あるときは `S90_SIGN_IDENTITY="Apple Development: 名前 (ID)" make dev-macos` のように選びます．証明書が無いとアドホック署名になり，入力ソースとして選べないことがあります．

見た目だけを確かめるときは，開発版のアプリを `--render-snapshots` 付きで起動すると，候補ウィンドウの画像を書き出します(`design/mockups/` の画像はこれで作っています)．

## PR のタイトルとコミット

スカッシュマージなので，**PR のタイトルがそのまま main のコミットになります**．Conventional Commits の形で，日本語で 1 行に書きます．スコープは必ず付けます．形が違うと検査(`pr-title`)が通りません．

```
feat(core): ¥ キーに割り当てる文字をプロファイルごとに決める
fix(macos): ターミナルで候補ウィンドウが入力位置からずれる
docs(adr): Windows で変換を別のプロセスで行う判断を記録する
```

スコープ: `core`，`macos`，`windows`，`protocol`，`design`，`docs`，`adr`，`skills`，`ci`，`repo`，`deps`

PR の中のコミットは main に残りませんが，同じ形で書いておくとレビューしやすくなります．

## Claude Code を使う場合

`.claude/skills/` にこのリポジトリ用のスキルがあります．`CLAUDE.md` の表のとおりに使われます．スキルを直すときは `skill-creator` を使い，`python3 -I tools/check/check_skills.py` を通してください．
