"""Wikidata の仮名表記(P1814)から，語彙(固有名詞・複合語)の変換を評価する TSV を作る．

使い方:
    python3 -I tools/evaluation/wikidata_vocabulary.py <出力ディレクトリ> [--count N]

- 種類ごとに vocabulary-<種類>.tsv を書く．1 行は「読み(ひらがな)<タブ>日本語のラベル」で，hajime-playground --evaluate が読む形
  - person: 日本の国籍の人(P31=Q5，P27=Q17)
  - place: 日本にある人以外のもの(P17=Q17．市町村・駅・山・川・建物など)
  - other: 国の指定が無い，人と名前(姓・名)以外のもの(作品・組織・用語など)
- 辞書を足したときの効果を測るのが目的なので，Mozc や azooKey の辞書とは別の出どころを使う．Wikidata は CC0 なので，作ったファイルはリポジトリに置ける
- ラベルが漢字を含まないもの(カタカナ語やかなだけの語は変換しなくても当たる)，英数字や記号を含むもの，読みがかな以外を含むものは除く
- 読みの空白・中黒・＝は除く(人名の姓と名の区切り)．カタカナはひらがなにする
- 取り出す項目は，項目の ID と種類から作ったハッシュの順で先頭から --count 件．Wikidata が更新されると変わるので，作ったファイルをコミットして固定する

Wikidata Query Service に問い合わせる(開発者が手元で動かす道具．IME 本体は通信しない)
"""
import argparse
import csv
import hashlib
import io
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "hajime-evaluation/0.1 (https://github.com/KikuchiTomo/Hajime)"
CATEGORIES = {
    "person": "?item wdt:P31 wd:Q5 ; wdt:P27 wd:Q17 .",
    "place": "?item wdt:P17 wd:Q17 . FILTER NOT EXISTS { ?item wdt:P31 wd:Q5 }",
    # 姓や名そのものの項目(Q101352 姓，Q202444 名，Q12308941 男性の名，Q11879590 女性の名)は国が付かないので，ここに入らないよう除く
    "other": "FILTER NOT EXISTS { ?item wdt:P17 [] } FILTER NOT EXISTS { ?item wdt:P31 ?class . VALUES ?class { wd:Q5 wd:Q101352 wd:Q202444 wd:Q12308941 wd:Q11879590 } }",
}
# 続けて問い合わせると 429(Too Many Requests)が返るので，種類のあいだで待つ秒数
INTERVAL = 15
KANJI = re.compile(r"[㐀-䶿一-鿿豈-﫿々〆ヶ]")
LABEL = re.compile(r"^[ぁ-ゖァ-ヺー㐀-䶿一-鿿豈-﫿々〆ヶ]+$")
READING = re.compile(r"^[ぁ-ゖー]+$")
SEPARATORS = str.maketrans("", "", " 　・＝=")
KATAKANA_TO_HIRAGANA = {code: code - 0x60 for code in range(0x30A1, 0x30F7)}

parser = argparse.ArgumentParser()
parser.add_argument("destination")
parser.add_argument("--count", type=int, default=300)
parser.add_argument("--min-length", type=int, default=2)
parser.add_argument("--max-length", type=int, default=12)
arguments = parser.parse_args()


def query(pattern):
    # 並べ替え(ORDER BY)やページ分け(OFFSET)を付けると Query Service の時間の上限(60 秒)を超えるので，種類ごとに 1 回で取り，並べ替えは手元で行う
    sparql = f"""SELECT ?item ?label ?kana WHERE {{
  ?item wdt:P1814 ?kana ; rdfs:label ?label .
  FILTER(LANG(?label) = "ja")
  {pattern}
}}"""
    url = ENDPOINT + "?" + urllib.parse.urlencode({"query": sparql})
    request = urllib.request.Request(url, headers={"Accept": "text/csv", "User-Agent": USER_AGENT})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return list(csv.DictReader(io.StringIO(response.read().decode("utf-8"))))
        except OSError as error:
            print(f"問い合わせに失敗しました({error})．やり直します", file=sys.stderr)
            time.sleep(10 * (attempt + 1))
    sys.exit("Wikidata Query Service から取れませんでした")


def normalize(label, kana):
    reading = kana.translate(SEPARATORS).translate(KATAKANA_TO_HIRAGANA)
    if not (arguments.min_length <= len(label) <= arguments.max_length):
        return None
    if not LABEL.match(label) or not KANJI.search(label) or not READING.match(reading):
        return None
    return reading, label


destination = pathlib.Path(arguments.destination)
destination.mkdir(parents=True, exist_ok=True)
for name, pattern in CATEGORIES.items():
    rows = query(pattern)
    time.sleep(INTERVAL)
    # 同じ項目に仮名表記やラベルが複数あるときは，項目ごとに最初の組だけを使う
    items = {}
    for row in rows:
        entry = normalize(row["label"], row["kana"])
        if entry and row["item"] not in items:
            items[row["item"]] = entry
    # 同じ読みと表記の組は 1 つにまとめる
    unique = {}
    for item, entry in items.items():
        unique.setdefault(entry, item)
    ordered = sorted(unique.items(), key=lambda pair: hashlib.sha256(f"{name}:{pair[1]}".encode()).hexdigest())
    chosen = ordered[: arguments.count]
    path = destination / f"vocabulary-{name}.tsv"
    with open(path, "w", encoding="utf-8") as file:
        file.write(f"# 語彙の変換の評価用({name})．Wikidata(CC0)の仮名表記(P1814)とラベル．tools/evaluation/wikidata_vocabulary.py が作る．読み<TAB>表記\n")
        for (reading, label), item in sorted(chosen, key=lambda pair: pair[0]):
            file.write(f"{reading}\t{label}\n")
    print(f"書きました: {path}({len(chosen)} 件．候補 {len(unique)} 件から)", file=sys.stderr)
