"""ある版の hajime-playground と辞書で，かな漢字変換の指標(R-25)を測り，JSON に書く．

使い方:
    python3 -I tools/evaluation/metrics.py --playground <hajime-playground> --dictionary <Dictionary>
        --small-model <small の gguf> --xsmall-model <xsmall の gguf>
        --evaluation <評価用の文の置き場所> --sets <リポジトリの core/Evaluation> --output <出力.json> [--label <版の名前>]

- 文: conversion-basic・conversion-everyday(リポジトリの core/Evaluation)，AJIMEE-Bench・Tatoeba(make fetch-evaluation で取得)．
  語彙: vocabulary-person・place・other．それぞれを Zenzai small と xsmall で変換する(hajime-playground --evaluate)
- 測るもの: 第 1 候補の正解の数と割合，上位 10 候補の正解率，MinCER，1 回の変換の時間の中央値
- 起動の時間(hajime-playground --startup)も測る．古い版には無いので，無ければ空にする
- 前の版と比べるときは，評価用の文は新しい版のもの(--sets)を両方に使う(同じ問題で比べるため)

評価用の文が無いもの(AJIMEE-Bench・Tatoeba を取得していない)は飛ばす．Zenzai を読み込めなかった変換は数えない(結果に zenzai: false と書く)
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys

SETS = [
    ("conversion-basic", "sets", "conversion-basic.tsv"),
    ("conversion-everyday", "sets", "conversion-everyday.tsv"),
    ("ajimee", "evaluation", "ajimee.tsv"),
    ("tatoeba", "evaluation", "tatoeba.tsv"),
    ("vocabulary-person", "sets", "vocabulary-person.tsv"),
    ("vocabulary-place", "sets", "vocabulary-place.tsv"),
    ("vocabulary-other", "sets", "vocabulary-other.tsv"),
]
MODELS = ["small", "xsmall"]
SUMMARY = re.compile(r"正解: (\d+) / (\d+) \(([\d.]+)%\)\s+上位 \d+ 候補: ([\d.]+)%\s+MinCER: ([\d.]+)%\s+変換の時間 中央値: ([\d.e-]+) seconds")
STARTUP = re.compile(r"確認 ([\d.e-]+) seconds\s+エンジン ([\d.e-]+) seconds\s+warmUp ([\d.e-]+) seconds\s+最初の変換 ([\d.e-]+) seconds")


def zenzai_arguments(models, name):
    return ["--zenzai", models[name]] + (["--zenzai-variant", "xsmall"] if name == "xsmall" else [])


def evaluate(playground, dictionary, models, path, model):
    result = subprocess.run([playground, "--evaluate", str(path), *zenzai_arguments(models, model), "--dictionary", dictionary],
                            capture_output=True, text=True)
    lines = result.stdout.splitlines()
    match = next((SUMMARY.search(line) for line in reversed(lines) if SUMMARY.search(line)), None)
    if match is None:
        return {"error": (result.stderr or result.stdout)[-500:]}
    passed, total, accuracy, top10, mincer, median = match.groups()
    return {
        "zenzai": any(line.startswith("Zenzai: あり") for line in lines),
        "passed": int(passed), "total": int(total), "accuracy": float(accuracy), "top10": float(top10),
        "mincer": float(mincer), "median_seconds": float(median),
    }


def startup(playground, dictionary, models):
    result = subprocess.run([playground, "--startup", dictionary, "--zenzai", models["small"], "--zenzai-fast", models["xsmall"]],
                            capture_output=True, text=True)
    match = next((STARTUP.search(line) for line in result.stdout.splitlines() if STARTUP.search(line)), None)
    if match is None:
        return None
    verification, engine, warm_up, first = (float(value) for value in match.groups())
    return {"verification_seconds": verification, "engine_seconds": engine, "warm_up_seconds": warm_up, "first_conversion_seconds": first}


def main():
    parser = argparse.ArgumentParser()
    for name in ["playground", "dictionary", "small-model", "xsmall-model", "evaluation", "sets", "output"]:
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--label", default="")
    arguments = parser.parse_args()
    models = {"small": arguments.small_model, "xsmall": arguments.xsmall_model}
    places = {"sets": pathlib.Path(arguments.sets), "evaluation": pathlib.Path(arguments.evaluation)}
    metrics = {"label": arguments.label, "dictionary": arguments.dictionary, "sets": {}, "startup": None}
    for name, place, file in SETS:
        path = places[place] / file
        if not path.exists():
            print(f"評価用の文がありません(飛ばします): {path}", file=sys.stderr)
            continue
        metrics["sets"][name] = {model: evaluate(arguments.playground, arguments.dictionary, models, path, model) for model in MODELS}
        print(f"{name}: " + "，".join(f"{model} {value.get('accuracy')}%" for model, value in metrics["sets"][name].items()), file=sys.stderr)
    metrics["startup"] = startup(arguments.playground, arguments.dictionary, models)
    pathlib.Path(arguments.output).write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
