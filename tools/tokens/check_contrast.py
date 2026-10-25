"""design/tokens/tokens.json に書いた色の組み合わせが WCAG 2.2 のコントラスト比を満たすか確かめる．

使い方: python3 -I tools/tokens/check_contrast.py [tokens.json のパス]
満たさない組み合わせがあれば一覧を出して終了コード 1 で終わる．
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

DEFAULT_TOKENS = Path(__file__).resolve().parents[2] / "design" / "tokens" / "tokens.json"


def relative_luminance(hex_color: str) -> float:
    value = hex_color.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"6 桁の16進数で書いてください: {hex_color}")
    channels = [int(value[i : i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(fg: str, bg: str) -> float:
    lighter, darker = sorted((relative_luminance(fg), relative_luminance(bg)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_TOKENS
    tokens = json.loads(path.read_text(encoding="utf-8"))
    themes = tokens["theme"]
    failures: list[str] = []
    for rule in tokens["$extensions"]["s90"]["contrast"]:
        colors = themes[rule["theme"]]["color"]
        ratio = contrast_ratio(colors[rule["fg"]]["$value"], colors[rule["bg"]]["$value"])
        line = f'{rule["theme"]}: {rule["fg"]} / {rule["bg"]} = {ratio:.2f} (必要 {rule["min"]})'
        if ratio < rule["min"]:
            failures.append(line)
        else:
            print(f"ok  {line}")
    for line in failures:
        print(f"NG  {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
