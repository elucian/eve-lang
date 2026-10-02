#!/usr/bin/env python3
"""speccheck.py - validate the JSON data files of the Eve specification.

Usage:
    python script/speccheck.py            check every spec/**/*.json (not spec/schema)
    python script/speccheck.py -v         also list each file checked

Checks (standard library only):
  1. the file is valid JSON and validates against the schema named in "$schema"
     (a small subset of JSON Schema: type, enum, required, properties, items);
  2. every item "id" is unique inside its file;
  3. every item "ref" ("path.md#anchor") points to an existing file and an existing
     "#"/"##"/"###"... heading of that file in spec/;
  4. every item "tutorial" URL (".../<page>.html#id") points to an existing id="..." in
     tutorial/<page>.html (skipped when the tutorial junction is missing).

Exit code 0 when everything passes, 1 otherwise.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "spec"
TUTORIAL = ROOT / "tutorial"

_TYPES = {"string": str, "integer": int, "boolean": bool, "array": list, "object": dict, "null": type(None)}


def type_ok(value, name):
    if name == "integer" and isinstance(value, bool):
        return False
    return isinstance(value, _TYPES[name])


def validate(value, schema, path, errors):
    t = schema.get("type")
    if t is not None:
        names = t if isinstance(t, list) else [t]
        if not any(type_ok(value, n) for n in names):
            errors.append(f"{path}: expected {t}, got {type(value).__name__}")
            return
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{path}: {value!r} not in {schema['enum']}")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: missing key '{key}'")
        for key, sub in schema.get("properties", {}).items():
            if key in value:
                validate(value[key], sub, f"{path}.{key}", errors)
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            validate(item, schema["items"], f"{path}[{i}]", errors)


def slug(heading):
    """GitHub-style anchor of a Markdown heading."""
    s = re.sub(r"`", "", heading.strip().lower())
    s = re.sub(r"[^\w\s-]", "", s)
    return re.sub(r"\s", "-", s)


_anchor_cache = {}


def anchors(md_path):
    if md_path not in _anchor_cache:
        found = set()
        in_fence = False
        for line in md_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("```"):
                in_fence = not in_fence
            elif not in_fence:
                m = re.match(r"#{1,6}\s+(.*)", line)
                if m:
                    found.add(slug(m.group(1)))
        _anchor_cache[md_path] = found
    return _anchor_cache[md_path]


_id_cache = {}


def html_ids(page):
    if page not in _id_cache:
        _id_cache[page] = set(re.findall(r'\bid="([^"]+)"', page.read_text(encoding="utf-8")))
    return _id_cache[page]


def check_file(path, verbose):
    errors = []
    rel = path.relative_to(ROOT).as_posix()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as e:
        return [f"{rel}: invalid JSON: {e}"]
    schema_ref = data.get("$schema")
    if schema_ref and not schema_ref.startswith("http"):
        schema_path = (path.parent / schema_ref).resolve()
        if not schema_path.exists():
            errors.append(f"{rel}: schema not found: {schema_ref}")
        else:
            validate(data, json.loads(schema_path.read_text(encoding="utf-8")), "$", errors)
    else:
        errors.append(f"{rel}: no local \"$schema\"")
    seen = set()
    for i, item in enumerate(data.get("items", [])):
        where = f"{rel} items[{i}] ({item.get('id', '?')})"
        iid = item.get("id")
        if iid in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(iid)
        ref = item.get("ref")
        if ref:
            target, _, anchor = ref.partition("#")
            md = SPEC / target
            if not md.exists():
                errors.append(f"{where}: ref file not found: {ref}")
            elif anchor and anchor not in anchors(md):
                errors.append(f"{where}: ref anchor not found: {ref}")
        url = item.get("tutorial")
        if url and TUTORIAL.exists():
            m = re.search(r"/([\w-]+)\.html#([\w-]+)$", url)
            if not m:
                errors.append(f"{where}: tutorial URL needs .html#id: {url}")
            else:
                page = TUTORIAL / (m.group(1) + ".html")
                if not page.exists():
                    errors.append(f"{where}: tutorial page not found: {url}")
                elif m.group(2) not in html_ids(page):
                    errors.append(f"{where}: tutorial id not found: {url}")
    if verbose:
        print(f"  {rel}: {len(data.get('items', []))} items, {len(errors)} problem(s)")
    return errors


def main():
    verbose = "-v" in sys.argv
    files = sorted(p for p in SPEC.rglob("*.json") if "schema" not in p.relative_to(SPEC).parts)
    errors = []
    for f in files:
        errors += check_file(f, verbose)
    for e in errors:
        print("!", e)
    print(f"speccheck: {len(files)} file(s), {len(errors)} problem(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
