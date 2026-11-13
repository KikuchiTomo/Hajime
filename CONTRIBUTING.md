# 開発に参加する

## はじめに読むもの

1. [docs/dev/ARCHITECTURE.md](docs/dev/ARCHITECTURE.md): 構成と層
2. [docs/dev/GUIDELINES.md](docs/dev/GUIDELINES.md): 置き場所・名前・書き方
3. [docs/dev/SECURITY-MODEL.md](docs/dev/SECURITY-MODEL.md): 入力内容の扱い
4. [docs/specs/REQUIREMENTS.md](docs/specs/REQUIREMENTS.md): 要件

## 手順

1. Issue で何をするかを相談する(小さな修正は不要)．Issue はテンプレートから作る
2. ブランチを切る．名前は `<種類>/<内容>`(例: `feat/yen-key-policy`)
3. `make fetch-models` で Zenzai モデルを取得し，`make check` と `make test` を通す(モデルが無いと本物の Zenzai のテストを飛ばす)
4. 利用者から見える変更なら，[CHANGELOG.md](CHANGELOG.md) の「未リリース」に 1 行で書く(リリースノートとアプリの「更新を確認」の変更点になる)．節の中は「追加」「変更」「修正」の見出しで分け，macOS と Windows の片方だけの変更は行の頭に「macOS:」「Windows:」を付ける．句読点は「，」「．」で，行の終わりにも「．」を付ける(「！」や絵文字で終わる行は除く)．PR 番号は書かない(GitHub のリリースノートには，マージした PR の一覧が別に付く)．バージョンを上げると `tools/release/bump_version.sh` が「未リリース」を新しいバージョンの節に移す．バージョンを上げる PR(タイトルが `chore(release)`)では，CI(`.github/workflows/metrics.yml`)が前のリリースと比べたかな漢字変換の指標(AJIMEE-Bench・Tatoeba などの正解率．R-25)を PR にコメントする．手元では `make release-metrics` で同じ表を作れる．書きぶりは `.claude/skills/hajime-docs` の「文体」に従う
5. PR のテンプレートに沿って説明を書き，`type:` のラベルを付ける
6. 検査が通ったらスカッシュマージする

main には直接 push できません．決まりの詳細は [docs/dev/REPOSITORY.md](docs/dev/REPOSITORY.md) にあります．

## 手元で試す

変換に Zenzai を使うには，先に `make fetch-models` でモデルを取得します(約 70MB．リポジトリの外の `../models/` に置かれます)．取得しなくてもビルドはでき，その場合は Zenzai なしで動きます．

目的に合わせて 3 つの方法があります．

| 方法 | コマンド | 向いている場面 |
|---|---|---|
| 入れずに試す | `make try` | 変換・補正・文節格子の結果だけを見たい．ターミナルでローマ字を打つと結果が出る |
| 開発版を入れる | `make dev-macos` | 実際のアプリで打ち心地を試したい．本番と並べて使える |
| 本番を入れる | `make install-macos` | 普段使いにする |

開発版は「Hajime IME Dev」という別の入力ソースです．本番とはバンドル ID・学習データ・設定が分かれていて，メニューバーのアイコンは点線の枠になります．

- 入れる先は `/Library/Input Methods` なので，管理者のパスワードを聞かれます
- 初めて入れたときだけ，一度ログアウトしてログインし直し，システム設定 > キーボード > 入力ソース の「+」から足す
- 2 回目からは `make dev-macos` で入れ直すだけでよい．古いプロセスは止まり，次にキーを打ったときに新しいバージョンが動く
- 試し終わったら `make uninstall-dev-macos` で消す．学習データと設定も消すときは `make uninstall-dev-macos PURGE=--purge`

署名の証明書は，すでに入っているバージョンと同じチームのものを選びます．macOS はアプリのデータの置き場所(コンテナ，`~/Library/Containers/<バンドル ID>`)を最初に作ったアプリの署名のチームに結び付けていて，違うチームで署名したバージョンを入れると起動の途中で止まり，入力できなくなるためです．

- 入っているバージョンが証明書で署名されていれば，それと同じチームの証明書を使う．キーチェーンに無ければ入れるのをやめる
- アプリだけ消して置き場所が残っているときは，置き場所を作った署名が分からないので入れるのをやめる
- アドホック署名のバージョンが入っていて置き場所があるときは，証明書で署名すると止まるおそれがあるので入れるのをやめる．アドホック署名のまま入れ直すときは `HAJIME_SIGN_IDENTITY=-` を付ける
- 入っているバージョンが証明書で署名されておらず，置き場所も無いとき(初めて入れるときなど)は，Apple Development の最初の証明書を使う(`security find-identity -v -p codesigning` で確かめられる)．証明書が 1 つも無ければアドホック署名になり，入力ソースとして選べないことがある
- 別の証明書を使うときは `HAJIME_SIGN_IDENTITY="Apple Development: 名前 (ID)" make dev-macos` のように選ぶ

止まったときに学習データと設定を消してよければ，先にアプリを消し(`make uninstall-macos` か `make uninstall-dev-macos`)，Finder で置き場所をゴミ箱に入れてから入れ直します．

見た目だけを確かめるときは，Debug でビルドした「Hajime Debug」(`apps/macos/build/Build/Products/Debug/`)を `--render-snapshots` 付きで起動すると，候補ウィンドウと設定の画面の画像を書き出します(`design/mockups/` の画像はこれで作っています)．Debug は開発版と別のバンドル ID なので，入れた開発版のデータには触れません．

設定の画面のすべての項目が使えるかは，Debug でビルドした「Hajime Debug」を `python3 -I tools/macos/check_settings_ui.py` で操作して確かめます(手で動かす道具で，CI では動かしません)．スイッチ・選択肢・ステッパー・スライダーを順に操作し，設定のファイルの項目が変わるか，範囲の端で止まるか，ほかの項目が使える・使えないに切り替わるか，「既定に戻す」で戻るかを表にします．Debug の設定の置き場所はほかの Debug と共有なので，始める前に丸ごと控えを取り，終わったら元に戻します．操作には，ターミナルに「アクセシビリティ」の許可が要ります．

設定の項目を足したら，macOS と Windows の両方の設定の画面に部品を置き，core のテストで値を変えて動きを確かめます．`make check` の `tools/check/check_settings_fields.py` が，部品かテストの無い項目を知らせます．

開発版のバンドル ID は 2026-10-26 に `men.haji.inputmethod.dev` から `.develop` に変えました．前の開発版を入れていた場合は，システム設定 > キーボード > 入力ソース で前の「Hajime Dev」を外し，新しく足し直してください．前の開発版の学習データと設定(`~/Library/Containers/men.haji.inputmethod.dev`)は使わないので，Finder で消してかまいません．

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

`.claude/skills/` にこのリポジトリ用のスキルがあります．`CLAUDE.md` の表のとおりに使われます．スキルを直すときは `skill-creator` を使い，`python3 -I tools/check/check_skills.py` を通してください．`skill-creator`・`frontend-design`・`webapp-testing` は [anthropics/skills](https://github.com/anthropics/skills) のもので，Apache License 2.0 です(各ディレクトリの `LICENSE.txt`)．
