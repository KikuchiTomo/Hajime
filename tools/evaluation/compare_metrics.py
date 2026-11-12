"""tools/evaluation/metrics.py が書いた 2 つの版の指標を比べ，PR のコメントにする Markdown を書く．

使い方:
    python3 -I tools/evaluation/compare_metrics.py <前の版.json> <今回の版.json> [--output <出力.md>]

正解率・上位 10 候補が下がったもの，MinCER が上がったものを「下がった」と書き，最初に数をまとめる．
時間は CI のマシンの負荷で揺れるので，目安として並べるだけにする
"""
import argparse
import json
import pathlib

# PR のコメントを探して書き換えるための印
MARKER = "<!-- hajime-release-metrics -->"
SET_NAMES = {
    "conversion-basic": "報告された例(conversion-basic)",
    "conversion-everyday": "ふだんの文(conversion-everyday)",
    "conversion-terms": "専門用語の文(conversion-terms)",
    "ajimee": "AJIMEE-Bench",
    "tatoeba": "Tatoeba",
    "vocabulary-person": "人名(語彙)",
    "vocabulary-place": "地名(語彙)",
    "vocabulary-other": "その他(語彙)",
}
# 割合の差をこれより小さいときは「変わらない」とみなす
EPSILON = 1e-9


def signed(value, unit="", digits=1):
    if abs(value) < EPSILON:
        return "±0"
    return f"{value:+.{digits}f}{unit}"


def compare(base, head):
    rows = []
    regressions = []
    improvements = 0
    for key, name in SET_NAMES.items():
        for model in ["small", "xsmall"]:
            before = base.get("sets", {}).get(key, {}).get(model)
            after = head.get("sets", {}).get(key, {}).get(model)
            if not after or "accuracy" not in after:
                continue
            if not before or "accuracy" not in before:
                rows.append(f"| {name} | {model} | — | {after['passed']}/{after['total']}({after['accuracy']:.1f}%) | — "
                            f"| {after['top10']:.1f}% | {after['mincer']:.2f}% | 今回から |")
                continue
            accuracy = after["accuracy"] - before["accuracy"]
            top10 = after["top10"] - before["top10"]
            mincer = after["mincer"] - before["mincer"]
            worse = accuracy < -EPSILON or top10 < -EPSILON or mincer > EPSILON
            better = accuracy > EPSILON or top10 > EPSILON or mincer < -EPSILON
            if worse:
                regressions.append(f"{name}({model})")
            elif better:
                improvements += 1
            mark = "下がった" if worse else "上がった" if better else ""
            if not after.get("zenzai", True) or not before.get("zenzai", True):
                mark += "(Zenzai を読み込めなかった版がある)"
            rows.append(
                f"| {name} | {model} | {before['passed']}/{before['total']}({before['accuracy']:.1f}%) "
                f"| {after['passed']}/{after['total']}({after['accuracy']:.1f}%) | {signed(accuracy, '%')} "
                f"| {before['top10']:.1f}% → {after['top10']:.1f}%({signed(top10, '%')}) "
                f"| {before['mincer']:.2f}% → {after['mincer']:.2f}%({signed(mincer, '%', 2)}) | {mark} |"
            )
    return rows, regressions, improvements


def startup_rows(base, head):
    labels = [("verification_seconds", "辞書とモデルの確認"), ("warm_up_seconds", "辞書の読み込み(warmUp)"), ("first_conversion_seconds", "最初の変換")]
    before, after = base.get("startup"), head.get("startup")
    if not after:
        return []
    rows = []
    for key, name in labels:
        old = f"{before[key]:.2f} 秒" if before else "—"
        rows.append(f"| {name} | {old} | {after[key]:.2f} 秒 |")
    return rows


def times(base, head):
    """文の評価で 1 回の変換にかかった時間の中央値(small，AJIMEE-Bench)"""
    before = base.get("sets", {}).get("ajimee", {}).get("small", {}).get("median_seconds")
    after = head.get("sets", {}).get("ajimee", {}).get("small", {}).get("median_seconds")
    if after is None:
        return None
    old = f"{before * 1000:.0f}ms" if before is not None else "—"
    return f"1 回の変換の時間の中央値(AJIMEE-Bench，small): {old} → {after * 1000:.0f}ms(CI のマシンの負荷で揺れるので目安)"


def report(base, head):
    rows, regressions, improvements = compare(base, head)
    lines = [MARKER, f"## かな漢字変換の指標({base.get('label') or '前の版'} → {head.get('label') or '今回'})", ""]
    if regressions:
        lines.append(f"**下がった指標: {len(regressions)} 件**({'，'.join(regressions)})．上がった指標: {improvements} 件")
    else:
        lines.append(f"下がった指標はありません．上がった指標: {improvements} 件")
    lines += [
        "",
        "第 1 候補の正解の数(割合)・上位 10 候補に正解が入った割合・MinCER(第 1 候補と期待する文との文字誤り率)．"
        "評価用の文は今回の版のものを両方に使い，同じ CI の中で両方の版を測った(R-25)．",
        "",
        "| 評価用の文 | モデル | 前の版 | 今回 | 差 | 上位 10 候補 | MinCER | |",
        "|---|---|---|---|---|---|---|---|",
        *rows,
    ]
    startup = startup_rows(base, head)
    if startup:
        lines += ["", "| 起動 | 前の版 | 今回 |", "|---|---|---|", *startup]
    timing = times(base, head)
    if timing:
        lines += ["", timing]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base")
    parser.add_argument("head")
    parser.add_argument("--output")
    arguments = parser.parse_args()
    base = json.loads(pathlib.Path(arguments.base).read_text(encoding="utf-8"))
    head = json.loads(pathlib.Path(arguments.head).read_text(encoding="utf-8"))
    text = report(base, head)
    if arguments.output:
        pathlib.Path(arguments.output).write_text(text, encoding="utf-8")
    else:
        print(text, end="")


if __name__ == "__main__":
    main()
