from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "protocol" / "schema.json"
SWIFT_OUT = ROOT / "core" / "Sources" / "S90IPC" / "Generated" / "WireMessages.swift"
RUST_OUT = ROOT / "apps" / "windows" / "crates" / "ipc" / "src" / "generated.rs"

SWIFT_PREFIX = "Wire"

PRIMITIVES_SWIFT = {
    "bool": "Bool",
    "string": "String",
    "u8": "UInt8",
    "u32": "UInt32",
    "i32": "Int32",
    "f64": "Double",
}
PRIMITIVES_RUST = {
    "bool": "bool",
    "string": "String",
    "u8": "u8",
    "u32": "u32",
    "i32": "i32",
    "f64": "f64",
}

class SchemaError(Exception):
    pass


def parse_type(text: str) -> tuple[str, bool, bool, bool]:
    optional = text.endswith("?")
    if optional:
        text = text[:-1]
    is_list = text.startswith("[") and text.endswith("]")
    element_optional = False
    if is_list:
        text = text[1:-1]
        element_optional = text.endswith("?")
        if element_optional:
            text = text[:-1]
    return text, is_list, element_optional, optional


def validate(schema: dict) -> None:
    names = {t["name"] for t in schema["types"]}
    identifier = re.compile(r"^[a-z][A-Za-z0-9]*$")
    for t in schema["types"]:
        if not re.match(r"^[A-Z][A-Za-z0-9]*$", t["name"]):
            raise SchemaError(f"型の名前は PascalCase: {t['name']}")
        kind = t["kind"]
        if kind == "enum":
            for case in t["cases"]:
                if not identifier.match(case):
                    raise SchemaError(f"{t['name']}.{case}: 名前は camelCase")
            continue
        field_lists = [t["fields"]] if kind == "struct" else [c.get("fields", []) for c in t["cases"]]
        if kind == "union":
            for case in t["cases"]:
                if not identifier.match(case["name"]):
                    raise SchemaError(f"{t['name']}.{case['name']}: 名前は camelCase")
        elif kind != "struct":
            raise SchemaError(f"{t['name']}: 知らない kind {kind}")
        for fields in field_lists:
            for field in fields:
                if not identifier.match(field["name"]):
                    raise SchemaError(f"{t['name']}.{field['name']}: 名前は camelCase")
                if kind == "union" and field["name"] == t["tag"]:
                    raise SchemaError(f"{t['name']}.{field['name']}: 種類を表す名前と同じ名前は使えない")
                base = parse_type(field["type"])[0]
                if base not in PRIMITIVES_SWIFT and base not in names:
                    raise SchemaError(f"{t['name']}.{field['name']}: 知らない型 {base}")


def type_kinds(schema: dict) -> dict[str, str]:
    return {t["name"]: t["kind"] for t in schema["types"]}


def has_text(type_text: str, schema: dict) -> bool:
    base = parse_type(type_text)[0]
    return base == "string"


def swift_type(text: str) -> str:
    base, is_list, element_optional, optional = parse_type(text)
    name = PRIMITIVES_SWIFT.get(base, SWIFT_PREFIX + base)
    if is_list:
        name = f"[{name}{'?' if element_optional else ''}]"
    return name + ("?" if optional else "")


def swift_doc(doc: str | None, indent: str) -> list[str]:
    return []


def swift_struct(t: dict) -> list[str]:
    name = SWIFT_PREFIX + t["name"]
    lines = swift_doc(t.get("doc"), "")
    lines.append(f"public struct {name}: Sendable, Equatable, Codable {{")
    for field in t["fields"]:
        lines += swift_doc(field.get("doc"), "    ")
        lines.append(f"    public var {field['name']}: {swift_type(field['type'])}")
    params = []
    for field in t["fields"]:
        default = " = nil" if parse_type(field["type"])[3] else ""
        params.append(f"{field['name']}: {swift_type(field['type'])}{default}")
    lines.append("")
    lines.append(f"    public init({', '.join(params)}) {{")
    for field in t["fields"]:
        lines.append(f"        self.{field['name']} = {field['name']}")
    lines.append("    }")
    lines.append("}")
    return lines


def swift_enum(t: dict) -> list[str]:
    name = SWIFT_PREFIX + t["name"]
    lines = swift_doc(t.get("doc"), "")
    lines.append(f"public enum {name}: String, Sendable, Equatable, Codable, CaseIterable {{")
    for case in t["cases"]:
        lines.append(f"    case {case}")
    lines.append("}")
    return lines


def swift_union(t: dict) -> list[str]:
    name = SWIFT_PREFIX + t["name"]
    tag = t["tag"]
    lines = swift_doc(t.get("doc"), "")
    lines.append(f"public enum {name}: Sendable, Equatable, Codable {{")
    keys: list[str] = [tag]
    for case in t["cases"]:
        lines += swift_doc(case.get("doc"), "    ")
        fields = case.get("fields", [])
        for field in fields:
            if field["name"] not in keys:
                keys.append(field["name"])
        if fields:
            params = ", ".join(f"{f['name']}: {swift_type(f['type'])}" for f in fields)
            lines.append(f"    case {case['name']}({params})")
        else:
            lines.append(f"    case {case['name']}")
    lines.append("")
    lines.append("    private enum CodingKeys: String, CodingKey {")
    lines.append(f"        case {', '.join(keys)}")
    lines.append("    }")
    lines.append("")
    lines.append("    public init(from decoder: any Decoder) throws {")
    lines.append("        let container = try decoder.container(keyedBy: CodingKeys.self)")
    lines.append(f"        let kind = try container.decode(String.self, forKey: .{tag})")
    lines.append("        switch kind {")
    for case in t["cases"]:
        fields = case.get("fields", [])
        lines.append(f'        case "{case["name"]}":')
        if fields:
            args = []
            for f in fields:
                decoded = swift_type(f["type"])
                if parse_type(f["type"])[3]:
                    args.append(f"{f['name']}: container.decodeIfPresent({decoded[:-1]}.self, forKey: .{f['name']})")
                else:
                    args.append(f"{f['name']}: container.decode({decoded}.self, forKey: .{f['name']})")
            lines.append(f"            self = try .{case['name']}({', '.join(args)})")
        else:
            lines.append(f"            self = .{case['name']}")
    lines.append("        default:")
    lines.append(
        f'            throw DecodingError.dataCorruptedError(forKey: .{tag}, in: container, debugDescription: "知らない種類")'
    )
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    public func encode(to encoder: any Encoder) throws {")
    lines.append("        var container = encoder.container(keyedBy: CodingKeys.self)")
    lines.append("        switch self {")
    for case in t["cases"]:
        fields = case.get("fields", [])
        if fields:
            bindings = ", ".join(f"let {f['name']}" for f in fields)
            lines.append(f"        case .{case['name']}({bindings}):")
        else:
            lines.append(f"        case .{case['name']}:")
        lines.append(f'            try container.encode("{case["name"]}", forKey: .{tag})')
        for f in fields:
            method = "encodeIfPresent" if parse_type(f["type"])[3] else "encode"
            lines.append(f"            try container.{method}({f['name']}, forKey: .{f['name']})")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return lines


def swift_redaction(t: dict) -> list[str]:
    name = SWIFT_PREFIX + t["name"]
    lines = [f"extension {name}: CustomStringConvertible, CustomDebugStringConvertible {{"]
    if t["kind"] == "union":
        lines.append("    public var description: String {")
        lines.append("        switch self {")
        for case in t["cases"]:
            lines.append(f'        case .{case["name"]}: "{name}.{case["name"]}"')
        lines.append("        }")
        lines.append("    }")
    elif t["kind"] == "enum":
        lines.append(f'    public var description: String {{ "{name}.\\(rawValue)" }}')
    else:
        lines.append(f'    public var description: String {{ "{name}" }}')
    lines.append("    public var debugDescription: String { description }")
    lines.append("}")
    return lines


def generate_swift(schema: dict) -> str:
    out: list[str] = []
    out.append(f"public enum {SWIFT_PREFIX}Protocol {{")
    out.append(f"    public static let version: UInt32 = {schema['version']}")
    out.append(f"    public static let maximumMessageBytes = {schema['maximumMessageBytes']}")
    out.append("}")
    for t in schema["types"]:
        out.append("")
        if t["kind"] == "struct":
            out += swift_struct(t)
        elif t["kind"] == "enum":
            out += swift_enum(t)
        else:
            out += swift_union(t)
        out.append("")
        out += swift_redaction(t)
    return "\n".join(out) + "\n"


def pascal(name: str) -> str:
    return name[0].upper() + name[1:]


def snake(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


RUST_KEYWORDS = {"type", "move", "ref", "self", "match", "fn", "mod", "use", "loop", "box"}


def rust_field_name(name: str) -> str:
    s = snake(name)
    return f"r#{s}" if s in RUST_KEYWORDS else s


def rust_type(text: str) -> str:
    base, is_list, element_optional, optional = parse_type(text)
    name = PRIMITIVES_RUST.get(base, base)
    if is_list:
        inner = f"Option<{name}>" if element_optional else name
        name = f"Vec<{inner}>"
    return f"Option<{name}>" if optional else name


def rust_doc(doc: str | None, indent: str) -> list[str]:
    return []


def rust_field_lines(fields: list[dict], indent: str, public: bool) -> list[str]:
    lines = []
    for field in fields:
        lines += rust_doc(field.get("doc"), indent)
        if snake(field["name"]) != field["name"] or rust_field_name(field["name"]).startswith("r#"):
            lines.append(f'{indent}#[serde(rename = "{field["name"]}")]')
        if parse_type(field["type"])[3]:
            lines.append(f'{indent}#[serde(default, skip_serializing_if = "Option::is_none")]')
        visibility = "pub " if public else ""
        lines.append(f"{indent}{visibility}{rust_field_name(field['name'])}: {rust_type(field['type'])},")
    return lines


def rust_debug_field(field: dict, schema: dict, accessor: str) -> str:
    if has_text(field["type"], schema):
        return f'.field("{field["name"]}", &REDACTED)'
    return f'.field("{field["name"]}", {accessor})'


def rust_struct(t: dict, schema: dict) -> list[str]:
    lines = rust_doc(t.get("doc"), "")
    lines.append("#[derive(Clone, PartialEq, Serialize, Deserialize)]")
    lines.append(f"pub struct {t['name']} {{")
    lines += rust_field_lines(t["fields"], "    ", public=True)
    lines.append("}")
    lines.append("")
    lines.append(f"impl fmt::Debug for {t['name']} {{")
    lines.append("    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {")
    lines.append(f'        f.debug_struct("{t["name"]}")')
    for field in t["fields"]:
        lines.append("            " + rust_debug_field(field, schema, f"&self.{rust_field_name(field['name'])}"))
    lines.append("            .finish()")
    lines.append("    }")
    lines.append("}")
    return lines


def rust_enum(t: dict) -> list[str]:
    lines = rust_doc(t.get("doc"), "")
    lines.append("#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]")
    lines.append('#[serde(rename_all = "camelCase")]')
    lines.append(f"pub enum {t['name']} {{")
    for case in t["cases"]:
        lines.append(f"    {pascal(case)},")
    lines.append("}")
    return lines


def rust_union(t: dict, schema: dict) -> list[str]:
    lines = rust_doc(t.get("doc"), "")
    lines.append("#[derive(Clone, PartialEq, Serialize, Deserialize)]")
    lines.append(f'#[serde(tag = "{t["tag"]}", rename_all = "camelCase")]')
    lines.append(f"pub enum {t['name']} {{")
    for case in t["cases"]:
        lines += rust_doc(case.get("doc"), "    ")
        fields = case.get("fields", [])
        if fields:
            lines.append(f"    {pascal(case['name'])} {{")
            lines += rust_field_lines(fields, "        ", public=False)
            lines.append("    },")
        else:
            lines.append(f"    {pascal(case['name'])},")
    lines.append("}")
    lines.append("")
    lines.append(f"impl fmt::Debug for {t['name']} {{")
    lines.append("    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {")
    lines.append("        match self {")
    for case in t["cases"]:
        fields = case.get("fields", [])
        variant = f"Self::{pascal(case['name'])}"
        if not fields:
            lines.append(f'            {variant} => f.write_str("{pascal(case["name"])}"),')
            continue
        used = [f for f in fields if not has_text(f["type"], schema)]
        if used:
            bindings = ", ".join(rust_field_name(f["name"]) for f in used)
            lines.append(f"            {variant} {{ {bindings}, .. }} => f")
        else:
            lines.append(f"            {variant} {{ .. }} => f")
        lines.append(f'                .debug_struct("{pascal(case["name"])}")')
        for field in fields:
            lines.append("                " + rust_debug_field(field, schema, rust_field_name(field["name"])))
        lines.append("                .finish(),")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    return lines


def generate_rust(schema: dict) -> str:
    out: list[str] = []
    out.append("use serde::{Deserialize, Serialize};")
    out.append("use std::fmt;")
    out.append("")
    out.append(f"pub const PROTOCOL_VERSION: u32 = {schema['version']};")
    out.append(f"pub const MAXIMUM_MESSAGE_BYTES: usize = {schema['maximumMessageBytes']};")
    out.append("")
    out.append('const REDACTED: &str = "<伏せた>";')
    for t in schema["types"]:
        out.append("")
        if t["kind"] == "struct":
            out += rust_struct(t, schema)
        elif t["kind"] == "enum":
            out += rust_enum(t)
        else:
            out += rust_union(t, schema)
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    check_only = "--check" in argv
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    try:
        validate(schema)
    except SchemaError as error:
        print(f"protocol/schema.json: {error}")
        return 1
    outputs = {SWIFT_OUT: generate_swift(schema), RUST_OUT: generate_rust(schema)}
    stale = []
    for path, text in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == text:
            continue
        if check_only:
            stale.append(path.relative_to(ROOT))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            print(f"作り直した: {path.relative_to(ROOT)}")
    if stale:
        for path in stale:
            print(f"{path}: protocol/schema.json と合っていません．make protocol で作り直してください")
        return 1
    if check_only:
        print("ok: 通信の型は protocol/schema.json と合っています")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
