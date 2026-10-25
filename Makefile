# 入口はすべてここ．中身はまだ検査だけ(core と apps を作ったら build と test を足す)
PYTHON ?= python3 -I

.PHONY: setup check test tokens build-macos install-macos dev-macos uninstall-dev-macos uninstall-macos try

setup:
	mise install

check:
	$(PYTHON) tools/check/check_skills.py
	$(PYTHON) .claude/skills/s90-architecture/scripts/check_layers.py
	$(PYTHON) tools/tokens/check_contrast.py

test:
	swift test --package-path core
	# 処理時間(R-01)は Release でだけ測る
	swift test --package-path core -c release --filter LatencyProbeTests

build-macos:
	cd apps/macos && xcodegen generate --quiet && xcodebuild -project S90IME.xcodeproj -scheme S90IME -configuration Release -derivedDataPath build build -quiet

# 本番を入れる
install-macos:
	tools/macos/install.sh Release

uninstall-macos:
	tools/macos/uninstall.sh Release

# 開発版(s90.tokyo IME Dev)を入れる．本番と並べて試せる．何度でも入れ直せる
dev-macos:
	tools/macos/install.sh Debug

# 開発版を消す．学習データと設定も消すときは make uninstall-dev-macos PURGE=--purge
uninstall-dev-macos:
	tools/macos/uninstall.sh Debug $(PURGE)

# 入力メソッドとして入れずに，ターミナルで変換を試す
try:
	swift run --package-path core -c release s90-playground

tokens:
	$(PYTHON) tools/tokens/check_contrast.py
	$(PYTHON) tools/tokens/generate_swift.py
