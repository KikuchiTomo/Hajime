#!/usr/bin/env python3
"""開発版(Hajime Debug)の設定の画面を実際に操作し，すべての項目が使えるかを確かめる．手で動かす道具で，CI では動かさない．

全ページのスイッチ・選択肢・ステッパー・スライダーを System Events で操作し，次を確かめて表にする．
- 操作すると設定のファイル(settings.json)の項目が 1 つ変わる
- ステッパーとスライダーは範囲の端(protocol/settings-catalog.json の ranges)で止まる
- 値を変えると，ほかの部品が使える・使えないに切り替わる(連動)．Windows の画面の条件(pages.rs の enabled_when)と比べる
- 「既定に戻す」で元の値に戻る．最後に「すべての設定を既定に戻す」で既定に戻る
試した値はそのつど元に戻す．

使い方(apps/macos で xcodegen generate のあと，Debug の構成でビルドしておく):
    python3 -I tools/macos/check_settings_ui.py [--pages 入力,変換] [--report 表.md]

開発版の設定のフォルダは，ほかの開発版とも共有する．始める前に丸ごと控えを取り，終わったら元に戻す(無かったなら消す)．
開発版がすでに動いていれば，ほかの人が使っているかもしれないので止める．本番(men.haji.inputmethod.Hajime)には触らない．
System Events の操作には「アクセシビリティ」の許可が要る．
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HELPER = Path(__file__).with_name("settings_ui.applescript")
CATALOG = ROOT / "protocol/settings-catalog.json"
WINDOWS_PAGES = ROOT / "apps/windows/crates/settings/src/pages.rs"
DEFAULT_APP = ROOT / "apps/macos/build/Build/Products/Debug/Hajime Debug.app"
PROCESS = "Hajime Debug"
BUNDLE_ID = "men.haji.inputmethod.debug"
SETTINGS_DIR = Path.home() / f"Library/Containers/{BUNDLE_ID}/Data/Library/Application Support/{BUNDLE_ID}"
SETTINGS_FILE = SETTINGS_DIR / "settings.json"
# 同期の設定(この Mac だけのもの)．同期の記録(ledger)は設定を変えるたびに時刻が変わるので比べない
SYNC_FILE = SETTINGS_DIR / "sync-state.json"
SYNC_PREFIX = "syncState"
SYNC_MODEL = ROOT / "core/Sources/HajimeDomain/Sync/SyncModel.swift"
# 設定の値を持たない部品(一覧に足す行の下書き)．ページの名前・部品の名前と理由
VIEW_ONLY = {
    ("英語と日本語", "前"): "決まりを足す前の下書き",
    ("英語と日本語", "結果"): "決まりを足す前の下書き",
    ("除外設定", "動作"): "アプリを足す前の下書き",
}
RESTORE_ALL = ("バックアップ", "すべての設定を既定に戻す")
# 範囲の名前が項目の名前と違うもの
RANGE_NAMES = {"listCandidatesPerPage": "candidatesPerPage", "branchCandidatesPerPage": "candidatesPerPage"}
STEP_NAMES = {"reviewCorrectionTimeout": "correctionTimeoutStep", "lateCorrectionTimeout": "correctionTimeoutStep",
              "associationLimit": "associationLimitStep", "paletteCellSize": "paletteCellSizeStep"}
SECONDS = {"liveConversionDelay", "correctionDelay", "reviewCorrectionTimeout", "lateCorrectionTimeout", "modeIndicatorDuration"}
ROLE_NAMES = {"AXCheckBox": "スイッチ", "AXPopUpButton": "選択肢", "AXIncrementor": "ステッパー", "AXSlider": "スライダー", "AXButton": "ボタン"}


class UIError(Exception):
    pass


# 操作する開発版のプロセスの番号．ほかの人が同時に開発版を動かしても，そちらの窓を操作しない
TARGET_PID: int | None = None


def ui(*arguments: str, timeout: float = 120) -> str:
    environment = os.environ | ({"HAJIME_UI_PID": str(TARGET_PID)} if TARGET_PID else {})
    for attempt in (1, 2):
        try:
            result = subprocess.run(["osascript", str(HELPER), *arguments], capture_output=True, text=True, timeout=timeout, env=environment)
        except subprocess.TimeoutExpired:
            raise UIError(f"System Events の操作({arguments[0]})が {timeout:.0f} 秒で終わらない") from None
        if result.returncode == 0:
            return result.stdout.rstrip("\n")
        # 窓や部品を引く途中で画面が描き直されると，参照が一時的に使えなくなる(-1728・-1719)．部品を探す段階の誤りなので 1 回だけやり直す
        if attempt == 1 and ("(-1728)" in result.stderr or "(-1719)" in result.stderr):
            time.sleep(1)
            continue
        raise UIError(result.stderr.strip())
    raise UIError("System Events の操作に失敗した")


@dataclass(frozen=True)
class Control:
    group: int
    role: str
    name: str
    occurrence: int
    enabled: bool
    value: str
    restorable: bool

    @property
    def key(self) -> tuple[int, str, str, int]:
        return (self.group, self.role, self.name, self.occurrence)

    def act(self, operation: str, extra: str = "") -> str:
        arguments = [str(self.group), self.role, self.name, str(self.occurrence), operation]
        # 何段も動かすときは 1 段ごとに部品を探し直すので，段の数に合わせて待つ
        steps = int(extra) if operation in ("increment", "decrement") and extra else 1
        return ui("act", *arguments, *([extra] if extra else []), timeout=60 + 10 * steps)


def controls(detailed: bool = True) -> list[Control]:
    """開いているページの部品．detailed でなければ値と「既定に戻す」を読まない(使えるかを見るだけのとき)"""
    found = []
    for line in ui("controls" if detailed else "states").splitlines():
        group, role, name, occurrence, enabled, value, restorable = line.split("\t")
        found.append(Control(int(group), role, name, int(occurrence), enabled == "true", value, restorable == "1"))
    return found


def without_digits(name: str) -> str:
    """部品の名前から今の値(数字)を除いたもの(「候補の文字サイズ: 15」→「候補の文字サイズ: 」)"""
    return re.sub(r"[0-9.]", "", name)


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def default_scopes() -> dict[str, str]:
    """同期のまとまりごとの既定の範囲(SyncGroup.defaultScope)"""
    text = SYNC_MODEL.read_text(encoding="utf-8")
    block = text[text.index("var defaultScope"):]
    block = block[:block.index("\n    }\n")]
    scopes = {}
    for groups, scope in re.findall(r"case ([.\w, ]+): \.(\w+)", block):
        for group in re.findall(r"\.(\w+)", groups):
            scopes[group] = scope
    return scopes


DEFAULT_SCOPES = default_scopes()


def read_settings() -> dict:
    """設定のファイルと，同期の設定(syncState．記録を除く)．
    同期の範囲は，書いていないまとまりを既定の範囲で埋める(既定の値を書いたときと書いていないときを同じに扱う)"""
    settings = read_json(SETTINGS_FILE)
    sync = read_json(SYNC_FILE)
    sync.pop("ledger", None)
    if settings and sync:
        sync["scopes"] = DEFAULT_SCOPES | sync.get("scopes", {})
        settings[SYNC_PREFIX] = sync
    return settings


def flatten(value: object, prefix: str = "") -> dict[str, object]:
    """入れ子の値を「correction.english」の道筋ごとにする．一覧はまとめて 1 つの値にする"""
    if isinstance(value, dict):
        flat: dict[str, object] = {}
        for key, inner in value.items():
            flat.update(flatten(inner, f"{prefix}{key}."))
        return flat
    return {prefix.rstrip("."): value}


def changed(before: dict, after: dict) -> dict[str, tuple[object, object]]:
    a, b = flatten(before), flatten(after)
    return {key: (a.get(key), b.get(key)) for key in sorted(set(a) | set(b)) if a.get(key) != b.get(key)}


def settle(before: dict, wait: float = 3.0, quiet: float = 0.5) -> dict:
    """設定のファイルが書き換わるのを少し待つ．書き換わったら，quiet 秒変わらなくなるまで待つ．書き換わらなければそのまま返す"""
    deadline = time.monotonic() + wait
    while True:
        after = read_settings()
        if after != before:
            while True:
                time.sleep(quiet)
                latest = read_settings()
                if latest == after:
                    return after
                after = latest
        if time.monotonic() > deadline:
            return after
        time.sleep(0.1)


def same(a: object, b: object) -> bool:
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return math.isclose(a, b, abs_tol=1e-6)
    return a == b


@dataclass
class Row:
    page: str
    control: Control
    fields: list[str] = field(default_factory=list)
    values: list[str] = field(default_factory=list)
    range_check: str = ""
    restore: str = ""
    links: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    # 操作できず確かめなかった理由(フォルダを選ばないと使えないなど)
    unverified: str = ""

    @property
    def result(self) -> str:
        return "NG" if self.problems else "未確認" if self.unverified else "OK"


def windows_conditions() -> dict[str, list[str]]:
    """Windows の画面で，項目を使えるようにする条件(pages.rs の enabled_when)．項目の道筋 → 「親=値」の並び(すべて満たすと使える)"""
    text = WINDOWS_PAGES.read_text(encoding="utf-8").split("#[cfg(test)]")[0]
    # 名前の付いた条件(const CORRECTS_JAPANESE: Condition = ...)は中身に置き換える
    named = dict(re.findall(r"const (\w+): Condition = (.*?);", text, re.DOTALL))
    conditions = {}
    # 行ごとに分けて読む(次の行の条件を拾わない)
    for match in re.finditer(r'Row::\w+\(\s*[\w:]+,\s*"([\w.]+)"(?:(?!Row::)[^;])*?\.enabled_when\(((?:[^()]|\([^()]*\))*)\)', text, re.DOTALL):
        path, argument = match.groups()
        argument = named.get(argument.strip(), argument)
        conditions[path] = [
            {"Is": f"{parent}={value}", "IsNot": f"{parent}≠{value}", "On": f"{parent}=true"}[kind]
            for kind, parent, value in re.findall(r'\b(Is|IsNot|On)\("([\w.]+)"(?:,\s*"(\w+)")?\)', argument)
        ]
    return conditions


class Checker:
    def __init__(self, catalog: dict, only: set[str] | None = None) -> None:
        self.catalog = catalog
        # 確かめる部品の名前(数字を除いたもの)．None ならページのすべての部品
        self.only = only
        self.rows: list[Row] = []
        # 項目ごとに，使えなくした親の値(macOS で見たもの)
        self.disabled_by: dict[str, set[str]] = {}
        self.field_of: dict[tuple[str, tuple], str] = {}
        # 既定では使えず，まだ確かめていない部品と，親の項目を変えて使えるようにして確かめた部品
        self.waiting: list[Row] = []
        self.tested_later: set[tuple[str, tuple]] = set()

    def finish(self) -> None:
        """既定では使えなかった部品のうち，親の項目を変えても使えるようにならなかったものを NG にする"""
        for row in self.waiting:
            if (row.page, row.control.key) in self.tested_later:
                self.rows.remove(row)
            else:
                row.unverified = "既定では使えず，ページのほかの部品を変えても使えるようにならない"

    def check_page(self, page: str) -> None:
        ui("select", page)
        time.sleep(0.5)
        baseline = controls()
        for control in baseline:
            if control.role in ROLE_NAMES and (self.only is None or without_digits(control.name) in self.only):
                wait_alone()
                self.check(page, control, baseline)

    def check(self, page: str, control: Control, baseline: list[Control], depth: int = 0) -> None:
        if not control.enabled and (page, control.key) in self.tested_later:
            return
        if depth:
            self.tested_later.add((page, control.key))
        row = Row(page, control)
        self.rows.append(row)
        if (page, control.name) in VIEW_ONLY and control.occurrence == 1:
            row.restore = "-"
            row.values.append(f"設定の値ではない({VIEW_ONLY[(page, control.name)]})")
            return
        if not control.enabled:
            # 既定では使えない部品は，親の項目を変えて使えるようになったときに確かめる(links)．最後まで確かめられなければ NG
            row.restore = "-"
            self.waiting.append(row)
            return
        before = read_settings()
        try:
            if control.role == "AXCheckBox":
                self.check_toggle(row, before, baseline, depth)
            elif control.role == "AXPopUpButton":
                self.check_choice(row, before, baseline, depth)
            else:
                self.check_range(row, before)
        except UIError as error:
            row.problems.append(f"操作できない: {error}")
        after = settle(before, wait=0.5)
        if diff := changed(before, after):
            row.problems.append(f"元に戻らない: {', '.join(diff)}")

    def field_change(self, row: Row, before: dict, after: dict) -> str | None:
        diff = changed(before, after)
        if not diff:
            row.problems.append("設定のファイルが変わらない")
            return None
        if len(diff) > 1:
            row.problems.append(f"複数の項目が変わる: {', '.join(diff)}")
        path = next(iter(diff))
        if path not in row.fields:
            row.fields.append(path)
        return path

    def links(self, row: Row, baseline: list[Control], label: str, depth: int) -> None:
        """値を変えたあとに使える・使えないが変わった部品を記録し，使えるようになった部品はその状態で確かめる"""
        now = {control.key: control for control in controls(detailed=False)}
        if depth == 0 and any(now.get(control.key) and now[control.key].enabled and not control.enabled for control in baseline):
            now = {control.key: control for control in controls()}
        for control in baseline:
            current = now.get(control.key)
            if current is None or current.enabled == control.enabled or current.key == row.control.key:
                continue
            row.links.append(f"{label} → {control.name}は{'使える' if current.enabled else '使えない'}")
            path = self.field_of.get((row.page, control.key))
            if not current.enabled and path:
                self.disabled_by.setdefault(path, set()).add(label)
            if current.enabled and depth == 0:
                # 既定では使えない部品(英字入力のライブ変換など)は，使えるようになったここで確かめる
                self.check(row.page, current, list(now.values()), depth + 1)
                self.rows[-1].links.append(f"({label} のとき)")

    def restore(self, row: Row, before: dict) -> None:
        if any(path.startswith(SYNC_PREFIX + ".") for path in row.fields):
            # 同期の範囲は設定の項目ではないので「既定に戻す」は無い．呼び出し側で元の値に戻す
            row.restore = "対象外"
            return
        state = row.control.act("restore")
        after = settle(before)
        if state == "none":
            row.restore = "ボタンなし"
            row.problems.append("既定から変えても「既定に戻す」が出ない")
        elif changed(before, after):
            row.restore = "戻らない"
            row.problems.append("「既定に戻す」で元の値に戻らない")
        else:
            row.restore = "OK"

    def check_toggle(self, row: Row, before: dict, baseline: list[Control], depth: int) -> None:
        row.control.act("click")
        after = settle(before)
        path = self.field_change(row, before, after)
        if path:
            self.field_of[(row.page, row.control.key)] = path
            row.values.append(f"{flatten(before).get(path)} → {flatten(after).get(path)}")
            self.links(row, baseline, f"{path}={json.dumps(flatten(after).get(path))}", depth)
        self.restore(row, before)
        if row.restore in ("対象外", "ボタンなし"):
            row.control.act("click")
            settle(after)

    def check_choice(self, row: Row, before: dict, baseline: list[Control], depth: int) -> None:
        names = row.control.act("menu").splitlines()
        original = row.control.value
        path = None
        for name in names:
            if name == original:
                continue
            row.control.act("choose", name)
            after = settle(before)
            path = self.field_change(row, before, after) or path
            if path:
                self.field_of[(row.page, row.control.key)] = path
                value = flatten(after).get(path)
                row.values.append(f"{name}={value}")
                self.links(row, baseline, f"{path}={value}", depth)
            # 選ぶたびに既定に戻し，次の選択肢をいつも既定の状態から確かめる
            self.restore(row, before)
            if row.restore != "OK":
                row.control.act("choose", original)
                settle(after)
        if len(names) < 2:
            row.problems.append("選択肢が 1 つしかない")

    def check_range(self, row: Row, before: dict) -> None:
        row.control.act("increment")
        after = settle(before)
        if not changed(before, after):
            # 上の端にあるときは下げてみる
            row.control.act("decrement")
            after = settle(before)
        path = self.field_change(row, before, after)
        if not path:
            return
        self.field_of[(row.page, row.control.key)] = path
        name = path.split(".")[-1]
        bounds = self.catalog["ranges"].get(RANGE_NAMES.get(name, name))
        step = self.catalog.get(STEP_NAMES.get(name, "secondsStep" if name in SECONDS else ""), 1)
        if not bounds:
            row.problems.append(f"protocol/settings-catalog.json に {name} の範囲が無い")
            self.restore(row, before)
            return
        low, high = bounds
        span = math.ceil((high - low) / step) + 2
        row.control.act("increment", str(span))
        top_settings = settle(after)
        top = flatten(top_settings).get(path)
        row.control.act("decrement", str(span * 2))
        bottom = flatten(settle(top_settings)).get(path)
        row.values.append(f"{bottom}〜{top}")
        # 端は目録の範囲の中でなければならない(少しでも越えた値を保存すると，読み直したときに丸められる)
        if same(top, high) and same(bottom, low) and low <= bottom and top <= high:
            row.range_check = "OK"
        else:
            row.range_check = "NG"
            row.problems.append(f"範囲の端が {bottom}〜{top}(目録は {low}〜{high})")
        # 下の端が既定の値なら「既定に戻す」は出ないので，1 段上げてから確かめる
        if same(bottom, flatten(before).get(path)):
            current = read_settings()
            row.control.act("increment")
            settle(current)
        self.restore(row, before)

    def check_restore_all(self, toggles: list[tuple[str, Control]]) -> Row:
        """スイッチを 2 つ変えてから「すべての設定を既定に戻す」を押し，既定に戻るかを確かめる"""
        page, button = RESTORE_ALL
        row = Row(page, Control(0, "AXButton", button, 1, True, "", False), restore="-")
        defaults = read_settings()
        for toggle_page, control in toggles:
            ui("select", toggle_page)
            control.act("click")
            settle(defaults)
        changed_before = changed(defaults, read_settings())
        ui("select", page)
        ui("press-last")
        after = settle(read_settings())
        if not changed_before:
            row.problems.append("試しに変えた値が保存されない")
        elif left := [path for path in changed(defaults, after) if path in changed_before]:
            row.problems.append(f"既定に戻らない: {', '.join(left)}")
        # 共有の設定のフォルダは既定のままとは限らない．試しに変えた項目のほかに既定に戻った項目は，もとから既定と違っていたもの
        if others := [path for path in changed(defaults, after) if path not in changed_before]:
            row.values.append(f"もとから既定と違っていて既定に戻った項目: {', '.join(others)}")
        row.fields = list(changed_before)
        return row


def report(rows: list[Row], disabled_by: dict[str, set[str]]) -> str:
    conditions = windows_conditions()
    lines = ["| ページ | 部品 | 名前 | 設定の項目 | 試した値 | 範囲 | 既定に戻す | 連動 | Windows の条件 | 結果 |",
             "|---|---|---|---|---|---|---|---|---|---|"]
    for row in rows:
        windows = ", ".join(" かつ ".join(conditions[path]) for path in row.fields if conditions.get(path))
        lines.append("| " + " | ".join([
            row.page, ROLE_NAMES.get(row.control.role, row.control.role), row.control.name, ", ".join(row.fields),
            "<br>".join(row.values), row.range_check, row.restore, "<br>".join(row.links), windows,
            row.result + "".join("<br>" + text for text in [*row.problems, row.unverified] if text),
        ]).replace("\n", " ") + " |")
    # 使えなくなる条件が macOS と Windows で食い違うもの
    mismatches = []
    for path, condition in sorted(conditions.items()):
        observed = disabled_by.get(path)
        if observed is None:
            continue
        # macOS で使えなくした親の項目は，Windows の条件の親の項目のどれか(別のページの親は見ない)
        parents = {re.split(r"[=≠]", part)[0] for part in condition}
        for label in sorted(observed):
            if label.split("=")[0] not in parents:
                mismatches.append(f"- {path}: Windows は {' かつ '.join(condition)} のときだけ使える．macOS では {label} で使えなくなる")
    for path, observed in sorted(disabled_by.items()):
        if path not in conditions:
            mismatches.append(f"- {path}: macOS では {', '.join(sorted(observed))} で使えなくなるが，Windows の画面には条件が無い")
    # スイッチ・選択肢・ステッパー・スライダーでは変えない項目(一覧・テーマの見本・ボタンで変えるもの)
    sys.path.insert(0, str(ROOT / "tools/check"))
    from check_settings_fields import setting_paths

    touched = {path for row in rows for path in row.fields}
    # 設定のファイルで入れ子になる値(keymap.entries など)は，項目の名前で数える
    touched |= {path.split(".")[0] for path in touched}
    others = [path for path in setting_paths() if path not in touched]
    counts = {result: sum(1 for row in rows if row.result == result) for result in ("OK", "NG", "未確認")}
    summary = f"\n{len(rows)} 件: OK {counts['OK']} 件，NG {counts['NG']} 件，未確認 {counts['未確認']} 件\n"
    summary += f"\nこの道具で操作しない項目(一覧やボタンで変えるもの): {', '.join(others)}\n" if others else ""
    return "\n".join(lines) + summary + ("\n連動の条件の食い違い:\n" + "\n".join(mismatches) + "\n" if mismatches else "")


def restore_all_toggles(rows: list[Row], first_page: str) -> list[tuple[str, Control]]:
    """「すべての設定を既定に戻す」を確かめる前に変えるスイッチ 2 つ．確かめたスイッチから選び，足りなければ最初のページから選ぶ"""
    toggles = [(row.page, row.control) for row in rows if row.control.role == "AXCheckBox" and row.result == "OK"][:2]
    if len(toggles) < 2:
        ui("select", first_page)
        toggles = [(first_page, control) for control in controls() if control.role == "AXCheckBox" and control.enabled][:2]
    return toggles


def running() -> bool:
    return subprocess.run(["pgrep", "-x", PROCESS], capture_output=True).returncode == 0


def others_running() -> bool:
    """ほかの開発版が動いているか．設定のフォルダを共有するので，動いているあいだは設定のファイルが書き換わりうる"""
    found = subprocess.run(["pgrep", "-x", PROCESS], capture_output=True, text=True).stdout.split()
    return any(int(pid) != TARGET_PID for pid in found)


def wait_alone(limit: float = 600) -> None:
    """ほかの開発版が終わるまで待つ．limit 秒たっても終わらなければ，そのページを確かめられなかったことにする"""
    deadline = time.monotonic() + limit
    while others_running():
        if time.monotonic() > deadline:
            raise UIError("ほかの開発版が動いていて，設定のファイルが書き換わるおそれがある")
        time.sleep(5)


def main() -> int:
    # 止められたときも，開発版を終わらせて設定のフォルダを戻す(finally を通す)．裏で動かすと SIGINT は無視されるので付け直す
    signal.signal(signal.SIGINT, signal.default_int_handler)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=DEFAULT_APP, help="開発版のアプリ(Debug の構成)")
    parser.add_argument("--pages", help="確かめるページの名前(カンマ区切り)．無ければすべて．途中で止まったときは，止まったページから先だけを指定してやり直せる")
    parser.add_argument("--controls", help="確かめる部品の名前(カンマ区切り)．無ければページのすべての部品．--pages と合わせて 1 つの部品だけをやり直せる")
    parser.add_argument("--report", type=Path, help="結果の表(Markdown)を書くファイル．無ければ標準出力")
    arguments = parser.parse_args()
    binary = arguments.app / "Contents/MacOS" / PROCESS
    if not binary.exists():
        print(f"開発版がありません: {binary}", file=sys.stderr)
        return 2
    if running():
        print(f"{PROCESS} がすでに動いています．ほかの人の作業かもしれないので，止まってから動かしてください", file=sys.stderr)
        return 2
    assert BUNDLE_ID.endswith(".debug") and SETTINGS_DIR.name == BUNDLE_ID
    backup = Path(tempfile.mkdtemp(prefix="hajime-settings-ui-")) / "backup"
    existed = SETTINGS_DIR.exists()
    if existed:
        shutil.copytree(SETTINGS_DIR, backup, symlinks=True)
    process = subprocess.Popen([str(binary), "--open-settings"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    global TARGET_PID
    TARGET_PID = process.pid
    try:
        deadline = time.monotonic() + 180
        while True:
            try:
                pages = ui("pages").splitlines()
                break
            except UIError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(2)
        wanted = arguments.pages.split(",") if arguments.pages else pages
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        checker = Checker(catalog, {without_digits(name) for name in arguments.controls.split(",")} if arguments.controls else None)
        # スイッチを 2 回押して，今のバージョンの形で設定のファイルを書き直させる．ファイルが無いときや，前のバージョンの形
        # (キー設定の表の書き足しなど)のときに，最初に操作した部品で変わったように見えないようにする
        ui("select", pages[0])
        first = next(control for control in controls() if control.role == "AXCheckBox" and control.enabled)
        current = read_settings()
        first.act("click")
        settle(current)
        first.act("click")
        settle(read_settings())

        def write() -> str:
            # 1 ページ終わるごとに書き直し，途中で止まってもそれまでの表を残す
            text = report(checker.rows, checker.disabled_by)
            if arguments.report:
                arguments.report.write_text(text, encoding="utf-8")
            return text

        for page in wanted:
            print(f"{page} を確かめています", file=sys.stderr)
            # 操作が時間内に終わらないなどで確かめられなければ 1 回だけやり直し，それでもだめなら記録して次のページへ進む
            for attempt in (1, 2):
                try:
                    checker.check_page(page)
                    break
                except UIError as error:
                    checker.rows = [row for row in checker.rows if row.page != page]
                    checker.waiting = [row for row in checker.waiting if row.page != page]
                    if attempt == 2:
                        checker.rows.append(Row(page, Control(0, "-", "-", 1, False, "", False), problems=[f"ページを確認できなかった: {error}"]))
            write()
        checker.finish()
        if RESTORE_ALL[0] in wanted:
            try:
                checker.rows.append(checker.check_restore_all(restore_all_toggles(checker.rows, pages[0])))
            except UIError as error:
                page, button = RESTORE_ALL
                checker.rows.append(Row(page, Control(0, "AXButton", button, 1, True, "", False), problems=[f"操作できない: {error}"]))
        text = write()
        if not arguments.report:
            print(text)
        return 0 if all(not row.problems for row in checker.rows) else 1
    finally:
        process.terminate()
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        if SETTINGS_DIR.exists():
            shutil.rmtree(SETTINGS_DIR)
        if existed:
            shutil.copytree(backup, SETTINGS_DIR, symlinks=True)
        shutil.rmtree(backup.parent, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
