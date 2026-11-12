# tools

| スクリプト | 役割 |
|---|---|
| `check/check_skills.py` | `.claude/skills/` のスキルの frontmatter と長さを確かめる |
| `check/check_settings_fields.py` | 設定のすべての項目が，macOS と Windows の設定の画面に部品を持ち，core のテストで値を変えて確かめられているかを確かめる(`make check`) |
| `macos/check_settings_ui.py` | Debug でビルドした Hajime Debug の設定の画面を System Events で操作し，すべての項目が使えるかを表にする(手で動かす) |
| `tokens/check_contrast.py` | デザイントークンの色の組み合わせのコントラスト比を確かめる |
| `tokens/generate_swift.py` | デザイントークンから macOS 用の Swift のコードを作る |
| `github/apply_repository_settings.sh` | GitHub のマージの方式・ルールセット・セキュリティの機能・ラベルを当てる |
| `macos/install.sh` | macOS の入力メソッドをビルドして入れる |
| `evaluation/fetch_ajimee.sh` | かな漢字変換の評価に使う AJIMEE-Bench を取得し，`evaluation/ajimee.py` で評価用の TSV にする(`make fetch-evaluation`) |
| `evaluation/complementarity.py` | 変換エンジンどうしの相補性(単独の正解率・どれかが正解した割合・食い違う割合と，差の信頼区間)を測る(`make evaluate-engines`) |
| `evaluation/reranking.py` | 検証木の点数で候補を並べ替えたときの効果(Acc@3・MRR)を，書き出した候補と点数から見積もる(`make evaluate-engines`) |
| `evaluation/wikidata_vocabulary.py` | Wikidata の仮名表記から，人名・地名・その他の語彙の変換を評価する `core/Evaluation/vocabulary-*.tsv` を作る |
| `site/make_feature_images.sh` | Debug の Hajime Debug が書き出した画面(`--render-snapshots`)から，公式サイトのトップページの画像を作る |
| `thesaurus/wordnet.py` | 日本語 WordNet(利用者が取得した XML)から，連想の辞書に取り込むファイルを作る |

Python のスクリプトは標準ライブラリだけで動く．
