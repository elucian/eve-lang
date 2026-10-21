"""The sources of the generator: the features of the spec, the tracking files of the tests, the benchmark history.

Everything is read from files (JSON and Markdown) and nothing else: the generator knows no other part of the
repository. A feature is in spec/features/<level>.json and its prose in spec/features/<level>/<id>.md; a test
suite is test/<suite>/<suite>.json; the benchmarks are in test/bmark/history.json.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEVEL_FILES = ["level%d" % n for n in range(1, 8)] + ["all"]
SPECIAL = ["smoke", "bytecode", "scaffold"]
STAGES = ("validated", "drafted", "planned")
STAGE_OF = {"done": "validated", "partial": "drafted", "open": "planned"}
EOL = "\n"


def jload(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def read_text(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read().replace("\r\n", "\n")


def write_text(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def slug(heading):
    """The anchor of a Markdown heading, as GitHub makes it."""
    h = heading.strip().lower().replace("`", "")
    h = re.sub(r"[^\w\s-]", "", h, flags=re.U)
    return re.sub(r"\s", "-", h)


def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


def feature_key(code):
    m = re.match(r"F-([A-Z]+)-(\d+)", code)
    return (m.group(1), int(m.group(2))) if m else (code, 0)


# ---------------------------------------------------------------- features

def load_levels(root=ROOT):
    """-> [level dict] in order level1 .. level7, all; each feature gets `body` (the Markdown of its file,
    without the first heading), `stage` (validated, drafted, planned; None for dropped) and `level` (the id of the level)."""
    out = []
    for name in LEVEL_FILES:
        p = root / "spec" / "features" / (name + ".json")
        if not p.is_file():
            continue
        lv = jload(p)
        for f in lv["features"]:
            doc = root / "spec" / "features" / f["doc"]
            text = read_text(doc) if doc.is_file() else ""
            f["body"] = re.sub(r"\A# [^\n]*\n+", "", text).strip()
            f["stage"] = STAGE_OF.get(f["status"])
            f["level"] = lv["id"]
        out.append(lv)
    return out


def all_features(levels):
    return [f for lv in levels for f in lv["features"]]


def level_label(lv):
    return "All levels" if lv["id"] == "all" else "Level %d" % lv["level"]


# ---------------------------------------------------------------- tests

def load_suites(root=ROOT):
    """-> [suite dict] for every test/<suite>/<suite>.json: levels first, then the special suites."""
    out = []
    for name in [n for n in LEVEL_FILES if n != "all"] + SPECIAL:
        p = root / "test" / name / (name + ".json")
        if p.is_file():
            out.append(jload(p))
    return out


def suite_label(suite):
    return "Level " + suite["suite"][5:] if suite["suite"].startswith("level") else suite["suite"].capitalize()


def test_file(root, suite, name):
    """The source file of a test: test/<suite>/<name>.eve or the primary aspect of a project test."""
    for p in (root / "test" / suite / (name + ".eve"), root / "test" / suite / name / (name + ".eve")):
        if p.is_file():
            return p
    for p in (root / "test" / suite).glob("*/" + name + ".eve"):     # a variation of a project test (b01_test1)
        return p
    return None


# ---------------------------------------------------------------- benchmarks

def bench_runs(root=ROOT):
    p = root / "test" / "bmark" / "history.json"
    if not p.is_file():
        return []
    return [r for r in jload(p) if r.get("build") == "ReleaseSafe"]


def bench_descriptions(root=ROOT):
    """{benchmark: text of its `** perf:` line}."""
    out = {}
    for f in (root / "test" / "bmark").glob("*.eve"):
        for line in read_text(f).split("\n"):
            m = re.match(r"\s*\*\*\s*perf:\s*(.*)", line)
            if m:
                out[f.stem] = m.group(1).strip()
                break
    return out
