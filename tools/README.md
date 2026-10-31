# tools

| スクリプト | 役割 |
|---|---|
| `check/check_skills.py` | `.claude/skills/` のスキルの frontmatter と長さを確かめる |
| `tokens/check_contrast.py` | デザイントークンの色の組み合わせのコントラスト比を確かめる |
| `tokens/generate_swift.py` | デザイントークンから macOS 用の Swift のコードを作る |
| `github/apply_repository_settings.sh` | GitHub のマージの方式・ルールセット・セキュリティの機能・ラベルを当てる |
| `macos/install.sh` | macOS の入力メソッドをビルドして入れる |
| `evaluation/fetch_ajimee.sh` | かな漢字変換の評価に使う AJIMEE-Bench を取得し，`evaluation/ajimee.py` で評価用の TSV にする(`make fetch-evaluation`) |
| `evaluation/wikidata_vocabulary.py` | Wikidata の仮名表記から，人名・地名・その他の語彙の変換を評価する `core/Evaluation/vocabulary-*.tsv` を作る |
| `thesaurus/wordnet.py` | 日本語 WordNet(利用者が取得した XML)から，連想の辞書に取り込むファイルを作る |

Python のスクリプトは標準ライブラリだけで動く．
