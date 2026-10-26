# 入口はすべてここ．中身はまだ検査だけ(core と apps を作ったら build と test を足す)
PYTHON ?= python3 -I
# Zenzai のモデルの置き場所．既定は tools/models/fetch_zenzai.sh と同じリポジトリの 1 つ上の models/
MODELS_DIR ?= $(abspath $(CURDIR)/../models)
ZENZAI_MODEL ?= $(MODELS_DIR)/zenz-v3.2-small-Q5_K_M.gguf

.PHONY: fetch-models setup check test test-debug test-zenzai tokens protocol settings-catalog build-macos package-macos install-macos dev-macos uninstall-dev-macos uninstall-macos try

setup:
	mise install

# Zenzai のモデルを取得してハッシュを確かめる(docs/dev/adr/0006-zenzai.md)
fetch-models:
	tools/models/fetch_zenzai.sh "$(MODELS_DIR)"

check:
	$(PYTHON) tools/check/check_skills.py
	$(PYTHON) tools/check/check_strings.py
	$(PYTHON) .claude/skills/s90-architecture/scripts/check_layers.py
	$(PYTHON) tools/tokens/check_contrast.py
	$(PYTHON) tools/protocol/generate.py --check
	$(PYTHON) tools/tokens/generate_rust.py --check

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
	env -u S90_ZENZAI_MODEL swift test --package-path core

# 本物の Zenzai のテストと処理時間(R-01)を Release で動かす．モデルが無ければ失敗する(CI はこちらを使う)
test-zenzai:
	@test -f "$(ZENZAI_MODEL)" || { echo "Zenzai のモデルがありません: $(ZENZAI_MODEL)．make fetch-models で取得してください" >&2; exit 1; }
	S90_ZENZAI_MODEL="$(abspath $(ZENZAI_MODEL))" swift test --package-path core -c release --filter S90EngineTests

build-macos:
	cd apps/macos && xcodegen generate --quiet && xcodebuild -project S90IME.xcodeproj -scheme S90IME -configuration Release -destination "generic/platform=macOS" -derivedDataPath build build -quiet

# 配布物(.pkg)を作る．署名と公証は使える証明書と設定があるときだけ(tools/macos/package.sh)
package-macos:
	tools/macos/package.sh

# 本番を入れる．入力メニューの名前を変えるときは make install-macos NAME="好きな名前"
install-macos:
	S90_NAME="$(NAME)" tools/macos/install.sh Release

uninstall-macos:
	tools/macos/uninstall.sh Release

# 開発版(s90 Dev)を入れる．本番と並べて試せる．何度でも入れ直せる
dev-macos:
	S90_NAME="$(NAME)" tools/macos/install.sh Dev

# 開発版を消す．学習データと設定も消すときは make uninstall-dev-macos PURGE=--purge
uninstall-dev-macos:
	tools/macos/uninstall.sh Dev $(PURGE)

# 入力メソッドとして入れずに，ターミナルで変換を試す
try:
	swift run --package-path core -c release s90-playground

tokens:
	$(PYTHON) tools/tokens/check_contrast.py
	$(PYTHON) tools/tokens/generate_swift.py
	$(PYTHON) tools/tokens/generate_rust.py

protocol:
	$(PYTHON) tools/protocol/generate.py

# Windows の設定の画面が読む，設定の項目の名前と範囲の写し(protocol/settings-catalog.json)を作り直す
settings-catalog:
	S90_WRITE_SETTINGS_CATALOG=1 swift test --package-path core --filter SettingsCatalogTests
