"""design/tokens/tokens.json の参照(「{size.space.md}」の形の $value)を，参照先の値に置き換える．

生成の道具(generate_swift.py・generate_rust.py)が読む．参照先がさらに参照なら，たどって値にする．
参照先が無いときと，参照が輪になっているときは ValueError にする
"""

from __future__ import annotations

import copy
import re

REFERENCE = re.compile(r"^\{([a-z0-9-]+(?:\.[a-z0-9-]+)+)\}$")


def resolve(tokens: dict) -> dict:
    """参照を値に置き換えた写し．元の辞書は変えない"""
    resolved = copy.deepcopy(tokens)

    def lookup(path: str, seen: tuple[str, ...]) -> object:
        if path in seen:
            raise ValueError(f"参照が輪になっています: {' → '.join(seen + (path,))}")
        node: object = tokens
        for part in path.split("."):
            if not isinstance(node, dict) or part not in node:
                raise ValueError(f"参照先がありません: {{{path}}}")
            node = node[part]
        if not isinstance(node, dict) or "$value" not in node:
            raise ValueError(f"参照先が値ではありません: {{{path}}}")
        return value_of(node["$value"], seen + (path,))

    def value_of(value: object, seen: tuple[str, ...]) -> object:
        if isinstance(value, str):
            match = REFERENCE.match(value)
            if match:
                return lookup(match.group(1), seen)
        return value

    def walk(node: object) -> None:
        if not isinstance(node, dict):
            return
        for key, child in node.items():
            if key == "$value":
                node[key] = value_of(child, ())
            else:
                walk(child)

    walk(resolved)
    return resolved
