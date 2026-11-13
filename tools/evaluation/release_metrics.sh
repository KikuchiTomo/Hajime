#!/bin/sh
# 前のリリース(タグ)と今の作業ツリーの版で，かな漢字変換の指標(R-25)を測って比べ，Markdown に書く．リリースの PR にコメントする(.github/workflows/metrics.yml)．
# 前の版は別の作業ツリーに取り出して作り，その版の辞書とモデルで測る．評価用の文は今回の版のものを両方に使う．
#
# 使い方: tools/evaluation/release_metrics.sh [前の版のタグ(既定: いちばん新しい v*)] [出力の置き場所(既定: build/release-metrics)]
# 環境変数: MODELS_DIR(モデルと辞書の置き場所．既定: リポジトリの 1 つ上の models/)，EVALUATION_DIR(AJIMEE-Bench と Tatoeba．既定: ../evaluation)，
#           HEAD_LABEL(今回の版の名前．既定: git describe)
# 書くもの: base.json・head.json(指標)と report.md(比べた表)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
base=${1:-$(git -C "$root" describe --tags --abbrev=0 --match 'v*')}
output=${2:-"$root/build/release-metrics"}
models=${MODELS_DIR:-"$root/../models"}
evaluation=${EVALUATION_DIR:-"$root/../evaluation"}
head_label=${HEAD_LABEL:-$(git -C "$root" describe --tags --always)}
mkdir -p "$output" "$models"
work=$(mktemp -d)
trap 'git -C "$root" worktree remove --force "$work/base" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

# 版の取得スクリプトから，辞書の版と，モデルのファイル(1 つ目が Zenzai の small，2 つ目が xsmall，3 つ目と 4 つ目が jinen の small と xsmall)を読む．
# jinen の無い古い版では，3 つ目と 4 つ目はファイルでない場所になり，metrics.py が渡さない
dictionary_of() { echo "$models/hajime-dictionary-$(sed -n 's/^version="\(.*\)"/\1/p' "$1/tools/dictionary/fetch_dictionary.sh")/Dictionary"; }
model_of() { echo "$models/$(sed -n 's/^fetch "\([^"]*\)".*/\1/p' "$1/tools/models/fetch_zenzai.sh" | sed -n "$2p")"; }

# 版を作り，その版の辞書とモデルを取得して，指標を測る
measure() {
  tree=$1 label=$2 out=$3
  "$tree/tools/models/fetch_zenzai.sh" "$models" >/dev/null
  "$tree/tools/dictionary/fetch_dictionary.sh" "$models" >/dev/null
  swift build --package-path "$tree/core" -c release --product hajime-playground >/dev/null
  playground="$(swift build --package-path "$tree/core" -c release --show-bin-path)/hajime-playground"
  python3 -I "$root/tools/evaluation/metrics.py" --playground "$playground" --dictionary "$(dictionary_of "$tree")" \
    --small-model "$(model_of "$tree" 1)" --xsmall-model "$(model_of "$tree" 2)"     --jinen-small-model "$(model_of "$tree" 3)" --jinen-xsmall-model "$(model_of "$tree" 4)" \
    --evaluation "$evaluation" --sets "$root/core/Evaluation" --label "$label" --output "$out"
}

git -C "$root" worktree add --detach "$work/base" "$base" >/dev/null
measure "$work/base" "$base" "$output/base.json"
measure "$root" "$head_label" "$output/head.json"
python3 -I "$root/tools/evaluation/compare_metrics.py" "$output/base.json" "$output/head.json" --output "$output/report.md"
echo "書きました: $output/report.md"
