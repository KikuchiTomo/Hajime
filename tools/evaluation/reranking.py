"""検証木の採点で候補を並べ替えたときの効果を，書き出した候補と点数から見積もる(ADR 0016 の提案 1)．

使い方:
    python3 -I tools/evaluation/reranking.py <評価用の TSV> <hajime-playground --dump-candidates --score の出力> [--resamples 2000]

並べ方ごとに Acc@1・Acc@3・Acc@5・Acc@10・MRR@10 を出す．
- そのまま: Zenzai の候補の順(今の Hajime IME)
- Zenzai の候補だけを並べ替え: 第 1 候補はそのまま，2 位以下を点数の順に
- 合わせて並べ替え: Zenzai の候補と Zenzai を使わない変換の候補を合わせ，第 1 候補はそのまま，2 位以下を点数の順に
- 全部を点数の順(参考): 第 1 候補も点数で選ぶ
採点できなかった候補(nil)は，点数の付いた候補のあとに元の順で置く．
「合わせて並べ替え」と「そのまま」の差には，問を選び直すブートストラップの 95% 信頼区間を付ける．評価の文そのものは出さない

標準ライブラリだけで動く
"""
import argparse
import json
import random
import sys


def load_expected(path):
    expected = []
    with open(path, encoding="utf-8") as file:
        for line in file:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) >= 2:
                expected.append(set(columns[1].split("|")))
    return expected


def by_score(texts, scores):
    scored = [(text, score) for text, score in zip(texts, scores) if score is not None]
    unscored = [text for text, score in zip(texts, scores) if score is None]
    return [text for text, _ in sorted(scored, key=lambda pair: -pair[1])] + unscored


def keep_first(texts, scores):
    if not texts:
        return []
    return [texts[0]] + by_score(texts[1:], scores[1:])


def rank(candidates, expected, window=10):
    for index, text in enumerate(candidates[:window]):
        if text in expected:
            return index + 1
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases")
    parser.add_argument("dump")
    parser.add_argument("--resamples", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=0)
    arguments = parser.parse_args()

    expected = load_expected(arguments.cases)
    records = {}
    with open(arguments.dump, encoding="utf-8") as file:
        for line in file:
            if line.startswith("{"):
                record = json.loads(line)
                records[record["id"]] = record
    if len(records) != len(expected) or any("scores" not in record for record in records.values()):
        sys.exit("候補の数が評価用の文と合わないか，点数がありません(--score を付けて書き出してください)")
    count = len(expected)

    orders = {"そのまま": [], "Zenzai の候補だけを並べ替え": [], "合わせて並べ替え": [], "全部を点数の順(参考)": []}
    times = []
    pool_sizes = []
    unscored = 0
    for index in range(count):
        record = records[index]
        pool, scores = record["pool"], record["scores"]
        score_of = dict(zip(pool, scores))
        zenzai = record["candidates"]
        orders["そのまま"].append(zenzai)
        orders["Zenzai の候補だけを並べ替え"].append(keep_first(zenzai, [score_of.get(text) for text in zenzai]))
        orders["合わせて並べ替え"].append(keep_first(pool, scores))
        orders["全部を点数の順(参考)"].append(by_score(pool, scores))
        times.append(record["scoreMilliseconds"])
        pool_sizes.append(len(pool))
        unscored += sum(1 for score in scores if score is None)

    ranks = {name: [rank(lists[i], expected[i]) for i in range(count)] for name, lists in orders.items()}

    def accuracy(name, window, indices):
        return sum(1 for i in indices if ranks[name][i] is not None and ranks[name][i] <= window) / len(indices) * 100

    def mrr(name, indices):
        return sum(1 / ranks[name][i] for i in indices if ranks[name][i]) / len(indices) * 100

    everything = list(range(count))
    print(f"問の数: {count}  採点した候補の数 中央値: {sorted(pool_sizes)[count // 2]}  採点できなかった候補: {unscored}")
    ordered_times = sorted(times)
    print(f"採点の時間 中央値: {ordered_times[count // 2]:.1f}ms  90%: {ordered_times[count * 9 // 10]:.1f}ms  最大: {ordered_times[-1]:.1f}ms")
    print()
    print("| 並べ方 | Acc@1 | Acc@3 | Acc@5 | Acc@10 | MRR@10 |")
    print("|---|---|---|---|---|---|")
    for name in orders:
        print(f"| {name} | {accuracy(name, 1, everything):.1f} | {accuracy(name, 3, everything):.1f} | {accuracy(name, 5, everything):.1f} | "
              f"{accuracy(name, 10, everything):.1f} | {mrr(name, everything):.1f} |")

    base, proposed = "そのまま", "合わせて並べ替え"
    generator = random.Random(arguments.seed)
    differences = {"Acc@3": [], "MRR@10": []}
    for _ in range(arguments.resamples):
        chosen = [generator.randrange(count) for _ in range(count)]
        differences["Acc@3"].append(accuracy(proposed, 3, chosen) - accuracy(base, 3, chosen))
        differences["MRR@10"].append(mrr(proposed, chosen) - mrr(base, chosen))
    print()
    for metric, values in differences.items():
        values.sort()
        point = (accuracy(proposed, 3, everything) - accuracy(base, 3, everything)) if metric == "Acc@3" else (mrr(proposed, everything) - mrr(base, everything))
        low, high = values[int(arguments.resamples * 0.025)], values[min(arguments.resamples - 1, int(arguments.resamples * 0.975))]
        print(f"{proposed} − {base} の {metric}: {point:+.1f} [{low:+.1f}, {high:+.1f}]")
    lost = sum(1 for i in everything if ranks[base][i] == 1 and ranks["全部を点数の順(参考)"][i] != 1)
    gained = sum(1 for i in everything if ranks[base][i] != 1 and ranks["全部を点数の順(参考)"][i] == 1)
    print(f"第 1 候補も点数で選んだ場合(参考): 正解を失う問 {lost}，正解になる問 {gained}")


if __name__ == "__main__":
    main()
