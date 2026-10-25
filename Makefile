# 入口はすべてここ．中身はまだ検査だけ(core と apps を作ったら build と test を足す)
PYTHON ?= python3 -I

.PHONY: setup check test tokens build-macos install-macos

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

install-macos:
	tools/macos/install.sh Release

tokens:
	$(PYTHON) tools/tokens/check_contrast.py
	$(PYTHON) tools/tokens/generate_swift.py
