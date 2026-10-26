from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKENS = ROOT / "design" / "tokens" / "tokens.json"
OUTPUT = ROOT / "apps" / "windows" / "crates" / "tokens" / "src" / "generated.rs"


def snake(name: str) -> str:
    return re.sub(r"[-]", "_", name).lower()


def upper(name: str) -> str:
    return snake(name).upper()


def number(token: dict) -> float:
    value = token["$value"]
    if isinstance(value, dict):
        value = value["value"]
    return float(value)


def rgb(hex_color: str) -> str:
    value = hex_color.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) for i in (0, 2, 4))
    return f"Rgb {{ red: 0x{r:02X}, green: 0x{g:02X}, blue: 0x{b:02X} }}"


def render(tokens: dict) -> str:
    color_names = sorted(next(iter(tokens["theme"].values()))["color"].keys())
    lines = [
        "#[derive(Debug, Clone, Copy, PartialEq, Eq)]",
        "pub struct Rgb {",
        "    pub red: u8,",
        "    pub green: u8,",
        "    pub blue: u8,",
        "}",
        "",
        "#[derive(Debug, Clone, Copy, PartialEq, Eq)]",
        "pub struct Palette {",
    ]
    lines += [f"    pub {snake(name)}: Rgb," for name in color_names]
    lines += ["}", "", "pub const THEMES: &[(&str, Palette)] = &["]
    for theme, body in tokens["theme"].items():
        colors = body["color"]
        missing = set(color_names) - set(colors)
        if missing:
            raise ValueError(f"{theme} に色が足りません: {sorted(missing)}")
        lines.append(f'    ("{theme}", Palette {{')
        lines += [f"        {snake(n)}: {rgb(colors[n]['$value'])}," for n in color_names]
        lines.append("    }),")
    lines.append("];")
    # Windows の glass の色．ライトとダーク
    for appearance, body in tokens["glass"].items():
        if appearance.startswith("$"):
            continue
        if body.get("$type") == "color":
            lines.append("")
            lines.append(f"pub const GLASS_{upper(appearance)}: Rgb = {rgb(body['$value'])};")
            continue
        colors = body["color"]
        missing = set(color_names) - set(colors)
        if missing:
            raise ValueError(f"glass.{appearance} に色が足りません: {sorted(missing)}")
        lines.append("")
        lines.append(f"pub const GLASS_{upper(appearance)}: Palette = Palette {{")
        lines += [f"    {snake(n)}: {rgb(colors[n]['$value'])}," for n in color_names]
        lines.append("};")
    for group, sections in (("size", tokens["size"]), ("motion", tokens["motion"]), ("opacity", tokens["opacity"])):
        lines.append("")
        lines.append(f"pub mod {group} {{")
        for section, entries in sections.items():
            lines.append(f"    pub mod {snake(section)} {{")
            for name, token in entries.items():
                if "$value" in token:
                    lines.append(f"        pub const {upper(name)}: f32 = {number(token)!r};")
                else:
                    for sub, subtoken in token.items():
                        lines.append(f"        pub const {upper(name + '-' + sub)}: f32 = {number(subtoken)!r};")
            lines.append("    }")
        lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    text = render(json.loads(TOKENS.read_text(encoding="utf-8")))
    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else None
    if "--check" in argv:
        if current != text:
            print(f"{OUTPUT.relative_to(ROOT)}: design/tokens/tokens.json と合っていません．make tokens で作り直してください")
            return 1
        print("ok: Rust のトークンは design/tokens/tokens.json と合っています")
        return 0
    if current != text:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(text, encoding="utf-8")
        print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
