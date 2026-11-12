"""変換エンジンどうしの相補性を測る．複数のエンジンの結果をまとめる仕組みを作る前に，まとめる余地があるかを数で確かめるため．

使い方:
    python3 -I tools/evaluation/complementarity.py <評価用の TSV> <名前>=<候補の JSON Lines> [<名前>=<…> …]
        [--baseline <名前>] [--resamples 2000] [--nfkc]

- 評価用の TSV は hajime-playground --evaluate と同じ形(読み<TAB>期待する変換(| で区切って複数)<TAB>左の文脈)
- 候補の JSON Lines は 1 行 1 問で {"id": 問の番号(0 から), "candidates": [候補, …], "milliseconds": 1 回の時間}．
  hajime-playground --dump-candidates が出す．ほかのエンジンの結果も同じ形で書けば並べて比べられる
- 出すもの
  - エンジンごと: 第 1 候補の正解率(Acc@1)，上位 3・10 に正解がある割合，MRR(上位 10 まで)，時間の中央値と 90%
  - 和の上限: どれかのエンジンの第 1 候補が正解した割合(まとめて第 1 候補を選ぶときの上限)と，どれかの上位 10 に正解がある割合
  - 2 つずつ: 第 1 候補が食い違う割合と，片方だけが正解した問の数
  - --baseline を付けると，基準のエンジンとの差と，和の上限と最良の単独との差に，問を選び直すブートストラップの 95% 信頼区間を付ける
- --nfkc を付けると，候補と期待する変換の両方を NFKC で正規化してから比べる(全角と半角の違いを数えない)
- 評価の文そのものは出さない(数だけを出す)

標準ライブラリだけで動く
"""
import argparse
import itertools
import json
import random
import statistics
import sys
import unicodedata


def load_cases(path):
    cases = []
    with open(path, encoding="utf-8") as file:
        for line in file:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) < 2:
                continue
            cases.append([text for text in columns[1].split("|")])
    return cases


def load_results(path, count):
    results = [None] * count
    with open(path, encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if not line.startswith("{"):
                continue
            record = json.loads(line)
            index = record["id"]
            if 0 <= index < count:
                results[index] = record
    missing = sum(1 for record in results if record is None)
    if missing:
        sys.exit(f"{path}: {missing} 問の結果がありません")
    return results


def rank_of(candidates, expected, window):
    for index, candidate in enumerate(candidates[:window]):
        if candidate in expected:
            return index + 1
    return None


def percentile(values, ratio):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * ratio))]


def bootstrap(samples, statistic, resamples, seed):
    """問を復元抽出で選び直し，statistic の 95% 信頼区間を返す"""
    generator = random.Random(seed)
    count = len(samples)
    values = []
    for _ in range(resamples):
        chosen = [samples[generator.randrange(count)] for _ in range(count)]
        values.append(statistic(chosen))
    values.sort()
    return values[int(resamples * 0.025)], values[min(resamples - 1, int(resamples * 0.975))]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("cases")
    parser.add_argument("engines", nargs="+", help="<名前>=<候補の JSON Lines>")
    parser.add_argument("--baseline")
    parser.add_argument("--resamples", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--nfkc", action="store_true")
    arguments = parser.parse_args()

    normalize = (lambda text: unicodedata.normalize("NFKC", text)) if arguments.nfkc else (lambda text: text)
    expected = [{normalize(text) for text in texts} for texts in load_cases(arguments.cases)]
    count = len(expected)
    names = []
    ranks = {}
    times = {}
    firsts = {}
    for spec in arguments.engines:
        name, _, path = spec.partition("=")
        if not path:
            sys.exit(f"<名前>=<ファイル> の形で渡してください: {spec}")
        records = load_results(path, count)
        names.append(name)
        candidates = [[normalize(text) for text in record["candidates"]] for record in records]
        ranks[name] = [rank_of(candidates[i], expected[i], 10) for i in range(count)]
        firsts[name] = [items[0] if items else None for items in candidates]
        times[name] = [float(record.get("milliseconds", 0)) for record in records]

    def accuracy(name, window, indices=range(count)):
        indices = list(indices)
        return sum(1 for i in indices if ranks[name][i] is not None and ranks[name][i] <= window) / len(indices)

    def reciprocal_rank(name, i):
        rank = ranks[name][i]
        return 1 / rank if rank else 0.0

    print(f"問の数: {count}{'(NFKC で正規化して比べた)' if arguments.nfkc else ''}")
    print()
    print("| エンジン | Acc@1 | Acc@3 | Acc@10 | MRR@10 | 時間の中央値 | 90% |")
    print("|---|---|---|---|---|---|---|")
    for name in names:
        mrr = sum(reciprocal_rank(name, i) for i in range(count)) / count
        print(f"| {name} | {accuracy(name, 1) * 100:.1f} | {accuracy(name, 3) * 100:.1f} | {accuracy(name, 10) * 100:.1f} | "
              f"{mrr * 100:.1f} | {statistics.median(times[name]):.1f}ms | {percentile(times[name], 0.9):.1f}ms |")

    oracle_first = [any(ranks[name][i] == 1 for name in names) for i in range(count)]
    oracle_top10 = [any(ranks[name][i] is not None for name in names) for i in range(count)]
    best = max(names, key=lambda name: accuracy(name, 1))
    print()
    print(f"和の上限(どれかの第 1 候補が正解): {sum(oracle_first) / count * 100:.1f}%  "
          f"最良の単独({best}): {accuracy(best, 1) * 100:.1f}%")
    print(f"どれかの上位 10 に正解: {sum(oracle_top10) / count * 100:.1f}%")

    print()
    print("| 組 | 第 1 候補が食い違う | 左だけ正解 | 右だけ正解 | 組の和の上限 |")
    print("|---|---|---|---|---|")
    for left, right in itertools.combinations(names, 2):
        differ = sum(1 for i in range(count) if firsts[left][i] != firsts[right][i])
        only_left = sum(1 for i in range(count) if ranks[left][i] == 1 and ranks[right][i] != 1)
        only_right = sum(1 for i in range(count) if ranks[right][i] == 1 and ranks[left][i] != 1)
        pair_oracle = sum(1 for i in range(count) if ranks[left][i] == 1 or ranks[right][i] == 1)
        print(f"| {left} / {right} | {differ / count * 100:.1f}% | {only_left} | {only_right} | {pair_oracle / count * 100:.1f}% |")

    if arguments.baseline:
        base = arguments.baseline
        if base not in names:
            sys.exit(f"--baseline の名前が見つかりません: {base}")
        indices = list(range(count))
        print()
        print(f"基準: {base}．差の 95% 信頼区間(問を選び直すブートストラップ {arguments.resamples} 回)")
        print()
        print("| エンジン | Acc@1 の差 | 信頼区間 | Acc@10 の差 | 信頼区間 |")
        print("|---|---|---|---|---|")
        for name in names:
            if name == base:
                continue
            def first_difference(chosen, name=name):
                return sum((ranks[name][i] == 1) - (ranks[base][i] == 1) for i in chosen) / len(chosen) * 100

            def top10_difference(chosen, name=name):
                return sum((ranks[name][i] is not None) - (ranks[base][i] is not None) for i in chosen) / len(chosen) * 100
            low1, high1 = bootstrap(indices, first_difference, arguments.resamples, arguments.seed)
            low10, high10 = bootstrap(indices, top10_difference, arguments.resamples, arguments.seed)
            print(f"| {name} | {first_difference(indices):+.1f} | [{low1:+.1f}, {high1:+.1f}] | "
                  f"{top10_difference(indices):+.1f} | [{low10:+.1f}, {high10:+.1f}] |")

        def oracle_gain(chosen):
            return sum(oracle_first[i] - (ranks[base][i] == 1) for i in chosen) / len(chosen) * 100
        low, high = bootstrap(indices, oracle_gain, arguments.resamples, arguments.seed)
        print()
        print(f"和の上限 − {base}: {oracle_gain(indices):+.1f} ポイント [{low:+.1f}, {high:+.1f}]")


if __name__ == "__main__":
    main()
