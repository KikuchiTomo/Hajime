# 入口はすべてここ．中身はまだ検査だけ(core と apps を作ったら build と test を足す)
PYTHON ?= python3 -I
# Zenzai のモデルの置き場所．既定は tools/models/fetch_zenzai.sh と同じリポジトリの 1 つ上の models/
MODELS_DIR ?= $(abspath $(CURDIR)/../models)
ZENZAI_MODEL ?= $(MODELS_DIR)/zenz-v3.2-small-Q5_K_M.gguf
# かな漢字変換の辞書(hajime-dictionary)．tools/dictionary/fetch_dictionary.sh が MODELS_DIR に展開する
BUNDLED_DICTIONARY ?= $(MODELS_DIR)/hajime-dictionary-0.3.0/Dictionary
# 評価用のデータ(AJIMEE-Bench)の置き場所．リポジトリに入れられないライセンスなので，1 つ上の evaluation/ に置く
EVALUATION_DIR ?= $(abspath $(CURDIR)/../evaluation)

.PHONY: fetch-models fetch-evaluation evaluate evaluate-operations evaluate-engines setup check test test-debug test-zenzai tokens protocol settings-catalog site site-serve build-macos package-macos install-macos dev-macos uninstall-dev-macos uninstall-macos try english-terms

setup:
	mise install

# Zenzai のモデルとかな漢字変換の辞書を取得してハッシュを確かめる(docs/dev/adr/0006-zenzai.md)
fetch-models:
	tools/models/fetch_zenzai.sh "$(MODELS_DIR)"
	tools/dictionary/fetch_dictionary.sh "$(MODELS_DIR)"

check:
	$(PYTHON) tools/check/check_skills.py
	$(PYTHON) tools/check/check_strings.py
	$(PYTHON) tools/check/check_settings_fields.py
	$(PYTHON) .claude/skills/hajime-architecture/scripts/check_layers.py
	$(PYTHON) tools/tokens/check_contrast.py
	$(PYTHON) tools/protocol/generate.py --check
	$(PYTHON) tools/tokens/generate_rust.py --check
	$(PYTHON) tools/release/changelog.py check

# モデルがあれば本物の Zenzai のテストも動かす．無ければ飛ばしたことを最後に出す
test: test-debug
	@if [ -f "$(ZENZAI_MODEL)" ]; then \
		$(MAKE) --no-print-directory test-zenzai; \
	else \
		swift test --package-path core -c release --filter LatencyProbeTests && \
		printf '\n注意: Zenzai のモデルが無いので，本物の Zenzai のテストを飛ばし，処理時間は Zenzai なしで測りました\n  モデルの場所: %s\n  make fetch-models で取得してから make test を動かし直してください\n\n' "$(ZENZAI_MODEL)" >&2; \
	fi

# Debug ビルドのテスト．本物の Zenzai のテストはデバッグビルドでは遅すぎるので，ここでは飛ばして test-zenzai で動かす
test-debug:
	env -u HAJIME_ZENZAI_MODEL swift test --package-path core

# 本物の Zenzai のテストと処理時間(R-01)を Release で動かす．モデルが無ければ失敗する(CI はこちらを使う)
test-zenzai:
	@test -f "$(ZENZAI_MODEL)" || { echo "Zenzai のモデルがありません: $(ZENZAI_MODEL)．make fetch-models で取得してください" >&2; exit 1; }
	@dictionary=; if [ -d "$(BUNDLED_DICTIONARY)" ]; then dictionary="HAJIME_BUNDLED_DICTIONARY=$(abspath $(BUNDLED_DICTIONARY))"; fi; \
	env HAJIME_ZENZAI_MODEL="$(abspath $(ZENZAI_MODEL))" $$dictionary swift test --package-path core -c release --filter HajimeEngineTests

# 公式サイト(apps/docs-site)．出力先は make site SITE_OUT=<ディレクトリ> で変えられる
SITE_OUT ?= $(CURDIR)/apps/docs-site/public

site:
	cd apps/docs-site && hugo --gc --minify --destination "$(abspath $(SITE_OUT))"

site-serve:
	cd apps/docs-site && hugo server

# ビルドしたアプリは LaunchServices の登録から外す．入れた Hajime IME が入力ソースから外れないようにする(tools/macos/unregister_builds.sh)
build-macos:
	cd apps/macos && xcodegen generate --quiet && xcodebuild -project Hajime.xcodeproj -scheme Hajime -configuration Release -destination "generic/platform=macOS" -derivedDataPath build build -quiet
	tools/macos/unregister_builds.sh

# 配布物(.pkg)を作る．署名と公証は使える証明書と設定があるときだけ(tools/macos/package.sh)
package-macos:
	tools/macos/package.sh

# 本番を入れる．入力メニューの名前を変えるときは make install-macos NAME="好きな名前"
install-macos:
	HAJIME_NAME="$(NAME)" tools/macos/install.sh Release

uninstall-macos:
	tools/macos/uninstall.sh Release

# 開発版(Hajime Dev)を入れる．本番と並べて試せる．何度でも入れ直せる
dev-macos:
	HAJIME_NAME="$(NAME)" tools/macos/install.sh Dev

# 開発版を消す．学習データと設定も消すときは make uninstall-dev-macos PURGE=--purge
uninstall-dev-macos:
	tools/macos/uninstall.sh Dev $(PURGE)

# 入力メソッドとして入れずに，ターミナルで変換を試す
try:
	swift run --package-path core -c release hajime-playground

# 英語の語の辞書(R-24)の語ごとに，小文字で打ったときの読みと候補の先頭を出す．語を足したら，日本語の語を打った人に英語の語が先に出ないか見る
english-terms:
	@swift run --package-path core -c release hajime-playground --english-terms data/english/english-terms.txt 2>/dev/null

# AJIMEE-Bench を取得してハッシュを確かめ，評価用の TSV にする
fetch-evaluation:
	tools/evaluation/fetch_ajimee.sh "$(EVALUATION_DIR)"

# かな漢字変換の正解率・上位の候補に正解が入った割合・MinCER を，文(conversion-basic と AJIMEE-Bench)と語彙(vocabulary-*)で測る．Zenzai のモデルがあれば使う．DICTIONARY=<ディレクトリ> で辞書を差し替えられる．llama.cpp のログで結果が埋もれるので，実行時の標準エラーは捨てる
evaluate:
	@test -f "$(EVALUATION_DIR)/ajimee.tsv" || { echo "評価用のデータがありません: $(EVALUATION_DIR)/ajimee.tsv．make fetch-evaluation で取得してください" >&2; exit 1; }
	swift build --package-path core -c release --product hajime-playground
	@options=; if [ -f "$(ZENZAI_MODEL)" ]; then options="--zenzai $(abspath $(ZENZAI_MODEL))"; fi; \
	if [ -n "$(DICTIONARY)" ]; then options="$$options --dictionary $(abspath $(DICTIONARY))"; fi; \
	bin=$$(swift build --package-path core -c release --show-bin-path); \
	for file in core/Evaluation/conversion-basic.tsv "$(EVALUATION_DIR)/ajimee.tsv" core/Evaluation/vocabulary-*.tsv; do \
		echo "== $$file"; \
		"$$bin/hajime-playground" --evaluate "$$file" $$options 2>/dev/null | tail -1; \
	done

# 期待する文に着くまでの操作(↓ ← → ⇧← ⇧→)の数と，着いた割合を，文(conversion-basic と AJIMEE-Bench)で測る(R-25)．
# 候補の出し方ごとに，同梱の辞書と Zenzai のモデルで測る．PRESENTATION=automatic,segmentList,list で出し方を選べる．
# ZENZAI_MODEL に xsmall のモデルを渡すときは ZENZAI_VARIANT=xsmall も付ける
PRESENTATION ?= automatic,segmentList,list
ZENZAI_VARIANT ?= small
evaluate-operations:
	@test -f "$(EVALUATION_DIR)/ajimee.tsv" || { echo "評価用のデータがありません: $(EVALUATION_DIR)/ajimee.tsv．make fetch-evaluation で取得してください" >&2; exit 1; }
	swift build --package-path core -c release --product hajime-playground
	@options="--presentation $(PRESENTATION)"; if [ -f "$(ZENZAI_MODEL)" ]; then options="$$options --zenzai $(abspath $(ZENZAI_MODEL)) --zenzai-variant $(ZENZAI_VARIANT)"; fi; \
	dictionary=$${DICTIONARY:-$(BUNDLED_DICTIONARY)}; if [ -d "$$dictionary" ]; then options="$$options --dictionary $$(cd "$$dictionary" && pwd)"; fi; \
	bin=$$(swift build --package-path core -c release --show-bin-path); \
	for file in core/Evaluation/conversion-basic.tsv "$(EVALUATION_DIR)/ajimee.tsv"; do \
		echo "== $$file"; \
		"$$bin/hajime-playground" --evaluate-operations "$$file" $$options 2>/dev/null | grep -E '^(==|第 1 候補)'; \
	done

# 変換エンジンどうしの相補性(単独の正解率・どれかが正解した割合・食い違う割合)と，検証木で候補を並べ替えた効果を，
# AJIMEE-Bench と語彙で測る(docs/dev/adr/0016-reading-aligned-fusion.md)．Hajime IME の 3 つの構成(ラティスだけ・Zenzai small・xsmall)の候補を
# $(EVALUATION_DIR)/engines/ に書き出す．ほかのエンジンの結果を同じ形(<セット>.<名前>.jsonl)でそこに置くと，相補性の表に加わる
ZENZAI_FAST_MODEL ?= $(MODELS_DIR)/zenz-v3.2-xsmall-Q5_K_M.gguf
evaluate-engines:
	@test -f "$(EVALUATION_DIR)/ajimee.tsv" || { echo "評価用のデータがありません: $(EVALUATION_DIR)/ajimee.tsv．make fetch-evaluation で取得してください" >&2; exit 1; }
	@test -f "$(ZENZAI_MODEL)" || { echo "Zenzai のモデルがありません: $(ZENZAI_MODEL)．make fetch-models で取得してください" >&2; exit 1; }
	swift build --package-path core -c release --product hajime-playground
	@out="$(EVALUATION_DIR)/engines"; mkdir -p "$$out"; \
	dictionary=$${DICTIONARY:-$(BUNDLED_DICTIONARY)}; options=; if [ -d "$$dictionary" ]; then options="--dictionary $$(cd "$$dictionary" && pwd)"; fi; \
	bin=$$(swift build --package-path core -c release --show-bin-path); \
	for set in ajimee:$(EVALUATION_DIR)/ajimee.tsv vocab-person:core/Evaluation/vocabulary-person.tsv vocab-place:core/Evaluation/vocabulary-place.tsv vocab-other:core/Evaluation/vocabulary-other.tsv; do \
		name=$${set%%:*}; file=$${set#*:}; \
		"$$bin/hajime-playground" --dump-candidates "$$file" $$options 2>/dev/null | grep '^{' >| "$$out/$$name.lattice.jsonl"; \
		"$$bin/hajime-playground" --dump-candidates "$$file" --score $$options --zenzai "$(abspath $(ZENZAI_MODEL))" 2>/dev/null | grep '^{' >| "$$out/$$name.small.jsonl"; \
		if [ -f "$(ZENZAI_FAST_MODEL)" ]; then "$$bin/hajime-playground" --dump-candidates "$$file" $$options --zenzai "$(abspath $(ZENZAI_FAST_MODEL))" --zenzai-variant xsmall 2>/dev/null | grep '^{' >| "$$out/$$name.xsmall.jsonl"; fi; \
		echo "== $$name: 検証木で並べ替えた効果"; \
		$(PYTHON) tools/evaluation/reranking.py "$$file" "$$out/$$name.small.jsonl"; \
		echo "== $$name: エンジンどうしの相補性"; \
		engines=$$(for result in "$$out/$$name".*.jsonl; do engine=$${result##*/$$name.}; echo "$${engine%.jsonl}=$$result"; done); \
		$(PYTHON) tools/evaluation/complementarity.py "$$file" $$engines --baseline small --nfkc; \
	done

tokens:
	$(PYTHON) tools/tokens/check_contrast.py
	$(PYTHON) tools/tokens/generate_swift.py
	$(PYTHON) tools/tokens/generate_rust.py

protocol:
	$(PYTHON) tools/protocol/generate.py

# Windows の設定の画面が読む，設定の項目の名前と範囲の写し(protocol/settings-catalog.json)を作り直す
settings-catalog:
	HAJIME_WRITE_SETTINGS_CATALOG=1 swift test --package-path core --filter SettingsCatalogTests
