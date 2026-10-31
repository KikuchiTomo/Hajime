"""AJIMEE-Bench(JWTD_v2/v1 の evaluation_items.json)を，hajime-playground --evaluate が読む TSV にする．

使い方:
    python3 -I tools/evaluation/ajimee.py <evaluation_items.json> <出力.tsv>

- 1 行は「読み<タブ>期待する変換(| で区切って複数)<タブ>左の文脈」
- 読みはカタカナで書かれているので，ひらがなにする(conversion-basic.tsv と同じ形にそろえるため)
- 区切りに使うタブ・改行・| を含む項目は書かない(今のデータには無いが，取り違えた行を作らないため)

取得と SHA-256 の確認は tools/evaluation/fetch_ajimee.sh が行う．データは CC-BY-SA 3.0 なのでリポジトリに入れない
"""
import json
import sys

if len(sys.argv) != 3:
    sys.exit(__doc__)

source, destination = sys.argv[1], sys.argv[2]

# カタカナ(ァ〜ヶ)をひらがなにする．スカラー値の表で変える(applyingTransform と同じく OS で結果が変わらないように)
KATAKANA_TO_HIRAGANA = {code: code - 0x60 for code in range(0x30A1, 0x30F7)}


def usable(text):
    return not any(separator in text for separator in ("\t", "\n", "\r", "|"))


with open(source, encoding="utf-8") as file:
    items = json.load(file)

lines = ["# AJIMEE-Bench(JWTD_v2/v1)．CC-BY-SA 3.0．tools/evaluation/fetch_ajimee.sh が作る．読み<TAB>期待する変換<TAB>左の文脈"]
skipped = 0
for item in items:
    reading = item["input"].translate(KATAKANA_TO_HIRAGANA)
    expected = item["expected_output"]
    context = item["context_text"]
    if not expected or not all(usable(text) for text in [reading, context, *expected]):
        skipped += 1
        continue
    lines.append("\t".join([reading, "|".join(expected), context]))

with open(destination, "w", encoding="utf-8") as file:
    file.write("\n".join(lines) + "\n")
print(f"{len(lines) - 1} 件を書きました(飛ばした項目: {skipped})", file=sys.stderr)
