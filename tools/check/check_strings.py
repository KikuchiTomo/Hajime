#!/usr/bin/env python3
"""Windows の画面の文言(apps/windows/crates/settings/src/strings.rs)が，macOS の文言(UIStrings.swift)と同じかを確かめる．

strings.rs の「/// UIStrings.X」の付いたまとまりの定数は，UIStrings.X の同じ名前の値と同じでなければならない
(定数の名前は NAME_LIKE_THIS と nameLikeThis を大文字と小文字を区別せずに比べる)．
キー設定の状態・ひな形・コマンドの名前の表も，UIStrings.Keys の label(for:) と同じでなければならない．
書き方の早見表(UIStrings.Templates のまとまりと行)も，strings.rs の templates と同じでなければならない(例の値は Windows だけなので比べない)．
設定の項目名の横に出す候補の見本(strings.rs の …_EXAMPLE)は，core の DefaultSettings の同じ名前の見本と同じでなければならない
(DefaultSettings の見本は，本物のエンジンで実際に出ることを SettingsExampleTests で確かめている)．
Windows だけの文言は「pub mod windows」に置き，ここでは比べない．
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "apps/macos/Hajime/UI/UIStrings.swift"
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
    "WORD_CLASSES": ("Settings", "WordClass"),
}
# Windows で名前を変える選択肢(macOS の Command のキーを，Windows では Ctrl のキーにする)
WINDOWS_ONLY_OPTIONS = {("KEYBOARD_LAYOUTS", "dvorakQwertyCommand"), ("SYNC_SCOPES", "local")}
SYNC_MODEL = ROOT / "core/Sources/HajimeDomain/Sync/SyncModel.swift"
# 専門用語の辞書の分野の名前(core の TermField.name)．Windows の設定の画面は strings.rs の terms::FIELD_NAMES
TERM_FIELDS = ROOT / "core/Sources/HajimeDomain/Dictionary/TermDictionary.swift"
DEFAULT_SETTINGS = ROOT / "core/Sources/HajimeDomain/Settings/DefaultSettings.swift"

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


def swift_label_functions(text: str, function_name: str = "label") -> list[tuple[str, str, dict[str, str]]]:
    """(入れ子の enum の名前，引数の型，case ごとの名前)．名前が別の label(for:) を呼ぶ case は，呼び先の名前として返す"""
    functions: list[tuple[str, str, dict[str, str]]] = []
    enums: list[tuple[str, int]] = []
    depth = 0
    current: tuple[str, str, dict[str, str], int] | None = None
    for line in text.split("\n"):
        enum = re.match(r"\s*(?:public |private |fileprivate )?enum (\w+)\b.*\{", line)
        if enum:
            enums.append((enum.group(1), depth))
        function = re.match(rf"\s*static func {function_name}\(for \w+: ([\w.]+)\) -> String\?? \{{", line)
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
    # rustfmt は短い組を 1 行に，長い組を 1 項目 1 行に書く．どちらも読む
    return dict(re.findall(rf'\(\s*"(\w+)",\s*{STRING},?\s*\)', text[start:end]))


TEMPLATE_KINDS = {"syntax": "Syntax", "filter": "Filter", "formatSymbol": "FormatSymbol"}


def swift_templates(text: str) -> list[tuple[str, str, list[tuple[str, str, str, bool]]]]:
    """UIStrings.Templates のまとまり(見出し，種類，行の書き方・意味・例を求める書き方・コードの値か)．書いた順"""
    start = text.index("    enum Templates {")
    block = text[start:text.index("\n    }\n", start)]
    groups: list[tuple[str, str, list[tuple[str, str, str, bool]]]] = []
    for line in block.split("\n"):
        group = re.search(rf"(?:TemplateReference\.Group\(|\.init\()title: {STRING}, kind: \.(\w+), items: \[", line)
        if group:
            groups.append((group.group(1), TEMPLATE_KINDS.get(group.group(2), group.group(2)), []))
            continue
        item = re.search(rf"\.init\({STRING}, {STRING}(?:, sample: {STRING})?(?:, codeValue: (true))?\)", line)
        if item and groups:
            code = item.group(1)
            groups[-1][2].append((code, item.group(2), item.group(3) or code, item.group(4) == "true"))
    return groups


def rust_templates(text: str) -> tuple[list[tuple[str, str, list[tuple[str, str, str, bool]]]], list[str], list[str], list[str]]:
    """strings.rs の templates のまとまり(書いた順)，まとまりの定数の名前，WORD と MACRO に並べた名前．
    rustfmt が長い行を折り返すので，行ごとではなくまとまりの中を通して読む"""
    start = text.index("pub mod templates {")
    block = text[start:text.index("\n}\n", start)]
    groups: list[tuple[str, str, list[tuple[str, str, str, bool]]]] = []
    names: list[str] = []
    heads = list(re.finditer(rf"const (\w+): Group = Group \{{\s*title: {STRING},\s*kind: Kind::(\w+),", block))
    for index, head in enumerate(heads):
        body = block[head.end():heads[index + 1].start() if index + 1 < len(heads) else len(block)]
        names.append(head.group(1))
        items: list[tuple[str, str, str, bool]] = []
        pattern = rf"Item::(new|with_sample)\(\s*{STRING},\s*{STRING},(?:\s*{STRING},)?\s*{STRING},?\s*\)(\s*\.code_value\(\))?"
        for item in re.finditer(pattern, body):
            code = item.group(2)
            sample = item.group(4) if item.group(1) == "with_sample" else code
            items.append((code, item.group(3), sample, item.group(6) is not None))
        groups.append((head.group(2), head.group(3), items))

    def listed(name: str) -> list[str]:
        found = re.search(rf"pub const {name}: &\[Group\] = &\[([^\]]*)\];", block)
        return [entry.strip() for entry in found.group(1).split(",") if entry.strip()] if found else []

    return groups, names, listed("WORD"), listed("MACRO")


def check_templates(swift: str, rust: str) -> list[str]:
    problems: list[str] = []
    mac = swift_templates(swift)
    windows, names, word, macro = rust_templates(rust)
    if len(mac) != len(windows):
        problems.append(f"書き方の早見表のまとまりの数が違います: macOS {len(mac)} と Windows {len(windows)}")
    for (mac_title, mac_kind, mac_items), (win_title, win_kind, win_items) in zip(mac, windows):
        if (mac_title, mac_kind) != (win_title, win_kind):
            problems.append(f"書き方の早見表のまとまり: macOS「{mac_title}」({mac_kind})と Windows「{win_title}」({win_kind})が違います")
        for index in range(max(len(mac_items), len(win_items))):
            mac_item = mac_items[index] if index < len(mac_items) else None
            win_item = win_items[index] if index < len(win_items) else None
            if mac_item != win_item:
                problems.append(f"書き方の早見表の「{mac_title}」の {index + 1} 行目: macOS {mac_item} と Windows {win_item} が違います")
    # macOS は 1 つ目のまとまり(語と読み)を変換マクロだけに置く．Windows も同じ並びにする
    if "static let word = TemplateReference(groups)" not in swift or "static let macro = TemplateReference([textGroup] + groups)" not in swift:
        problems.append("UIStrings.Templates の word と macro の組み方が check_strings.py の想定と違います")
    if macro != names or word != names[1:]:
        problems.append(f"strings.rs の templates の WORD と MACRO は，まとまりを書いた順に並べる(MACRO は {names}，WORD はその 2 つ目から)")
    return problems


def check() -> list[str]:
    swift = SWIFT.read_text(encoding="utf-8")
    rust = RUST.read_text(encoding="utf-8")
    mac = swift_constants(swift)
    problems: list[str] = check_templates(swift, rust)
    for group, name, value in rust_constants(rust):
        key = (group, name.replace("_", "").lower())
        # macOS で上限の値を差し込む文言は，Windows では目録の上限と同じ数かを Rust のテストで確かめる(strings.rs の limits のテスト)
        if key in mac and "\\(" in mac[key]:
            continue
        if key not in mac:
            problems.append(f"{name}: UIStrings.{group} に同じ名前の文言がありません(Windows だけの文言は pub mod windows に置く)")
        elif mac[key] != value:
            problems.append(f"{name}: 「{value}」が macOS の「{mac[key]}」と違います")
    # コマンドの説明(macOS の Keys.help(for:)．説明の無いコマンドは並べない)
    help_labels = next((labels for enum, kind, labels in swift_label_functions(swift, "help") if kind == "KeymapCommand"), {})
    windows_help = rust_table(rust, "COMMAND_HELP")
    for value in sorted(set(windows_help) | {name for name, text in help_labels.items() if text != "@nil"}):
        if windows_help.get(value) != help_labels.get(value):
            problems.append(f"COMMAND_HELP の {value}: Windows「{windows_help.get(value)}」と macOS「{help_labels.get(value)}」が違います")
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
    # 専門用語の辞書の分野の名前と並び: core の TermField.name と Windows の terms::FIELD_NAMES が同じか
    core = TERM_FIELDS.read_text(encoding="utf-8")
    block = core[core.index("public var name: String {"):]
    block = block[:block.index("\n    }\n")]
    core_names = re.findall(rf"case \.(\w+): {STRING}", block)
    start = rust.index("pub const FIELD_NAMES: &[(&str, &str)] = &[")
    windows_names = re.findall(rf'\("(\w+)", {STRING}\)', rust[start:rust.index("];", start)])
    if core_names != windows_names:
        problems.append(f"terms::FIELD_NAMES が core の TermField.name と違います: Windows {windows_names} と core {core_names}")
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
    return problems + check_examples(rust)


def check_examples(rust: str) -> list[str]:
    """strings.rs の候補の見本(NAME_EXAMPLE: (&str, &str))が DefaultSettings の nameExample と同じか"""
    problems: list[str] = []
    core = {name.lower(): (reading, candidate) for name, reading, candidate in re.findall(
        rf'static let (\w+Example) = \(reading: {STRING}, candidate: {STRING}\)', DEFAULT_SETTINGS.read_text(encoding="utf-8"))}
    for name, reading, candidate in re.findall(rf'pub const (\w+_EXAMPLE): \(&str, &str\) = \(\s*{STRING},\s*{STRING},?\s*\);', rust):
        key = name.replace("_", "").lower()
        if key not in core:
            problems.append(f"{name}: DefaultSettings に同じ名前の見本がありません")
        elif core[key] != (reading, candidate):
            problems.append(f"{name}: Windows「{reading} → {candidate}」が DefaultSettings の「{core[key][0]} → {core[key][1]}」と違います")
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
