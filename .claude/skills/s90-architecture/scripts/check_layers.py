"""core/Sources の Swift ファイルの import が，層の依存の向きに従っているかを確かめる．

使い方: python3 -I .claude/skills/s90-architecture/scripts/check_layers.py [リポジトリのルート]
違反があれば一覧を出し，終了コード 1 で終わる．core/Sources がまだ無いときは何もしない．

許す import は ALLOWED に書く．層を足したら ALLOWED と docs/dev/ARCHITECTURE.md を一緒に変える．
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# 各モジュールが import してよい，このリポジトリのモジュールと外部のモジュール
ALLOWED: dict[str, set[str]] = {
    "S90Domain": {"Foundation"},
    "S90Application": {"Foundation", "S90Domain"},
    "S90Engine": {
        "Foundation",
        "S90Domain",
        "S90Application",
        "KanaKanjiConverterModule",
        "KanaKanjiConverterModuleWithDefaultDictionary",
        "SwiftUtils",
        # Zenzai のモデルのハッシュを確かめるため(OS の標準のライブラリ)
        "CryptoKit",
    },
    # Vision と CoreGraphics は手書きの認識(端末の中だけ．VisionHandwritingRecognizer)に使う
    "S90Persistence": {"Foundation", "S90Domain", "S90Application", "CoreGraphics", "Vision"},
    "S90IPC": {"Foundation", "S90Domain", "S90Application"},
    "s90-playground": {"Foundation", "S90Domain", "S90Application", "S90Engine", "S90Persistence"},
    "s90-engine-host": {
        "Foundation",
        "S90Domain",
        "S90Application",
        "S90Engine",
        "S90Persistence",
        "S90IPC",
    },
}

IMPORT_PATTERN = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:\w+\s+)?([A-Za-z_][\w.]*)")
# OS と標準の基盤．どのモジュールでも条件付きで使うことがあるので検査しない
ALWAYS_ALLOWED = {"Swift", "_Concurrency", "Dispatch", "os", "Synchronization"}


def check(root: Path) -> list[str]:
    sources = root / "core" / "Sources"
    if not sources.is_dir():
        return []
    violations: list[str] = []
    for module_dir in sorted(p for p in sources.iterdir() if p.is_dir()):
        module = module_dir.name
        allowed = ALLOWED.get(module)
        if allowed is None:
            violations.append(f"{module}: ALLOWED に無いモジュールです．層を決めて追記してください")
            continue
        for file in sorted(module_dir.rglob("*.swift")):
            for number, line in enumerate(file.read_text(encoding="utf-8").splitlines(), start=1):
                match = IMPORT_PATTERN.match(line)
                if not match:
                    continue
                imported = match.group(1).split(".")[0]
                if imported in ALWAYS_ALLOWED or imported in allowed:
                    continue
                violations.append(f"{file.relative_to(root)}:{number}: {module} から {imported} は import できません")
    return violations


def main(argv: list[str]) -> int:
    root = Path(argv[1]).resolve() if len(argv) > 1 else Path(__file__).resolve().parents[4]
    violations = check(root)
    for v in violations:
        print(v)
    if violations:
        return 1
    print("ok: 層の依存の向きに違反はありません")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
