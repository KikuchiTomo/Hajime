# 入口はすべてここ．中身はまだ検査だけ(core と apps を作ったら build と test を足す)
PYTHON ?= python3 -I

.PHONY: setup check test tokens

setup:
	mise install

check:
	$(PYTHON) tools/check/check_skills.py
	$(PYTHON) .claude/skills/s90-architecture/scripts/check_layers.py
	$(PYTHON) tools/tokens/check_contrast.py

test:
	@if [ -f core/Package.swift ]; then swift test --package-path core; else echo "core はまだありません"; fi

tokens:
	$(PYTHON) tools/tokens/check_contrast.py
