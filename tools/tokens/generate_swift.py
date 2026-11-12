"""design/tokens/tokens.json から Swift のコードを作る．

使い方: python3 -I tools/tokens/generate_swift.py [--check]
生成先(手で編集しない)
- apps/macos/Hajime/UI/Generated/DesignTokens.swift: macOS のアプリの色・寸法・動き・不透明度
- core/Sources/HajimeApplication/Generated/LayoutTokens.swift: core が窓の配置を決めるのに使う寸法(size)．
  パレットの説明の欄の高さとマス目の行の数を，Windows のエンジンのプロセスでも同じに決めるため
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

# 同じディレクトリの references.py を読む(python3 -I ではスクリプトのディレクトリが探す先に入らない)
sys.path.insert(0, str(Path(__file__).resolve().parent))
from references import resolve  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TOKENS = ROOT / "design" / "tokens" / "tokens.json"
OUTPUT = ROOT / "apps" / "macos" / "Hajime" / "UI" / "Generated" / "DesignTokens.swift"
CORE_OUTPUT = ROOT / "core" / "Sources" / "HajimeApplication" / "Generated" / "LayoutTokens.swift"


def camel(name: str) -> str:
    head, *rest = re.split(r"[-_]", name)
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def rgb(hex_color: str) -> str:
    value = hex_color.lstrip("#")
    r, g, b = (int(value[i : i + 2], 16) for i in (0, 2, 4))
    return f"RGB(red: 0x{r:02X}, green: 0x{g:02X}, blue: 0x{b:02X})"


def number(token: dict) -> str:
    value = token["$value"]
    if isinstance(value, dict):
        value = value["value"]
    return repr(float(value)) if isinstance(value, float) else str(value)


def render_core(tokens: dict) -> str:
    """core の寸法(1 ドット = 1pt の Double)．名前は macOS の DesignTokens.Size と同じ"""
    lines = [
        "// このファイルは tools/tokens/generate_swift.py が design/tokens/tokens.json から作る．手で編集しない．",
        "",
        "/// デザイントークンの寸法(design/tokens/tokens.json の size)",
        "public enum LayoutTokens {",
    ]
    for section, entries in tokens["size"].items():
        lines.append(f"    public enum {camel(section)[:1].upper() + camel(section)[1:]} {{")
        for name, token in entries.items():
            if name.startswith("$"):
                continue
            if "$value" in token:
                lines.append(f"        public static let {camel(name)}: Double = {number(token)}")
            else:
                for sub, subtoken in token.items():
                    lines.append(f"        public static let {camel(name + '-' + sub)}: Double = {number(subtoken)}")
        lines.append("    }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def write(path: Path, text: str, check: bool) -> bool:
    current = path.read_text(encoding="utf-8") if path.exists() else None
    if check:
        if current != text:
            print(f"{path.relative_to(ROOT)}: design/tokens/tokens.json と合っていません．make tokens で作り直してください")
            return False
        return True
    if current != text:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return True


def main(argv: list[str]) -> int:
    tokens = resolve(json.loads(TOKENS.read_text(encoding="utf-8")))
    color_names = sorted(next(iter(tokens["theme"].values()))["color"].keys())
    lines = [
        "// このファイルは tools/tokens/generate_swift.py が design/tokens/tokens.json から作る．手で編集しない．",
        "",
        "import CoreGraphics",
        "",
        "struct RGB: Equatable, Sendable {",
        "    let red: UInt8",
        "    let green: UInt8",
        "    let blue: UInt8",
        "}",
        "",
        "struct ThemePalette: Equatable, Sendable {",
    ]
    lines += [f"    let {camel(name)}: RGB" for name in color_names]
    lines += ["}", "", "enum DesignTokens {", "    enum Palette {"]
    for theme, body in tokens["theme"].items():
        colors = body["color"]
        missing = set(color_names) - set(colors)
        if missing:
            print(f"{theme} に色が足りません: {sorted(missing)}", file=sys.stderr)
            return 1
        args = ",\n".join(f"            {camel(n)}: {rgb(colors[n]['$value'])}" for n in color_names)
        lines.append(f"        static let {camel(theme)} = ThemePalette(\n{args}\n        )")
    lines.append("    }")
    # 寸法は 1 ドット = 1pt の CGFloat，動きの長さはミリ秒の Double，不透明度は 0〜1 の CGFloat
    for group, sections, swift_type in (("Size", tokens["size"], "CGFloat"), ("Motion", tokens["motion"], "Double"), ("Opacity", tokens["opacity"], "CGFloat")):
        lines.append(f"    enum {group} {{")
        for section, entries in sections.items():
            lines.append(f"        enum {camel(section)[:1].upper() + camel(section)[1:]} {{")
            for name, token in entries.items():
                if name.startswith("$"):
                    continue
                if "$value" in token:
                    lines.append(f"            static let {camel(name)}: {swift_type} = {number(token)}")
                else:
                    for sub, subtoken in token.items():
                        lines.append(f"            static let {camel(name + '-' + sub)}: {swift_type} = {number(subtoken)}")
            lines.append("        }")
        lines.append("    }")
    lines.append("}")
    check = "--check" in argv
    ok = write(OUTPUT, "\n".join(lines) + "\n", check) & write(CORE_OUTPUT, render_core(tokens), check)
    if check and ok:
        print("ok: Swift のトークンは design/tokens/tokens.json と合っています")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
