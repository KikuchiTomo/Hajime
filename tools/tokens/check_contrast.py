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


def blend(color: str, opacity: float, under: str) -> str:
    """color を opacity の濃さで under の上に重ねた色(パレットの説明のカードのように，文字の色を薄く敷いた地)．"""
    top = [int(color.lstrip("#")[i : i + 2], 16) for i in (0, 2, 4)]
    bottom = [int(under.lstrip("#")[i : i + 2], 16) for i in (0, 2, 4)]
    mixed = [round(t * opacity + b * (1 - opacity)) for t, b in zip(top, bottom)]
    return "#" + "".join(f"{c:02X}" for c in mixed)


def lookup(tokens: dict, path: str) -> float:
    node = tokens
    for key in path.split("."):
        node = node[key]
    return float(node["$value"])


def contrast_ratio(fg: str, bg: str) -> float:
    lighter, darker = sorted((relative_luminance(fg), relative_luminance(bg)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def main(argv: list[str]) -> int:
    path = Path(argv[1]) if len(argv) > 1 else DEFAULT_TOKENS
    tokens = json.loads(path.read_text(encoding="utf-8"))
    # Windows の glass の色(glass.light・glass-dark)も同じ基準で検査する
    themes = {**tokens["theme"], **{f"glass-{name}": body for name, body in tokens.get("glass", {}).items() if "color" in body}}
    # Windows の設定の画面の色は「settings-windows.light」のように名前を付けて同じ形で確かめる
    # Windows の手書きの窓だけの色(handwriting-windows.light など)も同じ形で確かめる
    for group in ("settings-windows", "handwriting-windows"):
        for mode, body in tokens.get(group, {}).items():
            if not mode.startswith("$"):
                themes[f"{group}.{mode}"] = body
    failures: list[str] = []
    for rule in tokens["$extensions"]["hajime"]["contrast"]:
        colors = themes[rule["theme"]]["color"]
        bg = colors[rule["bg"]]["$value"]
        name = rule["bg"]
        # tint があれば，その色をその濃さで bg の上に重ねた地と比べる(例: 文字の色を薄く敷いたタグ)
        if tint := rule.get("tint"):
            opacity = lookup(tokens, tint["opacity"])
            bg = blend(colors[tint["color"]]["$value"], opacity, bg)
            name = f'{tint["color"]}({tint["opacity"]}) over {rule["bg"]}'
        ratio = contrast_ratio(colors[rule["fg"]]["$value"], bg)
        line = f'{rule["theme"]}: {rule["fg"]} / {name} = {ratio:.2f} (必要 {rule["min"]})'
        if ratio < rule["min"]:
            failures.append(line)
        else:
            print(f"ok  {line}")
    for line in failures:
        print(f"NG  {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
