#!/usr/bin/env python3
"""設定のすべての項目が，macOS と Windows の設定の画面に操作の部品を持ち，値を変えて動きを確かめるテストを持つかを確かめる．

項目は Settings の CodingKeys(設定のファイルの項目の名前)．中に項目を持つ値(correction・wordLanguage)は，
中の項目(correction.english など)を 1 つずつ確かめる．

- macOS: apps/macos/Hajime/Settings/ の中で，値を書き換える形で項目を指していれば部品がある
  (キーパス「\\.項目」，model.update の中の「$0.項目」「settings.項目」)．model.settings.項目 は読むだけなので数えない
- Windows: apps/windows/crates/settings/src/pages.rs の行の道筋(「"項目"」「"項目.中の項目"」)か，
  道筋を持たない部品(WINDOWS_CONTROLS)があれば部品がある．出す・使える条件と，一緒に空にする項目は数えない
- テスト: core/Tests の中で項目に値を入れていれば(「.項目 = 」など)，値を変えて動きを確かめるテストがある．
  設定の読み書きそのものを確かめるテスト(STORAGE_TESTS)は数えない

画面に出さない項目は HIDDEN に，core で動きを確かめられない項目は UNTESTED に理由とともに書く．
使い方: python3 -I tools/check/check_settings_fields.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SETTINGS = ROOT / "core/Sources/HajimeDomain/Settings/Settings.swift"
# 中に項目を持つ値と，その型と，型の CodingKeys がある場所
NESTED = {
    "correction": ("CorrectionCustomization", ROOT / "core/Sources/HajimeDomain/Correction/CorrectionCustomization.swift"),
    "wordLanguage": ("WordLanguageSettings", ROOT / "core/Sources/HajimeDomain/Correction/WordLanguage.swift"),
}
# 中の項目の名前を enum の case から決める値(項目の名前が enum の rawValue)と，その enum がある場所
NESTED_ENUMS = {
    "termFields": ("TermField", ROOT / "core/Sources/HajimeDomain/Dictionary/TermDictionary.swift"),
}
MACOS = ROOT / "apps/macos/Hajime/Settings"
WINDOWS_PAGES = ROOT / "apps/windows/crates/settings/src/pages.rs"
TESTS = ROOT / "core/Tests"
# 設定の読み書き・同期・書き出しを確かめるテスト．値を入れても動きは確かめない
STORAGE_TESTS = {
    "SettingsCatalogTests.swift", "FileSettingsStoreTests.swift", "SettingsTransferTests.swift", "SettingsFilesTests.swift",
    "SettingsFileRequestTests.swift", "SyncTests.swift", "Fakes.swift",
}

# Windows で値の道筋を持たない部品と，その部品が書き換える項目
WINDOWS_CONTROLS = {
    # 記号の決まりは，エンジンが既定の決まりに重ねた一覧を読み，決まりを 1 つずつ重ねる・外す
    "Control::Symbols(": ("symbolRules",),
    # カスタムテーマの一覧の「使う」で，使うテーマを選ぶ
    "Control::CustomThemes(": ("customThemes", "customThemeID"),
}

# 画面に部品を置かない項目と理由．OS ごとに書く
HIDDEN: dict[str, dict[str, str]] = {
    "macos": {},
    "windows": {},
}

# core のテストで動きを確かめられない項目と理由
UNTESTED: dict[str, str] = {}


def coding_keys(text: str, type_name: str | None = None) -> list[str]:
    """型の中の CodingKeys の case の名前．type_name が無ければファイルの最初の CodingKeys"""
    if type_name:
        start = re.search(rf"\bstruct {type_name}\b", text)
        if not start:
            raise ValueError(f"{type_name} が見つかりません")
        text = text[start.start():]
    block = re.search(r"enum CodingKeys: String, CodingKey[^{]*\{(.*?)\n\s*\}", text, re.DOTALL)
    if not block:
        raise ValueError("CodingKeys が見つかりません")
    return [name for line in re.findall(r"\bcase ([^\n]+)", block.group(1)) for name in re.findall(r"\w+", line)]


def enum_cases(text: str, type_name: str) -> list[str]:
    """enum の case の名前(switch の「case .x:」は除く)"""
    start = re.search(rf"\benum {type_name}\b[^{{]*\{{", text)
    if not start:
        raise ValueError(f"{type_name} が見つかりません")
    names: list[str] = []
    for line in text[start.end():].split("\n"):
        if re.match(r"\s*(?:public |private )?(?:var|func|init|static)\b", line):
            break
        case = re.match(r"\s*case ([a-z]\w*(?:, *[a-z]\w*)*)\s*$", line)
        if case:
            names.extend(name.strip() for name in case.group(1).split(","))
    return names


def setting_paths() -> list[str]:
    """確かめる項目の道筋．中に項目を持つ値は中の項目にする"""
    paths: list[str] = []
    for field in coding_keys(SETTINGS.read_text(encoding="utf-8")):
        if field in NESTED:
            type_name, source = NESTED[field]
            paths.extend(f"{field}.{name}" for name in coding_keys(source.read_text(encoding="utf-8"), type_name))
        elif field in NESTED_ENUMS:
            type_name, source = NESTED_ENUMS[field]
            paths.extend(f"{field}.{name}" for name in enum_cases(source.read_text(encoding="utf-8"), type_name))
        else:
            paths.append(field)
    return paths


def macos_controls(paths: list[str]) -> set[str]:
    text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MACOS.glob("*.swift")))
    found = set()
    for path in paths:
        name = re.escape(path)
        # キーパス(ResettableToggle・binding)と，model.update などの中で書き換える値
        if re.search(rf"\\\.{name}\b|\$0\.{name}\b|(?<![\w.])settings\.{name}\b", text):
            found.add(path)
    return found


def windows_controls(paths: list[str]) -> set[str]:
    text = WINDOWS_PAGES.read_text(encoding="utf-8")
    text = text.split("#[cfg(test)]")[0]
    # 出す・使える条件，一緒に空にする項目，一覧どうしの排他は部品ではない
    text = re.sub(r'\b(?:Is|IsNot|On|clearing|Some)\(\s*"[^"]*"', "", text)
    literals = set(re.findall(r'"([\w.]+)"', text))
    found = {path for path in paths if path in literals}
    for control, fields in WINDOWS_CONTROLS.items():
        if control in text:
            found.update(fields)
    return found


def tested(paths: list[str]) -> set[str]:
    """core/Tests で値を入れている項目(代入・toggle・一覧への追加)"""
    text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(TESTS.rglob("*.swift")) if path.name not in STORAGE_TESTS)
    found = set()
    for path in paths:
        if re.search(rf"\.{re.escape(path)}\s*(?:=[^=]|\+=|\.toggle\(|\.append\(|\.insert\(|\.remove)", text):
            found.add(path)
    return found


def check() -> list[str]:
    paths = setting_paths()
    problems: list[str] = []
    for platform, found, where in (
        ("macos", macos_controls(paths), "apps/macos/Hajime/Settings/"),
        ("windows", windows_controls(paths), "apps/windows/crates/settings/src/pages.rs"),
    ):
        hidden = HIDDEN[platform]
        for path in paths:
            if path not in found and path not in hidden:
                problems.append(f"{path}: {where} に操作の部品がありません(画面に出さないなら HIDDEN[\"{platform}\"] に理由を書く)")
            elif path in found and path in hidden:
                problems.append(f"{path}: {where} に部品があるので，HIDDEN[\"{platform}\"] から外してください")
        for path in sorted(set(hidden) - set(paths)):
            problems.append(f"{path}: 設定に無い項目が HIDDEN[\"{platform}\"] にあります")
    found = tested(paths)
    for path in paths:
        if path not in found and path not in UNTESTED:
            problems.append(f"{path}: core/Tests に値を変えて動きを確かめるテストがありません(確かめられないなら UNTESTED に理由を書く)")
        elif path in found and path in UNTESTED:
            problems.append(f"{path}: core/Tests にテストがあるので，UNTESTED から外してください")
    for path in sorted(set(UNTESTED) - set(paths)):
        problems.append(f"{path}: 設定に無い項目が UNTESTED にあります")
    return problems


def main() -> int:
    problems = check()
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
