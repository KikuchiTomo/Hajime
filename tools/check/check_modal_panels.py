#!/usr/bin/env python3
"""入力ソースのアプリ(apps/macos/Hajime)で，窓を runModal で出していないかを確かめる．

設定の画面は入力ソースの Hajime IME と同じプロセスで動く．runModal で開く・保存の窓や警告を出すとメインスレッドが止まり，
窓の欄に打った文字(入力ソースの Hajime IME が受け取る)を処理できずに互いに待って止まる(ぐるぐるが出る)．
開発版は入力ソースに登録しないので，この止まり方は開発版やテストでは起きない．窓は FilePanel(シート)で出す．
更新用のアプリ(apps/macos/HajimeUpdater)は別のプロセスなので確かめない．
使い方: python3 -I tools/check/check_modal_panels.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/macos/Hajime"


def check() -> list[str]:
    problems: list[str] = []
    for path in sorted(APP.rglob("*.swift")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            code = line.split("//", 1)[0]
            if re.search(r"\.runModal\(", code):
                problems.append(f"{path.relative_to(ROOT)}:{number}: runModal で窓を出すと，入力ソースの Hajime IME が止まります(FilePanel で出す)")
    return problems


def main() -> int:
    problems = check()
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
