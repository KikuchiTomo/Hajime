"""日本郵便の郵便番号データ(UTF-8 形式)を「郵便番号<タブ>住所」の表に整える．

- 住所は 都道府県 + 市区町村 + 町域．町域は次のように整える
  - 「以下に掲載がない場合」「〜の次に番地がくる場合」「〜一円」は町域を付けない(市区町村までの住所にする)
  - 括弧の中(「大通西（１〜１９丁目）」の「（１〜１９丁目）」)は除く．番地や丁目の範囲で，住所の候補には要らない
- 同じ郵便番号に町域がいくつもあるときは，重ねずに並べる(表に出てきた順)
- UTF-8 形式は 1 つの郵便番号を 1 行に書くので，行の結合は要らない
"""
import csv
import re
import sys

source, destination = sys.argv[1], sys.argv[2]
NO_TOWN = re.compile(r"(以下に掲載がない場合|の次に番地がくる場合|一円)$")
PAREN = re.compile(r"（.*?）|（.*$")

rows: dict[str, list[str]] = {}
with open(source, encoding="utf-8", newline="") as file:
    for record in csv.reader(file):
        code, prefecture, city, town = record[2], record[6], record[7], record[8]
        town = "" if NO_TOWN.search(town) else PAREN.sub("", town)
        address = prefecture + city + town
        addresses = rows.setdefault(code, [])
        if address not in addresses:
            addresses.append(address)

with open(destination, "w", encoding="utf-8", newline="\n") as out:
    out.write("# 郵便番号<タブ>住所(同じ郵便番号に住所がいくつもあるときはタブで続ける)\n")
    out.write("# 出典: 日本郵便株式会社 郵便番号データ(UTF-8 形式)．日本郵便株式会社は郵便番号データの著作権を主張しない\n")
    for code in sorted(rows):
        out.write(code + "\t" + "\t".join(rows[code]) + "\n")
