"""日本語 WordNet(WN-LMF の XML．wnja 2.x)から，連想の辞書(R-18)に取り込むファイルを作る．

使い方:
    python3 -I tools/thesaurus/wordnet.py <wnja-2.1.xml> <出力.tsv> [--min-count N] [--max-words N] [--label-length N]

- 1 行が 1 つの意味(synset)．「意味の説明<タブ>単語<タブ>単語…」の形(AssociationFileReader が読む形)
- 説明は日本語の定義の先頭を --label-length 字までにしたもの．日本語の定義が無ければ空
- 単語はコーパスでの出現の回数(Count)の多い順．--min-count を 1 以上にすると，その回数に満たない単語を除く(よく使う単語に絞る)
- 単語が 2 つ以上残る意味だけを書き，意味はよく使う単語を含むものから順に並べる(同じ単語の意味のうち，よく使うものが先に出る)
- --max-words で 1 つの意味の単語の数を抑える
- 最後に，取り込んだときの索引のおおよその大きさを標準エラーに出す

同梱する data/thesaurus/wordnet-ja.tsv は tools/thesaurus/update.sh がこのスクリプトで作る(入手先・バージョン・SHA-256 は update.sh に書く)．
ライセンス(LICENSES/JapaneseWordNet.txt)は，配るときにデータに添える決まり．
外から来る XML なので，外部の実体を読まない ElementTree の iterparse で少しずつ読む
"""
import argparse
import sys
import xml.etree.ElementTree as ElementTree

parser = argparse.ArgumentParser()
parser.add_argument("source")
parser.add_argument("destination")
parser.add_argument("--min-count", type=int, default=0)
parser.add_argument("--max-words", type=int, default=64)
parser.add_argument("--label-length", type=int, default=24)
parser.add_argument("--version", default="")
options = parser.parse_args()

# synset → [(単語, その意味での回数)]
members: dict[str, list[tuple[str, int]]] = {}
# 単語 → すべての意味での回数の合計
frequency: dict[str, int] = {}
definitions: dict[str, str] = {}

lemma = None
for event, element in ElementTree.iterparse(options.source, events=("start", "end")):
    tag = element.tag
    if event == "start":
        if tag == "LexicalEntry":
            lemma = None
        continue
    if tag == "Lemma":
        lemma = (element.get("writtenForm") or "").strip()
    elif tag == "Sense" and lemma:
        count = sum(int(c.text or 0) for c in element.findall("Count") if (c.text or "").isdigit())
        synset = element.get("synset") or ""
        members.setdefault(synset, []).append((lemma, count))
        frequency[lemma] = frequency.get(lemma, 0) + count
    elif tag == "Synset":
        definition = element.find("Definition")
        if definition is not None and definition.text:
            definitions[element.get("id") or ""] = definition.text.strip()
        element.clear()
    elif tag == "LexicalEntry":
        element.clear()


def clean(text: str) -> str:
    return " ".join(text.replace("\t", " ").split())


groups = []
for synset, words in members.items():
    seen = set()
    ordered = []
    for word, count in sorted(words, key=lambda item: (-frequency[item[0]], -item[1])):
        word = clean(word)
        if word and word not in seen and frequency.get(word, 0) >= options.min_count:
            seen.add(word)
            ordered.append(word)
    ordered = ordered[: options.max_words]
    if len(ordered) < 2:
        continue
    label = clean(definitions.get(synset, ""))
    # 日本語の定義の無い意味には英語の定義が入っていることがあるので，かなと漢字を含まない説明は付けない
    if not any("\u3040" <= character <= "\u9fff" for character in label):
        label = ""
    if len(label) > options.label_length:
        label = label[: options.label_length - 1] + "…"
    groups.append((max(frequency[word] for word in ordered), label, ordered))

groups.sort(key=lambda group: -group[0])
with open(options.destination, "w", encoding="utf-8", newline="\n") as out:
    out.write("# 日本語 WordNet から作った連想の辞書．意味の説明<タブ>単語<タブ>単語…\n")
    out.write(f"# 出典: Japanese WordNet {options.version}(https://bond-lab.github.io/wnja/)．ライセンスは LICENSES/JapaneseWordNet.txt\n")
    for _, label, words in groups:
        out.write(label + "\t" + "\t".join(words) + "\n")

# 取り込んだときの索引(AssociationDictionaryStore)は，単語ごとに「見出し<タブ>説明<タブ>ほかの単語…」の行になる
index_bytes = sum(
    len(("\t".join([word, label] + [other for other in words if other != word]) + "\n").encode("utf-8"))
    for _, label, words in groups
    for word in words
)
headwords = len({word for _, _, words in groups for word in words})
print(f"意味 {len(groups)} 個，見出し {headwords} 語，索引 {index_bytes / 1024 / 1024:.1f} MB", file=sys.stderr)
