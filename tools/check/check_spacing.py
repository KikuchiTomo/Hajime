#!/usr/bin/env python3
"""余白の決まり(docs/dev/DESIGN-SYSTEM.md の「余白と部品」)を守っているかを確かめる．

トークン(design/tokens/tokens.json)
- size.space の段階は 2・4・8・12・16・24 だけ．役割(fine〜page)は段階を参照し，近さの順を守る
- size.text と size.part の値が $extensions.hajime.formula の式と一致する(部品の高さは式で決める)
- 画面のトークンの余白(名前に padding・gap・inset・margin・indent・spacing を含むもの)は，
  役割(size.space.<役割>)か部品(size.part)を参照する．段階の名前や数値を直接書かない．
  部品の値(アイコンの箱の余白 3 など)は部品の決まりで決めるので，段階に載らなくてよい

描画のコード(CODE_DIRS)
- 余白に数値を書かない(.padding(8)，spacing: 6，insetBy(dx: 0, dy: 2)，rect.minX + 4，x + 8.0 など)
- 余白のトークンを割ったり，2 以外の数を掛けたりして新しい余白を作らない(padding / 2，gap * 0.7)
- 段階の名前(Space.xs，space::SM)を使わず，役割の名前を使う

どうしても決まりから外れるものは ALLOWED_TOKENS に理由とともに書く．一覧は小さく保つ．
決まりを入れる前からの画面で，あとの PR で直すものは PENDING_SECTIONS と PENDING_FILES に直す PR とともに書く．
直し終えて決まりに合ったのに一覧に残っていれば止める(一覧が古くならないように)．
使い方: python3 -I tools/check/check_spacing.py
"""

from __future__ import annotations

import ast
import json
import operator
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKENS = ROOT / "design/tokens/tokens.json"
sys.path.insert(0, str(ROOT / "tools/tokens"))
from references import resolve  # noqa: E402

SCALE = {"xxs": 2, "xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24}
# 近さの順．左ほど狭い．"<" は前より広い，"<=" は前と同じか広い
ROLE_ORDER = [("fine", None), ("inset", "<"), ("inline", "<="), ("stack", "<="), ("group", "<"), ("section", "<="),
              ("window", "<="), ("page", "<")]
ROLES = {name for name, _ in ROLE_ORDER}
SYSTEM_SECTIONS = {"space", "text", "part"}
SPACING_NAME = re.compile(r"(padding|gap|inset|margin|indent|spacing)")

# 決まりから外れてよいトークンと理由
ALLOWED_TOKENS: dict[str, tuple[str, ...]] = {
    "Windows 11 の設定アプリと標準の部品(WinUI 3 の NavigationView・SettingsCard・TitleBar・TextBox・Button)と同じ寸法にする(ADR 0013)": (
        "settings-windows.page-padding-x", "settings-windows.page-padding-top", "settings-windows.section-gap",
        "settings-windows.card-padding-x", "settings-windows.card-padding-y", "settings-windows.button-padding-x",
        "settings-windows.field-padding-x", "settings-windows.nav-padding-x", "settings-windows.nav-icon-gap",
        "settings-windows.nav-group-gap", "settings-windows.control-gap", "settings-windows.title-bar-padding-x",
        "settings-windows.table-indicator-inset", "handwriting.control-padding-x",
    ),
    "macOS の表(Table)が描く行の字の位置に，表の外の見出しをそろえる": (
        "settings.table-header-inset", "settings.table-column-spacing", "settings.table-popup-text-inset",
    ),
    "窓の外の距離(画面の端・入力位置から窓まで，見本の画像の余白)．窓の中の余白ではない": (
        "candidate.screen-margin", "handwriting.anchor-gap", "prediction.gap", "snapshot.margin",
    ),
    "枝の曲線を曲げる幅．余白ではなく線の形": (
        "glass.branch-indent", "branch.branch-indent",
    ),
}

CODE_DIRS = [
    ROOT / "apps/macos/Hajime/UI",
    ROOT / "apps/macos/Hajime/Settings",
    ROOT / "apps/macos/Hajime/Onboarding",
    ROOT / "apps/windows/crates/candidate-ui/src",
    ROOT / "apps/windows/crates/settings/src",
    ROOT / "core/Sources/HajimeApplication",
]
# core は配置を決めるファイル(名前に Layout を含む)だけを見る
CORE_LAYOUT = re.compile(r"Layout\w*\.swift$")
SKIPPED_DIRS = {"Generated"}
# 動きの曲線の式を書くファイル．位置や余白を決めないので見ない
MOTION_FILES = {"motion.rs", "anim.rs", "PaletteMotion.swift"}

# 決まりを入れる前からの画面で，あとの PR で直すもの(トークンの節とファイル)．直したら外す
FOLLOW_UP_CANDIDATE = "#430 の次の PR で直す(候補の窓・分岐図・語の意味・案内と，予測・モードの札)"
FOLLOW_UP_SETTINGS = "設定の画面の PR で直す(template-ui が作り直し中)"
PENDING_SECTIONS: dict[str, str] = {
    "candidate": FOLLOW_UP_CANDIDATE, "glass": FOLLOW_UP_CANDIDATE, "branch": FOLLOW_UP_CANDIDATE, "meaning": FOLLOW_UP_CANDIDATE,
    "mode-indicator": FOLLOW_UP_CANDIDATE, "prediction": FOLLOW_UP_CANDIDATE,
    "settings": FOLLOW_UP_SETTINGS, "settings-windows": FOLLOW_UP_SETTINGS,
}
PENDING_FILES: dict[str, str] = {
    "apps/macos/Hajime/UI/BranchView.swift": FOLLOW_UP_CANDIDATE,
    "apps/macos/Hajime/UI/AssociationHeadingDrawing.swift": FOLLOW_UP_CANDIDATE,
    "apps/windows/crates/candidate-ui/src/scene/branch.rs": FOLLOW_UP_CANDIDATE,
    "apps/windows/crates/candidate-ui/src/scene/association.rs": FOLLOW_UP_CANDIDATE,
    "apps/macos/Hajime/Settings/AboutPage.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/AppearancePage.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/AssociationSection.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/DictionaryPage.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/EmojiSection.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/KeymapPage.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/SettingsRows.swift": FOLLOW_UP_SETTINGS,
    "apps/macos/Hajime/Settings/WordLanguagePage.swift": FOLLOW_UP_SETTINGS,
    "apps/windows/crates/candidate-ui/src/app/preview.rs": FOLLOW_UP_SETTINGS,
    "apps/windows/crates/settings/src/app/page.rs": FOLLOW_UP_SETTINGS,
    "apps/windows/crates/settings/src/app/paint.rs": FOLLOW_UP_SETTINGS,
    "apps/windows/crates/settings/src/app/window.rs": FOLLOW_UP_SETTINGS,
}

NUMBER = r"-?\d+(?:\.\d+)?"
SPACING_WORD = r"\w*(?:[Pp]adding|PADDING|[Gg]ap|GAP|[Ii]nset|INSET|[Mm]argin|MARGIN|[Ss]pacing|SPACING|[Ii]ndent|INDENT)\w*"
SWIFT_RULES = [
    (re.compile(rf"\.padding\((?:[^()]*,\s*)?({NUMBER})\)"), "余白に数値を書いている(.padding)"),
    (re.compile(rf"\bspacing:\s*({NUMBER})\b"), "余白に数値を書いている(spacing:)"),
    (re.compile(rf"insetBy\(dx:\s*({NUMBER}),\s*dy:\s*({NUMBER})\)"), "余白に数値を書いている(insetBy)"),
    (re.compile(rf"\.(?:minX|maxX|minY|maxY|midX|midY)\s*[+-]\s*({NUMBER})\b(?!\s*[*/])"), "位置に数値を足している"),
    (re.compile(rf"\b{SPACING_WORD}\s*/\s*({NUMBER})"), "余白のトークンを割って新しい余白を作っている"),
    (re.compile(rf"\b{SPACING_WORD}\s*\*\s*({NUMBER})"), "余白のトークンに 2 以外の数を掛けている"),
    (re.compile(r"\bSpace\.(xxs|xs|sm|md|lg|xl)\b"), "段階の名前を使っている．役割(Space.inset など)を使う"),
]
RUST_RULES = [
    (re.compile(r"\s[+-]\s+(\d+\.\d+)(?:_?f32)?\b(?!\s*[*/])"), "位置や大きさに数値を足している"),
    (re.compile(rf"\.inset\(({NUMBER}),\s*({NUMBER})\)"), "余白に数値を書いている(inset)"),
    (re.compile(rf"\b{SPACING_WORD}\s*/\s*({NUMBER})"), "余白のトークンを割って新しい余白を作っている"),
    (re.compile(rf"\b{SPACING_WORD}\s*\*\s*({NUMBER})"), "余白のトークンに 2 以外の数を掛けている"),
    (re.compile(r"\bspace::(XXS|XS|SM|MD|LG|XL)\b"), "段階の名前を使っている．役割(space::INSET など)を使う"),
]
# 1 ドットの線の位置合わせ(1 と 1 より小さい数)と 0 は余白ではないので数えない
IGNORED_NUMBERS = {1.0, -1.0}
STRING = re.compile(r'"(?:[^"\\]|\\.)*"')


def number(token: dict) -> float:
    value = token["$value"]
    if isinstance(value, dict):
        value = value["value"]
    return float(value)


def entries(section: dict):
    for name, token in section.items():
        if name.startswith("$"):
            continue
        if "$value" in token:
            yield name, token
        else:
            for sub, subtoken in token.items():
                yield f"{name}-{sub}", subtoken


def evaluate(formula: str, values: dict[str, float]) -> float:
    """「{size.text.tag-line} + {size.space.fine} * 2」の形の式を計算する"""
    expression = re.sub(r"\{([a-z0-9.-]+)\}", lambda m: repr(values[m.group(1)]), formula)
    operators = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv}

    def walk(node: ast.AST) -> float:
        if isinstance(node, ast.Expression):
            return walk(node.body)
        if isinstance(node, ast.BinOp) and type(node.op) in operators:
            return operators[type(node.op)](walk(node.left), walk(node.right))
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return float(node.value)
        raise ValueError(f"式に使えないものがあります: {formula}")

    return walk(ast.parse(expression, mode="eval"))


def check_tokens(raw: dict) -> list[str]:
    errors: list[str] = []
    resolved = resolve(raw)
    size, flat = resolved["size"], {}
    for section, body in size.items():
        for name, token in entries(body):
            flat[f"size.{section}.{name}"] = number(token)

    space = raw["size"]["space"]
    for name, value in SCALE.items():
        if name not in space or number(space[name]) != value:
            errors.append(f"size.space.{name}: 段階は {value} にする")
    for name, _ in entries(space):
        if name not in SCALE and name not in ROLES:
            errors.append(f"size.space.{name}: 段階({'・'.join(SCALE)})か役割({'・'.join(sorted(ROLES))})だけを置く")
    previous = None
    for role, relation in ROLE_ORDER:
        if role not in space:
            errors.append(f"size.space.{role}: 役割がありません")
            continue
        target = space[role]["$value"]
        if not (isinstance(target, str) and target.strip("{}").split(".")[-1] in SCALE):
            errors.append(f"size.space.{role}: 役割は段階を参照する(今は {target})")
        value = flat[f"size.space.{role}"]
        if previous is not None:
            name, before = previous
            if (relation == "<" and not value > before) or (relation == "<=" and not value >= before):
                errors.append(f"size.space.{role}({value:g}): {name}({before:g}) {'より広く' if relation == '<' else 'と同じか広く'}する")
        previous = (role, value)

    for section in ("text", "part"):
        for name, token in entries(raw["size"][section]):
            formula = token.get("$extensions", {}).get("hajime", {}).get("formula")
            if formula and abs(evaluate(formula, flat) - flat[f"size.{section}.{name}"]) > 1e-6:
                errors.append(f"size.{section}.{name}: 値 {flat[f'size.{section}.{name}']:g} が式 {formula} と合いません")

    allowed = {path for paths in ALLOWED_TOKENS.values() for path in paths}
    seen: set[str] = set()
    pending_hits: set[str] = set()
    for section, body in raw["size"].items():
        if section in SYSTEM_SECTIONS:
            continue
        section_errors: list[str] = []
        for name, token in entries(body):
            key = f"{section}.{name}"
            if not SPACING_NAME.search(name):
                continue
            seen.add(key)
            if key in allowed:
                continue
            value = token["$value"]
            target = value.strip("{}") if isinstance(value, str) else None
            parts = target.split(".") if target else []
            if not target:
                section_errors.append(f"size.{key}: 余白に数値 {number(token):g} を書いている．size.space の役割か size.part を参照する")
            elif parts[:2] == ["size", "space"] and parts[2] not in ROLES:
                section_errors.append(f"size.{key}: 段階の名前({target})を参照している．役割を参照する")
            elif parts[:2] not in (["size", "space"], ["size", "part"]):
                section_errors.append(f"size.{key}: {target} を参照している．size.space の役割か size.part を参照する")
            elif parts[:2] == ["size", "space"] and flat[f"size.{key}"] not in SCALE.values():
                section_errors.append(f"size.{key}: 値 {flat[f'size.{key}']:g} が段階にありません")
        if section in PENDING_SECTIONS:
            if section_errors:
                pending_hits.add(section)
        else:
            errors += section_errors
    for key in sorted(allowed - seen):
        errors.append(f"ALLOWED_TOKENS の size.{key} はもう無いか，余白のトークンではありません．一覧から外す")
    for section in sorted(set(PENDING_SECTIONS) - pending_hits):
        errors.append(f"PENDING_SECTIONS の size.{section} は決まりに合いました．一覧から外す")
    return errors


def code_files() -> list[Path]:
    files: list[Path] = []
    for directory in CODE_DIRS:
        for path in sorted(directory.rglob("*")):
            if path.suffix not in (".swift", ".rs") or path.name in MOTION_FILES or SKIPPED_DIRS & set(path.relative_to(ROOT).parts):
                continue
            if "core/Sources" in str(path) and not CORE_LAYOUT.search(path.name):
                continue
            files.append(path)
    return files


def literal_values(match: re.Match) -> list[float]:
    return [float(group) for group in match.groups() if group is not None and re.fullmatch(NUMBER, group)]


def violation(rule_message: str, match: re.Match) -> bool:
    values = literal_values(match)
    if "段階の名前" in rule_message:
        return True
    if "2 以外" in rule_message:
        return any(value != 2 for value in values)
    return any(value not in IGNORED_NUMBERS and abs(value) >= 1 for value in values)


def check_code() -> list[str]:
    errors: list[str] = []
    pending_hits: set[str] = set()
    for path in code_files():
        relative = str(path.relative_to(ROOT))
        file_errors: list[str] = []
        rust = path.suffix == ".rs"
        rules = RUST_RULES if rust else SWIFT_RULES
        for number_, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if rust and line.strip().startswith("#[cfg(test)]"):
                break
            code = STRING.sub('""', line).split("//", 1)[0]
            if not code.strip():
                continue
            for pattern, message in rules:
                for match in pattern.finditer(code):
                    if violation(message, match):
                        file_errors.append(f"{relative}:{number_}: {message}: {code.strip()}")
        if relative in PENDING_FILES:
            if file_errors:
                pending_hits.add(relative)
        else:
            errors += file_errors
    for relative in sorted(set(PENDING_FILES) - pending_hits):
        errors.append(f"PENDING_FILES の {relative} は決まりに合いました(か，もうありません)．一覧から外す")
    return errors


def main() -> int:
    errors = check_tokens(json.loads(TOKENS.read_text(encoding="utf-8"))) + check_code()
    for error in errors:
        print(error)
    if errors:
        print(f"\n余白の決まりに合わないものが {len(errors)} 件あります(docs/dev/DESIGN-SYSTEM.md の「余白と部品」)", file=sys.stderr)
        return 1
    print(f"ok: 余白は役割のトークンから選ばれています(あとの PR で直すもの: トークンの節 {len(PENDING_SECTIONS)}，ファイル {len(PENDING_FILES)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
