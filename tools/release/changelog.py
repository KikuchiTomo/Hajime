"""CHANGELOG.md を読み書きする．

節は「## 未リリース」と「## vX.Y.Z (YYYY-MM-DD)」．新しいバージョンほど上に書く．

使い方:
  python3 -I tools/release/changelog.py check                       形を確かめる(make check)
  python3 -I tools/release/changelog.py section <バージョン>          その節の中身を出す(リリースノート)
  python3 -I tools/release/changelog.py release <バージョン> <日付>   「未リリース」の中身を新しいバージョンの節に移す(bump_version.sh)
  python3 -I tools/release/changelog.py recent <バージョン> <数>      そのバージョンまでの新しい節を JSON で出す(latest.json の notes)
"""

import json
import re
import sys
from pathlib import Path

PATH = Path(__file__).resolve().parents[2] / "CHANGELOG.md"
UNRELEASED = "## 未リリース"
VERSION_HEADING = re.compile(r"^## v(\d+)\.(\d+)\.(\d+) \((\d{4}-\d{2}-\d{2})\)$")
VERSION = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


class ChangelogError(Exception):
    pass


def parse(text):
    """前置き(最初の ## より前)と，節の一覧(見出し・バージョン・日付・中身)に分ける"""
    lines = text.split("\n")
    preamble = []
    sections = []
    for line in lines:
        if line.startswith("## "):
            sections.append({"heading": line, "body": []})
        elif sections:
            sections[-1]["body"].append(line)
        else:
            preamble.append(line)
    for section in sections:
        section["text"] = "\n".join(section.pop("body")).strip()
        match = VERSION_HEADING.match(section["heading"])
        if match:
            section["version"] = tuple(int(part) for part in match.group(1, 2, 3))
            section["date"] = match.group(4)
        elif section["heading"] == UNRELEASED:
            section["version"] = None
        else:
            raise ChangelogError(f"見出しの形が違います(「{UNRELEASED}」か「## vX.Y.Z (YYYY-MM-DD)」): {section['heading']}")
    return "\n".join(preamble), sections


def check(sections):
    if not sections or sections[0]["version"] is not None:
        raise ChangelogError(f"最初の節は「{UNRELEASED}」にしてください")
    if sum(1 for section in sections if section["version"] is None) != 1:
        raise ChangelogError(f"「{UNRELEASED}」は 1 つだけにしてください")
    versions = [section["version"] for section in sections[1:]]
    for newer, older in zip(versions, versions[1:]):
        if newer <= older:
            raise ChangelogError(f"バージョンは新しい順に書いてください: v{format_version(newer)} の次に v{format_version(older)}")
    for section in sections[1:]:
        if not section["text"]:
            raise ChangelogError(f"中身がありません: {section['heading']}")


def parse_version(value):
    match = VERSION.match(value)
    if not match:
        raise ChangelogError(f"バージョンは X.Y.Z で書いてください: {value}")
    return tuple(int(part) for part in match.groups())


def format_version(version):
    return ".".join(str(part) for part in version)


def render(preamble, sections):
    parts = [preamble.rstrip()]
    for section in sections:
        parts.append(section["heading"] + ("\n\n" + section["text"] if section["text"] else ""))
    return "\n\n".join(parts) + "\n"


def find(sections, version):
    for section in sections:
        if section["version"] == version:
            return section
    raise ChangelogError(f"CHANGELOG.md に v{format_version(version)} の節がありません")


def main(arguments):
    command = arguments[0] if arguments else ""
    preamble, sections = parse(PATH.read_text(encoding="utf-8"))
    check(sections)
    if command == "check" and len(arguments) == 1:
        print("ok: CHANGELOG.md の形が合っています")
    elif command == "section" and len(arguments) == 2:
        print(find(sections, parse_version(arguments[1]))["text"])
    elif command == "release" and len(arguments) == 3:
        version = parse_version(arguments[1])
        date = arguments[2]
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
            raise ChangelogError(f"日付は YYYY-MM-DD で書いてください: {date}")
        unreleased = sections[0]
        if not unreleased["text"]:
            raise ChangelogError(f"「{UNRELEASED}」に変更点を書いてからバージョンを上げてください")
        if len(sections) > 1 and version <= sections[1]["version"]:
            raise ChangelogError(f"v{format_version(version)} は前のバージョン(v{format_version(sections[1]['version'])})より新しくしてください")
        released = {"heading": f"## v{format_version(version)} ({date})", "text": unreleased["text"], "version": version}
        sections = [{"heading": UNRELEASED, "text": "", "version": None}, released, *sections[1:]]
        PATH.write_text(render(preamble, sections), encoding="utf-8")
    elif command == "recent" and len(arguments) == 3:
        latest = parse_version(arguments[1])
        limit = int(arguments[2])
        released = [section for section in sections[1:] if section["version"] <= latest][:limit]
        print(json.dumps([{"version": format_version(section["version"]), "date": section["date"], "notes": section["text"]}
                          for section in released], ensure_ascii=False))
    else:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except ChangelogError as error:
        print(f"CHANGELOG.md: {error}", file=sys.stderr)
        sys.exit(1)
