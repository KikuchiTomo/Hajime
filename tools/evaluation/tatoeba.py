"""Tatoeba の日本語の文のふりがな(transcriptions.csv)から，hajime-playground --evaluate が読む TSV(読み<TAB>期待する変換)を作る．

使い方:
    python3 -I tools/evaluation/tatoeba.py <transcriptions.csv> <出力.tsv> [--all]

- 使うのは，人が付けた(作業した人の名前がある)日本語のふりがなだけ．「[弾|ひ]ける」の括弧を外して期待する変換にし，ふりがなとかなを読みにする．
  カタカナの語(ギター)は読みをひらがなにする(打つときはひらがなで打つため)
- 除く文: 英字・数字を含む文，期待する変換が 5 文字より短いか 40 文字より長い文，読みにかなと句読点以外が残る文
- 既定では，文の番号の SHA-256 で SAMPLE_MODULUS 文に 1 文を選ぶ(同じ書き出しからは同じ文が選ばれる)．--all ならすべて
"""
import hashlib
import re
import sys

SAMPLE_MODULUS = 50
MIN_LENGTH = 5
MAX_LENGTH = 40
KATAKANA_TO_HIRAGANA = {code: code - 0x60 for code in range(0x30A1, 0x30F7)}
FURIGANA = re.compile(r"\[([^|\]]+)((?:\|[^|\]]*)+)\]")
LATIN_OR_DIGIT = re.compile(r"[A-Za-z0-9Ａ-Ｚａ-ｚ０-９]")
READING = re.compile(r"[ぁ-ゖー、。？！「」…・]+")

if len(sys.argv) not in (3, 4):
    sys.exit(__doc__)
source, destination = sys.argv[1:3]
everything = "--all" in sys.argv[3:]

rows = []
with open(source, encoding="utf-8") as file:
    for line in file:
        columns = line.rstrip("\n").split("\t")
        # 番号<TAB>言語<TAB>文字の種類<TAB>付けた人<TAB>ふりがな付きの文．付けた人が無い(\N)ものは自動で付いたふりがな
        if len(columns) < 5 or columns[1] != "jpn" or columns[3] in ("", "\\N"):
            continue
        number, marked = columns[0], columns[4]
        text = FURIGANA.sub(lambda match: match.group(1), marked)
        reading = FURIGANA.sub(lambda match: "".join(match.group(2).split("|")[1:]), marked).translate(KATAKANA_TO_HIRAGANA)
        if LATIN_OR_DIGIT.search(text) or not MIN_LENGTH <= len(text) <= MAX_LENGTH or not READING.fullmatch(reading):
            continue
        if not everything and int(hashlib.sha256(number.encode()).hexdigest(), 16) % SAMPLE_MODULUS != 0:
            continue
        rows.append((int(number), reading, text))

with open(destination, "w", encoding="utf-8") as output:
    for _, reading, text in sorted(rows):
        output.write(f"{reading}\t{text}\n")
print(f"{len(rows)} 文を書きました: {destination}", file=sys.stderr)
