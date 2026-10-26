#!/usr/bin/env python3
"""Windows の画面の文言(apps/windows/crates/settings/src/strings.rs)が，macOS の文言(UIStrings.swift)と同じかを確かめる．

strings.rs の「/// UIStrings.X」の付いたまとまりの定数は，UIStrings.X の同じ名前の値と同じでなければならない
(定数の名前は NAME_LIKE_THIS と nameLikeThis を大文字と小文字を区別せずに比べる)．
キー設定の状態・ひな形・コマンドの名前の表も，UIStrings.Keys の label(for:) と同じでなければならない．
Windows だけの文言は「pub mod windows」に置き，ここでは比べない．
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "apps/macos/S90IME/UI/UIStrings.swift"
RUST = ROOT / "apps/windows/crates/settings/src/strings.rs"
OPTIONS = ROOT / "apps/windows/crates/settings/src/options.rs"

# options.rs の選択肢の表と，同じ名前を返す macOS の label(for:)(入れ子の enum，引数の型)
OPTION_TABLES = {
    "INPUT_STYLES": ("Choice", "InputStyle"),
    "KEYBOARD_LAYOUTS": ("Choice", "KeyboardLayout"),
    "WIDTHS": ("Settings", "CharacterWidth"),
    "YEN_KEY": ("Choice", "YenKeyPolicy"),
    "PRESENTATIONS": ("Choice", "CandidatePresentation"),
    "INITIAL_FOCUS": ("Choice", "InitialFocus"),
    "SUGGESTION_DISPLAY": ("Choice", "SuggestionDisplay"),
    "TYPO_CORRECTION": ("Choice", "TypoCorrectionLevel"),
    "CORRECTION_SENSITIVITY": ("More", "CorrectionSensitivity"),
    "OKURIGANA": ("Features", "OkuriganaStyle"),
    "LEARNING": ("Settings", "LearningMode"),
    "WORD_LANGUAGES": ("Features", "WordLanguage"),
    "WORD_CONTEXTS": ("Features", "WordLanguageContext"),
    "APP_PROFILES": ("Settings", "AppProfile"),
    "THEMES": ("Choice", "ThemePreference"),
    "SYNC_SCOPES": ("Sync", "SyncScope"),
    "SYNC_GROUPS": ("Sync", "SyncGroup"),
    "BRANCH_STYLES": ("More", "CustomTheme.BranchStyle"),
}
# Windows で名前を変える選択肢(macOS の Command のキーを，Windows では Ctrl のキーにする)
WINDOWS_ONLY_OPTIONS = {("KEYBOARD_LAYOUTS", "dvorakQwertyCommand"), ("SYNC_SCOPES", "local")}
SYNC_MODEL = ROOT / "core/Sources/S90Domain/Sync/SyncModel.swift"

STRING = r'"((?:[^"\\]|\\.)*)"'


def swift_constants(text: str) -> dict[tuple[str, str], str]:
    """UIStrings の入れ子の enum ごとの static let の文字列"""
    constants: dict[tuple[str, str], str] = {}
    enums: list[tuple[str, int]] = []
    depth = 0
    for line in text.split("\n"):
        enum = re.match(r"\s*(?:public |private |fileprivate )?enum (\w+)\b.*\{", line)
        if enum:
            enums.append((enum.group(1), depth))
        constant = re.match(rf"\s*static let (\w+)(?:: String)? = {STRING}\s*$", line)
        if constant and enums:
            constants[(enums[-1][0], constant.group(1).lower())] = constant.group(2)
        depth += line.count("{") - line.count("}")
        while enums and depth <= enums[-1][1]:
            enums.pop()
    return constants


def swift_label_functions(text: str) -> list[tuple[str, str, dict[str, str]]]:
    """(入れ子の enum の名前，引数の型，case ごとの名前)．名前が別の label(for:) を呼ぶ case は，呼び先の名前として返す"""
    functions: list[tuple[str, str, dict[str, str]]] = []
    enums: list[tuple[str, int]] = []
    depth = 0
    current: tuple[str, str, dict[str, str], int] | None = None
    for line in text.split("\n"):
        enum = re.match(r"\s*(?:public |private |fileprivate )?enum (\w+)\b.*\{", line)
        if enum:
            enums.append((enum.group(1), depth))
        function = re.match(r"\s*static func label\(for \w+: ([\w.]+)\) -> String \{", line)
        if function and enums:
            current = (enums[-1][0], function.group(1), {}, depth)
        elif current:
            case = re.match(rf"\s*case (\.[\w, .]+): (?:{STRING}|(\w+)\.label\(for: \.(\w+)\))", line)
            if case:
                value = case.group(2) if case.group(2) is not None else f"@{case.group(3)}.{case.group(4)}"
                for name in re.findall(r"\.(\w+)", case.group(1)):
                    current[2][name] = value
        depth += line.count("{") - line.count("}")
        if current and depth <= current[3]:
            functions.append(current[:3])
            current = None
        while enums and depth <= enums[-1][1]:
            enums.pop()
    return functions


def swift_labels(text: str, kind: str, enum_name: str | None = None) -> dict[str, str]:
    """引数の型が kind の label(for:) の名前(enum_name があればその enum の中のもの)．別の label(for:) を呼ぶものはたどる"""
    functions = swift_label_functions(text)

    def resolve(value: str) -> str:
        reference = re.fullmatch(r"@(\w+)\.(\w+)", value)
        if not reference:
            return value
        for enum, _, labels in functions:
            if enum == reference.group(1) and reference.group(2) in labels:
                return resolve(labels[reference.group(2)])
        return value

    for enum, argument, labels in functions:
        if argument == kind and enum_name in (None, enum):
            return {name: resolve(value) for name, value in labels.items()}
    return {}


def rust_constants(text: str) -> list[tuple[str, str, str]]:
    """(UIStrings のまとまり，定数の名前，値)．windows のまとまりは除く"""
    text = re.sub(r'=\s*\n\s*"', '= "', text)
    group: str | None = None
    found: list[tuple[str, str, str]] = []
    for line in text.split("\n"):
        mark = re.match(r"/// UIStrings\.(\w+)", line)
        if mark:
            group = mark.group(1)
        elif line.startswith("pub mod windows"):
            group = None
        constant = re.match(rf"\s*pub const (\w+): &str = {STRING};", line)
        if constant and group:
            found.append((group, constant.group(1), constant.group(2)))
    return found


def rust_table(text: str, name: str) -> dict[str, str]:
    start = text.find(f"pub const {name}: &[(&str, &str)] = &[")
    if start < 0:
        return {}
    end = text.find("];", start)
    return dict(re.findall(rf'\("(\w+)", {STRING}\)', text[start:end]))


def check() -> list[str]:
    swift = SWIFT.read_text(encoding="utf-8")
    rust = RUST.read_text(encoding="utf-8")
    mac = swift_constants(swift)
    problems: list[str] = []
    for group, name, value in rust_constants(rust):
        key = (group, name.replace("_", "").lower())
        if key not in mac:
            problems.append(f"{name}: UIStrings.{group} に同じ名前の文言がありません(Windows だけの文言は pub mod windows に置く)")
        elif mac[key] != value:
            problems.append(f"{name}: 「{value}」が macOS の「{mac[key]}」と違います")
    for table, kind in (("STATES", "KeymapState"), ("PRESETS", "KeymapPreset"), ("COMMANDS", "KeymapCommand")):
        windows = rust_table(rust, table)
        labels = swift_labels(swift, kind)
        for value in sorted(set(windows) | set(labels)):
            if windows.get(value) != labels.get(value):
                problems.append(f"{table} の {value}: Windows「{windows.get(value)}」と macOS「{labels.get(value)}」が違います")
    options = OPTIONS.read_text(encoding="utf-8").replace("pub const ", "pub const ").replace(": &[Choice] = &[", ": &[(&str, &str)] = &[")
    for table, (enum, kind) in OPTION_TABLES.items():
        labels = swift_labels(swift, kind, enum)
        if not labels:
            problems.append(f"{table}: UIStrings.{enum} に label(for: {kind}) がありません")
            continue
        # Windows に無い選択肢(標準と同じ見た目のテーマなど)は並べなくてよい．並べたものは同じ名前にする
        for value, name in rust_table(options, table).items():
            if (table, value) not in WINDOWS_ONLY_OPTIONS and labels.get(value) != name:
                problems.append(f"{table} の {value}: Windows「{name}」と macOS「{labels.get(value)}」が違います")
    # 同期の項目の名前: macOS の fieldLabels が同期のまとまりのすべての項目を持ち，Windows の FIELD_LABELS が同じ名前か
    labels = swift_field_labels(swift, mac)
    model = SYNC_MODEL.read_text(encoding="utf-8")
    names = model[model.index("public var fieldNames"):model.index("public var legacyFieldNames")]
    for field in re.findall(r'"(\w+)"', names):
        if field not in labels:
            problems.append(f"UIStrings.Sync の fieldLabels に {field} の名前がありません")
    for field, name in rust_table(rust, "FIELD_LABELS").items():
        if labels.get(field) != name:
            problems.append(f"FIELD_LABELS の {field}: Windows「{name}」と macOS「{labels.get(field)}」が違います")
    return problems


def swift_field_labels(text: str, constants: dict[tuple[str, str], str]) -> dict[str, str]:
    """UIStrings.Sync.fieldLabels の項目ごとの名前．ほかの文言を指すものはその値にする"""
    start = text.index("private static let fieldLabels")
    block = text[start:text.index("\n        ]", start)]
    labels: dict[str, str] = {}
    for field, literal, reference in re.findall(rf'"(\w+)": (?:{STRING}|((?:UIStrings\.)?\w+\.\w+))', block):
        if reference:
            group, name = reference.removeprefix("UIStrings.").split(".")
            labels[field] = constants.get((group, name.lower()), reference)
        else:
            labels[field] = literal
    return labels


def main() -> int:
    problems = check()
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
