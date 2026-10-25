""".claude/skills/*/SKILL.md が Agent Skills の決まりを守っているかを確かめる．

skill-creator の quick_validate.py と同じ規則を，PyYAML に頼らずに確かめる(CI で依存を増やさないため)．
frontmatter は「キー: 値」の 1 行ずつの形だけを受け付ける．

使い方: python3 -I tools/check/check_skills.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".claude" / "skills"
ALLOWED_KEYS = {"name", "description", "license", "allowed-tools", "metadata", "compatibility"}
NAME_PATTERN = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MAX_NAME = 64
MAX_DESCRIPTION = 1024
# skill-creator の目安．超えたら references/ に分ける
MAX_BODY_LINES = 500


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    match = re.match(r"^---\n(.*?)\n---\n?(.*)$", text, re.DOTALL)
    if not match:
        raise ValueError("先頭に --- で囲んだ frontmatter がありません")
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if not line.strip():
            continue
        key, sep, value = line.partition(":")
        if not sep:
            raise ValueError(f"frontmatter の行を読めません: {line}")
        fields[key.strip()] = value.strip()
    return fields, match.group(2)


def check_skill(directory: Path) -> list[str]:
    skill_file = directory / "SKILL.md"
    if not skill_file.is_file():
        return [f"{directory.name}: SKILL.md がありません"]
    try:
        fields, body = parse_frontmatter(skill_file.read_text(encoding="utf-8"))
    except ValueError as error:
        return [f"{directory.name}: {error}"]
    problems: list[str] = []
    unknown = set(fields) - ALLOWED_KEYS
    if unknown:
        problems.append(f"{directory.name}: 使えないキー {sorted(unknown)}")
    name = fields.get("name", "")
    if not NAME_PATTERN.match(name) or len(name) > MAX_NAME:
        problems.append(f"{directory.name}: name は {MAX_NAME} 文字以内の kebab-case にしてください")
    if name != directory.name:
        problems.append(f"{directory.name}: name({name})がディレクトリ名と違います")
    description = fields.get("description", "")
    if not description:
        problems.append(f"{directory.name}: description がありません")
    elif len(description) > MAX_DESCRIPTION:
        problems.append(f"{directory.name}: description が {len(description)} 文字です(上限 {MAX_DESCRIPTION})")
    if "<" in description or ">" in description:
        problems.append(f"{directory.name}: description に < と > は使えません")
    lines = body.count("\n") + 1
    if lines > MAX_BODY_LINES:
        problems.append(f"{directory.name}: 本文が {lines} 行です．references/ に分けてください")
    return problems


def main() -> int:
    problems: list[str] = []
    for directory in sorted(p for p in SKILLS.iterdir() if p.is_dir()):
        problems.extend(check_skill(directory))
    for problem in problems:
        print(problem)
    if problems:
        return 1
    print(f"ok: {SKILLS.relative_to(ROOT)} のスキルはすべて決まりを守っています")
    return 0


if __name__ == "__main__":
    sys.exit(main())
