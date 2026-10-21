"""The pages of the manual, made from the spec (features, keywords, operators), the tests (tracking files and
verified examples) and the benchmark history.

A page is one of two kinds:
- a template page (features.md, tests.md, performance.md): made from generator/templates/ when it does not
  exist; afterwards only its `<!-- GEN:name -->` blocks are written again and the hand-written text is kept;
- a generated page (levels/*.md, reference/*.md): written whole, every time.
The pages name no folder, file or identifier of the repository and link to no test or spec page, so the
manual reads the same in a distribution.
"""
import json
import re
from pathlib import Path

import model
from model import table

TEMPLATES = Path(__file__).resolve().parent / "templates"
NOTE = "<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->\n"


def put(text, name, body):
    """Replace the body of the block GEN:name."""
    pat = re.compile(r"<!-- GEN:%s[^>]*-->\n.*?<!-- /GEN:%s -->" % (name, name), re.S)
    if not pat.search(text):
        raise SystemExit("evegen: block GEN:%s missing" % name)
    return pat.sub(lambda m: "<!-- GEN:%s -->\n%s\n<!-- /GEN:%s -->" % (name, body.rstrip("\n"), name), text)


REPO_PATH = r"(?:spec|code|script|test|design|backlog|tools|drivers)/[^`\s]+"


def strip_ids(text):
    """The manual names no decision, no folder of the repository and no test: `(D-094)`, `D-094, D-095`,
    `(spec/syntax/x.md#y)` and `script/x.py` are dropped, with the parentheses they leave empty."""
    text = re.sub(r"\s*\((?:(?:earlier|see|and|to)\s+)?[DQ]-\d+[a-z]?(?:\s*(?:,|;|and|to)\s*[DQ]-\d+[a-z]?)*\)", "", text)
    text = re.sub(r"[,;]?\s*\b[DQ]-\d+[a-z]?\b", "", text)
    text = re.sub(r"\s*\(`" + REPO_PATH + r"`\)", "", text)
    text = re.sub(r"[,;]?\s*`" + REPO_PATH + r"`", "", text)
    text = re.sub(r"\(\s*[,;]?\s*\)", "", text)
    text = re.sub(r"\(\s*[,;]\s*", "(", text)
    return re.sub(r"[ ]+([,.;:])", r"\1", text)


# ---------------------------------------------------------------- features.md

def features_blocks(levels):
    feats = model.all_features(levels)
    live = [f for f in feats if f["stage"]]
    rows = []
    for lv in levels:
        mine = [f for f in lv["features"] if f["stage"]]
        rows.append([model.level_label(lv)] + [sum(1 for f in mine if f["stage"] == s) for s in model.STAGES] + [len(mine)])
    rows.append(["**All**"] + ["**%d**" % sum(1 for f in live if f["stage"] == s) for s in model.STAGES] + ["**%d**" % len(live)])
    summary = table(("Level", "Validated", "Drafted", "Planned", "Total"), rows)
    parts = []
    for lv in levels:
        mine = [f for f in lv["features"] if f["stage"]]
        parts.append("### [%s: %s](levels/%s.md)\n\n%s\n\n%s" % (
            model.level_label(lv), lv["name"], lv["id"], strip_ids(lv["description"]),
            table(("Code", "Feature", "Stage", "What it is"),
                  [("`%s`" % f["id"], f["name"], f["stage"], strip_ids(f["summary"]).replace("|", "\\|")) for f in mine])))
    return {"summary": summary, "list": "\n\n".join(parts)}


# ---------------------------------------------------------------- tests.md

def tests_blocks(suites):
    rows, failing, last = [], [], ""
    all_total = all_pass = 0
    for s in suites:
        tests = s["tests"]
        passed = sum(1 for t in tests if t["status"] == "PASS")
        dates = [t["last"] for t in tests if t["last"] not in ("", "-")]
        last = max([last] + dates)
        rows.append((model.suite_label(s), len(tests), passed, len(tests) - passed,
                     "%d%%" % (100 * passed // len(tests)) if tests else "-", max(dates)[:10] if dates else "-"))
        all_total += len(tests)
        all_pass += passed
        for t in tests:
            if t["status"] != "PASS":
                failing.append((model.suite_label(s), "`%s`" % t["name"], t["status"], strip_ids(t["title"]),
                                t["reason"] or "-"))
    rows.append(("**All**", "**%d**" % all_total, "**%d**" % all_pass, "**%d**" % (all_total - all_pass),
                 "**%d%%**" % (100 * all_pass // all_total) if all_total else "-", ""))
    summary = ("%d of %d tests pass; last run %s.\n\n" % (all_pass, all_total, last[:16] or "never")
               + table(("Suite", "Tests", "Pass", "Fail", "%", "Last run"), rows))
    fail = (table(("Suite", "Test", "Status", "What it tests", "Reason"), failing) if failing
            else "None: every test of the last run passes.")
    return {"summary": summary, "failing": fail}


# ---------------------------------------------------------------- performance.md

def ms(x):
    return "%d ms" % round(x)


def ratio(eve, py):
    return "%.1fx" % (eve / py) if py else "-"


def vkey(v):
    return tuple(int(x) for x in v.split("."))


def per_level(run):
    out = {}
    for name, res in run.get("results", {}).items():
        m = re.match(r"p(\d)", name)
        if not m:
            continue
        eve, py = out.get(int(m.group(1)), (0.0, 0.0))
        p = run.get("python", {}).get(name)
        out[int(m.group(1))] = (eve + res["median_ms"], None if (p is None or py is None) else py + p)
    return out


def performance_blocks(runs, descriptions):
    if not runs:
        none = "No saved ReleaseSafe benchmark run yet."
        return {"summary": none, "benchmarks": none, "results": none, "history": none}
    run = runs[-1]
    size = run.get("exe_bytes")
    head = "Run of %s, version %s%s." % (run["date"], run["version"], ", `eve.exe` %.1f MB" % (size / (1 << 20)) if size else "")
    summary = head + "\n\n" + table(
        ("Benchmarks", "Eve", "Python", "Eve / Python"),
        [("Level %d" % lv, ms(e), ms(p) if p else "-", ratio(e, p)) for lv, (e, p) in sorted(per_level(run).items())])
    names = sorted(run.get("results", {}))
    benchmarks = table(("Benchmark", "Level", "What it measures"),
                       [("`%s`" % n, n[1] if re.match(r"p\d", n) else "-", descriptions.get(n, "")) for n in names])
    rows = []
    for name in names:
        res = run["results"][name]
        py = run.get("python", {}).get(name)
        rows.append(("`%s`" % name, ms(res["median_ms"]), ms(py) if py else "-", ratio(res["median_ms"], py),
                     "%.1f MB" % res["peak_mb"] if res.get("peak_mb") else "-"))
    results = table(("Benchmark", "Eve", "Python", "Eve / Python", "Peak memory"), rows)
    last_of = {}
    for r in runs:
        last_of[r["version"]] = r
    hist = []
    for v in sorted(last_of, key=vkey):
        r = last_of[v]
        eve = sum(x["median_ms"] for x in r.get("results", {}).values())
        py = sum(r.get("python", {}).get(n, 0) for n in r.get("results", {}))
        hist.append((v, r["date"][:10], len(r.get("results", {})), ms(eve), ms(py) if py else "-", ratio(eve, py)))
    history = ("The last saved run of each version; the set of benchmarks grows with the versions.\n\n"
               + table(("Version", "Date", "Benchmarks", "Eve total", "Python total", "Eve / Python"), hist))
    return {"summary": summary, "benchmarks": benchmarks, "results": results, "history": history}


# ---------------------------------------------------------------- levels/*.md: features with verified examples

EXPECT = re.compile(r"/\*@expect(.*?)\*/", re.S)
MAX_EXAMPLE_LINES = 36


def example_of(root, suite, test):
    """-> (source, output lines) of a test that passes and is short, or None. The expectation block is cut from
    the source; a decision id in a comment is dropped."""
    path = model.test_file(root, suite, test["name"])
    if path is None or test["status"] != "PASS" or path.parent.name != suite:
        return None
    text = model.read_text(path)
    m = EXPECT.search(text)
    try:
        exp = json.loads(m.group(1)) if m else {}
    except ValueError:
        return None
    out = exp.get("stdout")
    if exp.get("exit", 0) != 0 or exp.get("args") or not out or "skip" in exp or "syntax_error" in exp:
        return None
    out = out.split("\n") if isinstance(out, str) else out
    src = strip_ids(EXPECT.sub("", text))
    src = re.sub(r"^\*\* spec:.*\n", "", src, flags=re.M).strip("\n")
    lines = src.split("\n")
    if len(lines) > MAX_EXAMPLE_LINES or len(out) > 14:
        return None
    return src, [l.rstrip() for l in out]


def examples_by_feature(root, suites):
    """{feature id: (source, output)}: the first short passing test of each feature, in the order of the suites."""
    found = {}
    for s in suites:
        if s["kind"] != "level":
            continue
        for t in s["tests"]:
            for fid in t["features"]:
                if fid not in found:
                    ex = example_of(root, s["suite"], t)
                    if ex:
                        found[fid] = ex
    return found


def level_page(lv, examples):
    mine = [f for f in lv["features"] if f["stage"]]
    out = [NOTE, "# %s: %s\n" % (model.level_label(lv), lv["name"]), strip_ids(lv["description"]) + "\n",
           table(("Code", "Feature", "Stage"), [("[`%s`](#%s)" % (f["id"], model.slug(f["id"] + " " + f["name"])),
                                                  f["name"], f["stage"]) for f in mine]) + "\n"]
    for f in mine:
        out.append("## %s %s\n" % (f["id"], f["name"]))
        out.append("Stage: **%s**.\n" % f["stage"])
        if f["body"]:
            out.append(strip_ids(f["body"]).replace("\n# ", "\n### ") + "\n")
        if f["id"] in examples:
            src, res = examples[f["id"]]
            out.append("An example that runs, and what it prints:\n\n```eve\n%s\n```\n\n```text\n%s\n```\n" % (src, "\n".join(res)))
    return "\n".join(out)


# ---------------------------------------------------------------- reference/*.md from the lexical data of the spec

def keywords_page(data):
    items = sorted(data["items"], key=lambda i: (i["category"], i["id"]))
    rows = [("`%s`" % i["id"], i["category"] + (" (contextual)" if i.get("contextual") else ""),
             strip_ids(i["summary"]).replace("|", "\\|")) for i in items]
    return "\n".join([NOTE, "# Keywords\n",
                      "The words of the language. A **contextual** word is a keyword only where the grammar expects it and an ordinary name everywhere else.\n",
                      table(("Word", "Category", "Meaning"), rows) + "\n"])


def operators_page(data):
    items = sorted(data["items"], key=lambda i: (-(i["precedence"] or 0), i["id"]))
    rows = [("`%s`" % i["symbol"].replace("|", "\\|"), i["name"], i["kind"], "-" if i["precedence"] is None else i["precedence"], i["associativity"] or "-",
             strip_ids(i["summary"]).replace("|", "\\|")) for i in items]
    return "\n".join([NOTE, "# Operators\n",
                      "From the tightest binding to the loosest: a higher precedence binds tighter. Assignment and modifier operators have precedence 0.\n",
                      table(("Symbol", "Name", "Kind", "Precedence", "Associativity", "Meaning"), rows) + "\n"])


def delimiters_page(data):
    def cell(text):
        if not text:
            return "-"
        text = text.replace("|", "\\|")
        return "`%s`" % text if len(text) <= 4 else text

    rows = [(cell(i["open"]), cell(i["close"]), i["kind"], strip_ids(i["summary"]).replace("|", "\\|")) for i in data["items"]]
    return "\n".join([NOTE, "# Delimiters\n", "Comments, strings and the other bracketed forms of the source text.\n",
                      table(("Opens", "Closes", "Kind", "Meaning"), rows) + "\n"])
