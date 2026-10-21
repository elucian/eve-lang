"""The tracking file of a test suite: test/<suite>/<suite>.json (levels 1 to 7, smoke, bytecode, scaffold).

One JSON file per suite replaces the old `status.json` and the generated list in `readme.md`. Shape
(checked by spec/schema/tests.schema.json):

    {"suite": "level1", "kind": "level", "title": "...",
     "tests": [{"id": "a01", "name": "a01_driver", "title": "...", "features": ["F-LNG-01"],
                "status": "PASS", "runs": 233, "failures": 1, "checks": 0, "last": "2026-10-20 16:45",
                "mtime": 1792003006, "reason": ""}, ...]}

`features` is the only link from a test to the rest of the project: ids of spec/features/*.json, written
by hand (the runner keeps them). `title` is the first comment line of the test. One test per line so a
diff shows one line per test that changed. runtest.py writes the file after every run; the manual
generator (generator/) reads it.

@eve-module testtrack
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DIR = os.path.join(ROOT, "test")
KINDS = {"smoke": "special", "bytecode": "special", "scaffold": "special"}
TITLES = {
    "smoke": "Smoke tests: the tools of the machine, one feature each",
    "bytecode": "Bytecode machine: small programs for each group of instructions, run on the bytecode engine",
    "scaffold": "Scaffold: the commands project init and project new on real folders",
}
FIELDS = ("id", "name", "title", "features", "status", "runs", "failures", "checks", "last", "mtime", "reason")
_ID = re.compile(r"\b[DQ]-\d+[a-z]?\b")


def path(suite):
    return os.path.join(TEST_DIR, suite, suite + ".json")


def clean_title(title):
    """A title never names a decision: `(D-094)` and `D-094, D-095` are dropped."""
    def only_ids(m):
        inner = m.group(1)
        rest = re.sub(_ID.pattern + r"|\b(?:earlier|see|and|to|from|since)\b|[\s,;:.\-/]", "", inner)
        return "" if _ID.search(inner) and not rest else m.group(0)

    title = re.sub(r"\s*\(([^()]*)\)", only_ids, title)
    title = re.sub(r"[,;]?\s*" + _ID.pattern, "", title)
    return re.sub(r"\s+([,.;:])", r"\1", title).strip()


def load(suite):
    p = path(suite)
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)
    return {"suite": suite, "kind": KINDS.get(suite, "level"), "title": TITLES.get(suite, suite), "tests": []}


def dumps(doc):
    head = {k: v for k, v in doc.items() if k != "tests"}
    text = json.dumps(head, indent=1, ensure_ascii=False)
    rows = ",\n".join("  " + json.dumps(t, ensure_ascii=False) for t in doc["tests"])
    return text[:-2] + ',\n "tests": [\n' + rows + "\n ]\n}\n"


def save(doc):
    """Write the file when its text changed (a run that changes nothing leaves the file alone)."""
    p = path(doc["suite"])
    text = dumps(doc)
    if os.path.isfile(p):
        with open(p, encoding="utf-8", newline="") as f:
            if f.read() == text:
                return False
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return True


def natural(name):
    m = re.match(r"([a-z]+)(\d+)(.*)", name)
    return (m.group(1), int(m.group(2)), m.group(3)) if m else (name, 0, "")


def test_id(name):
    head = name.split("_")[0]
    return head if re.fullmatch(r"[a-z]\d+", head) else name


def sync(doc, found):
    """Make the tests of `doc` follow the files: `found` is {name: (title, mtime)}. A new test is added as NEW,
    a deleted one disappears, the title is read again only when the file changed. -> {name: entry}."""
    old = {t["name"]: t for t in doc.get("tests", [])}
    state = {}
    for name, (title, mtime) in found.items():
        t = old.get(name) or {"id": test_id(name), "name": name, "title": "", "features": [], "status": "NEW",
                              "runs": 0, "failures": 0, "checks": 0, "last": "-", "mtime": 0, "reason": ""}
        if t.get("mtime") != mtime or not t.get("title"):
            t["mtime"] = mtime
            t["title"] = clean_title(title())
        state[name] = t
    doc["tests"] = [{k: state[n].get(k, "" if k in ("title", "reason", "last") else 0) for k in FIELDS}
                    for n in sorted(state, key=natural)]
    return {t["name"]: t for t in doc["tests"]}


def record(entry, verdict, checks, reason, now):
    entry["status"] = verdict
    entry["checks"] = checks
    entry["reason"] = reason
    entry["last"] = now
    if verdict != "SKIP":
        entry["runs"] += 1
    if verdict in ("FAIL", "ERROR"):
        entry["failures"] += 1


def summary(doc):
    """-> {"tests": n, "PASS": n, ...} for a suite."""
    out = {"tests": len(doc["tests"])}
    for t in doc["tests"]:
        out[t["status"]] = out.get(t["status"], 0) + 1
    return out
