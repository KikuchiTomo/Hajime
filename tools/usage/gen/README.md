# tools/usage/gen

Mozc の辞書から同音異義語のグループを抜き出し，claude -p で用例を生成して，japanese-usage-dictionary と同じ TSV 形式の辞書を作るスクリプト群です．

```
読み<TAB>表記<TAB>活用型<TAB>説明。「用例」「用例」
ほしょう	保証	*	確かだということに責任を持つこと。「借金の保証人」
```

できた out/usage_dict_extra.tsv を data/usage/usage_dict_extra.tsv に置くと，アプリが data/usage/usage_dict.txt に続けて読みます．

## 準備

```sh
./setup.sh
```

setup.sh は次の内容を順に確認し，足りないものがあれば案内を出します．何度実行しても問題ありません．

1. Ruby 3.0 以上があるか．標準ライブラリだけで動くので gem のインストールは不要です．
2. claude コマンドがあるか．無い場合は公式インストーラを実行するか確認します．Homebrew を使う場合は `brew install --cask claude-code` でも入ります．
3. claude -p で実際にモデルを呼べるか．Haiku に1回だけ短い問い合わせをします．
4. Mozc の dictionary_oss と japanese-usage-dictionary を data/ にダウンロードします．

3 で失敗した場合はログインが済んでいません．Pro や Max などのサブスクリプションで使う場合は，ターミナルで一度 `claude` を起動してブラウザでログインし，`/exit` で抜けてから setup.sh を再実行してください．API キーで使う場合は `ANTHROPIC_API_KEY` を設定します．このとき `CLAUDE_BARE=1` も付けると，`~/.claude` のフックやプラグインを読み込まずに動きます．

API キーを 1Password に保存している場合は，キーを出力するコマンドを `CLAUDE_API_KEY_HELPER` に設定します．claude はこのコマンドを apiKeyHelper として呼び出してキーを受け取るので，キーをシェルやファイルに書かずに済みます．

```sh
export CLAUDE_BARE=1
export CLAUDE_API_KEY_HELPER="op read op://Personal/ANTHROPIC_API_KEY/credential"
```

`op run` で `ANTHROPIC_API_KEY` を渡す方法は，Claude Code のセッションの中から実行すると環境変数が claude に届かず，ログインしていない扱いになります．

## 使い方

```sh
ruby extract_groups.rb          # 対象グループを抽出 → work/groups.jsonl
ruby generate.rb --limit 50     # Haiku で50グループ分を生成 → work/generated.jsonl
ruby verify.rb                  # Sonnet で校閲 → work/verified.jsonl
ruby build_tsv.rb               # → out/usage_dict_extra.tsv と work/review.tsv
```

generate.rb と verify.rb は途中で止めても，同じコマンドを再実行すれば続きから処理します．応答の形式が崩れたグループや失敗したバッチは保存されないので，再実行するとそのグループだけ再度処理されます．全件を流すときは `--limit` を外し，`-j 4` などで並列数を増やしてください．

build_tsv.rb に `--merge data/usage_dict.txt` を付けると，元の usage_dict.txt と合わせた1ファイルを出力します．校閲で修正や除外が入ったものは work/review.tsv に修正前と修正後を並べて出すので，人が目を通すのはこのファイルだけで足ります．

## 抽出の仕組み

extract_groups.rb は Mozc の辞書から，同じ読みと品詞で漢字表記が2つ以上あるものを集めます．対象は一般名詞，サ変名詞，形容動詞語幹などの名詞と，動詞と形容詞の基本形です．`--max-cost` は Mozc のコスト値で，小さいほどよく使われる語だけに絞られます．現在の辞書で試した件数は次のとおりです．

| --max-cost | グループ数 |
|---|---|
| 6000 | 約2,100 |
| 6500 | 約3,500 |
| 7000 | 約5,300 |
| 7500 | 約7,300 |
| 8000 | 約9,600 |
| 9000 | 約12,200 |
| 10000（既定） | 約13,300 |

並び順は2番目によく使われる表記のコストの昇順です．上位の表記がどちらもよく使われる読みほど，ユーザーが選択に迷う場面が多いと考えて先頭に置いています．

次のものは同音異義語ではないため，抽出の段階で除外します．

- 送り仮名や漢字とかなの書き分けだけの違い．買取と買い取り，ご存じとご存知などが該当します．
- 4月と四月のような数字の表記違い．
- カイワレ大根とかいわれ大根のようなカタカナとひらがなの書き分けと，剝がれると剥がれるのような異体字の違い．
- たくさん生まれのように，かなで書いた副詞などに語が続く句と，今の時期や目を留めるのように助詞で語をつないだ句．元の語のグループで扱います．
- 講座内や事故後のように，辞書にある語に接尾辞が付いただけの複合語．
- 気になっ のような句の断片．
- すでに usage_dict.txt に載っている読み．`--include-partial` を付けると，載っていない表記がある読みは残します．

## プロンプトの調整

生成と校閲のシステムプロンプトは prompts/ にあります．説明の長さや用例の数を変えたいときは，このファイルを編集してください．モデルは `--model` か環境変数 `GEN_MODEL` と `VERIFY_MODEL` で変更できます．haiku，sonnet，opus のような別名と，正式なモデル名のどちらも指定できます．

## claude -p の呼び出し方

lib/common.rb は1回の呼び出しごとに空の一時ディレクトリで claude -p を起動します．プロジェクトの CLAUDE.md や .mcp.json を読み込まないようにするためです．あわせて次のオプションを付けています．

- `--system-prompt` で Claude Code 標準のシステムプロンプトを置き換えます．
- `--tools ""` ですべてのツールを無効にし，テキストを受け取って JSON を返すだけの呼び出しにします．
- `--json-schema` と `--output-format json` で，結果を `structured_output` から受け取ります．
- `--no-session-persistence` で，大量の呼び出しが履歴に残らないようにします．

環境変数 `CLAUDE_MAX_BUDGET_USD` を設定すると，1回の呼び出しの上限額として `--max-budget-usd` を渡します．

## 費用の目安

パイロットとして50グループを流したときの，claude -p が報告した推定額は次のとおりです．

- 生成（Haiku，10グループずつ，3並列）は約0.03ドルで，1分ほどかかりました．
- 校閲（Sonnet）は約0.35ドルで，30秒ほどかかりました．

既定の約13,300グループを全件流したときの実績は，生成（Haiku）が約3.3ドル，校閲（Sonnet，8並列）が約26ドルで，あわせて2時間ほどかかりました．残ったのは約6,100読み，14,500行です．コストが大きい，つまりあまり使われない表記を含むグループほど，辞書の誤りやまれな表記として除かれる割合が上がります．表記が1つしか残らないグループは TSV に入らないので，コスト 6000 までは8割ほど，7500 を超えると3割ほどしか残りません．サブスクリプションでログインしている場合は課金ではなくプランの利用枠を消費するので，利用上限に注意してください．校閲を上位のグループだけに絞る場合は `ruby verify.rb --limit 500` のように指定します．

## ライセンス

スクリプトは MIT ライセンスで配布できます．data/ に入る辞書データはそれぞれのライセンスに従います．

- Mozc dictionary_oss は IPAdic のライセンスと ICOT の条件の対象です．data/MOZC_DICTIONARY_README.txt を参照してください．
- japanese-usage-dictionary は BSD-2-Clause です．data/USAGE_DICT_LICENSE を参照してください．

生成結果の TSV には Mozc の表記がそのまま含まれます．配布するときは上記の表示を THIRD_PARTY_NOTICES などにまとめて同梱してください．prompts/generate_system.md の文体見本は usage_dict.txt から数行引用しています．
