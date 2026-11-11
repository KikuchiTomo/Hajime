"""日本郵便の郵便番号データを「郵便番号<タブ>住所」の表に整える．

使い方: normalize.py <utf_ken_all.csv> <jigyosyo.csv> <出力先>

- 町域の郵便番号(UTF-8 形式の全国一括)の住所は 都道府県 + 市区町村 + 町域．町域は次のように整える
  - 「以下に掲載がない場合」「〜の次に番地がくる場合」「〜一円」は町域を付けない(市区町村までの住所にする)
  - 括弧の中(「大通西（１〜１９丁目）」の「（１〜１９丁目）」)は除く．番地や丁目の範囲で，住所の候補には要らない
- 大口事業所の個別の郵便番号(Shift_JIS)は，次の 3 つを並べる
  - 住所(都道府県 + 市区町村 + 町域 + 番地など)
  - 住所と事業所名(全角の空白でつなぐ)
  - 事業所名
- 同じ郵便番号に住所がいくつもあるときは，重ねずに並べる(町域，事業所の順．それぞれ表に出てきた順)
- UTF-8 形式は 1 つの郵便番号を 1 行に書くので，行の結合は要らない
"""
import csv
import re
import sys

areas_source, offices_source, destination = sys.argv[1], sys.argv[2], sys.argv[3]
NO_TOWN = re.compile(r"(以下に掲載がない場合|の次に番地がくる場合|一円)$")
PAREN = re.compile(r"（.*?）|（.*$")
SEPARATOR = "　"

rows: dict[str, list[str]] = {}


def add(code: str, text: str) -> None:
    texts = rows.setdefault(code, [])
    if text and text not in texts:
        texts.append(text)


with open(areas_source, encoding="utf-8", newline="") as file:
    for record in csv.reader(file):
        code, prefecture, city, town = record[2], record[6], record[7], record[8]
        town = "" if NO_TOWN.search(town) else PAREN.sub("", town)
        add(code, prefecture + city + town)

with open(offices_source, encoding="cp932", newline="") as file:
    for record in csv.reader(file):
        name, prefecture, city, town, block, code = (field.strip() for field in record[2:8])
        address = prefecture + city + town + block
        add(code, address)
        add(code, address + SEPARATOR + name)
        add(code, name)

with open(destination, "w", encoding="utf-8", newline="\n") as out:
    out.write("# 郵便番号<タブ>住所(同じ郵便番号に住所がいくつもあるときはタブで続ける．事業所の郵便番号は住所・住所と事業所名・事業所名)\n")
    out.write("# 出典: 日本郵便株式会社 郵便番号データ(UTF-8 形式)と大口事業所個別番号データ．日本郵便株式会社はどちらの著作権も主張しない\n")
    for code in sorted(rows):
        out.write(code + "\t" + "\t".join(rows[code]) + "\n")
