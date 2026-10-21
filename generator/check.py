"""evegen check: the rules that keep the spec, the tests and the manual apart, and the links that join them.

Errors (exit code 1):
- a feature has no Markdown file, or two features have the same id, or an id is not `F-<AREA>-<nn>`;
- a test names a feature that does not exist; a test of a tracking file has no source file, or a source file has no test;
- a `spec` reference of a feature names a page or an anchor that does not exist;
- the spec (pages, data, feature files) names the design, the backlog, a decision or a question (`D-nnn`, `Q-nnn`), or a test;
- a page of the manual links to the spec or to a test, or names a decision id;
- spec/spec.json or a generated page of the manual is out of date.
Warnings (printed with -v): a feature that is `done` and has no test; a test with no feature; a test source (.eve)
that names a decision or the design (the tests refer to the spec only).
"""
import re

import build
import model
import specindex
from model import ROOT, read_text

FEATURE_ID = re.compile(r"F-[A-Z]+-\d+$")
OUTSIDE = re.compile(r"\bdesign/|\bbacklog/|\b[DQ]-\d{2,3}[a-z]?\b|\bdecision/")
TEST_SOURCE = re.compile(r"\bdesign/|\bbacklog/|\bdecision/|\b[DQ]-\d{3}\b")
LINK_OUT = re.compile(r"\]\((?:\.\./)*(?:spec|test)/|https://github\.com/[^)]*/(?:spec|test)/")


def spec_files(root):
    spec = root / "spec"
    return [p for p in sorted(spec.rglob("*")) if p.is_file() and p.suffix in (".md", ".json") and p.name != "spec.json"]


def check_features(root, levels, errors):
    seen = {}
    index = {p["path"]: p for p in specindex.build(root)["pages"]}
    for lv in levels:
        for f in lv["features"]:
            fid = f["id"]
            if not FEATURE_ID.match(fid):
                errors.append("%s: bad feature id %r" % (lv["id"], fid))
            if fid in seen:
                errors.append("%s: feature %s is also in %s" % (lv["id"], fid, seen[fid]))
            seen[fid] = lv["id"]
            if not (root / "spec" / "features" / f["doc"]).is_file():
                errors.append("%s: no file %s" % (fid, f["doc"]))
            elif not f["body"]:
                errors.append("%s: the file %s has no text" % (fid, f["doc"]))
            for ref in f.get("spec", []):
                page, _, anchor = ref.partition("#")
                entry = index.get(page)
                if not entry and not (root / "spec" / page).is_file():
                    errors.append("%s: spec page %s does not exist" % (fid, page))
                elif anchor and entry and anchor not in {s[1] for s in entry["sections"]}:
                    errors.append("%s: spec anchor %s does not exist" % (fid, ref))
    return seen


def check_tests(root, suites, known, errors, warnings):
    covered = set()
    for s in suites:
        names = set()
        for t in s["tests"]:
            names.add(t["name"])
            if not t["features"] and s["kind"] == "level":
                warnings.append("%s/%s: the test names no feature" % (s["suite"], t["name"]))
            for fid in t["features"]:
                covered.add(fid)
                if fid not in known:
                    errors.append("%s/%s: unknown feature %s" % (s["suite"], t["name"], fid))
            src = model.test_file(root, s["suite"], t["name"])
            if src is None and s["suite"] != "scaffold":
                errors.append("%s/%s: no source file" % (s["suite"], t["name"]))
            elif src is not None and TEST_SOURCE.search(read_text(src)):
                warnings.append("%s/%s: the source names a decision or the design" % (s["suite"], t["name"]))
        folder = root / "test" / s["suite"]
        for p in sorted(folder.glob("*.eve")):
            if p.stem not in names and re.match(r"[a-z]\d+_", p.stem):
                errors.append("%s/%s: not in %s.json (run the test runner)" % (s["suite"], p.stem, s["suite"]))
    return covered


def check_isolation(root, errors):
    for p in spec_files(root):
        rel = p.relative_to(root).as_posix()
        for n, line in enumerate(read_text(p).split("\n"), 1):
            if OUTSIDE.search(line) or re.search(r"(?<![\w/])test/(?:level|smoke|bytecode|scaffold)", line):
                errors.append("%s:%d: the spec names the design, a decision or a test: %s" % (rel, n, line.strip()[:90]))
                break
    manual = root / "manual"
    for p in sorted(manual.rglob("*.md")) if manual.is_dir() else []:
        rel = p.relative_to(root).as_posix()
        if rel.startswith(("manual/releases/", "manual/evevm/", "manual/evecp/", "manual/evecm/", "manual/evetx/",
                           "manual/eveux/", "manual/evewp/", "manual/drivers/")):
            continue
        for n, line in enumerate(read_text(p).split("\n"), 1):
            if LINK_OUT.search(line) or re.search(r"\b[DQ]-\d{3}\b", line):
                errors.append("%s:%d: the manual links to the spec or a test, or names a decision: %s" % (rel, n, line.strip()[:90]))
                break


def run(root=ROOT, verbose=False):
    errors, warnings = [], []
    levels = model.load_levels(root)
    suites = model.load_suites(root)
    known = check_features(root, levels, errors)
    covered = check_tests(root, suites, known, errors, warnings)
    for lv in levels:
        for f in lv["features"]:
            if f["status"] == "done" and f["id"] not in covered:
                warnings.append("%s: done, and no test names it" % f["id"])
            if f["status"] in ("partial", "open") and lv["id"] in ("level1", "level2", "level3", "level4", "level5"):
                page = root / "spec" / "features" / f["doc"]
                if not page.is_file() or not re.search(r"^## Missing\n\n- ", read_text(page), re.M):
                    errors.append("%s: %s, and its page has no '## Missing' list" % (f["id"], f["status"]))
    check_isolation(root, errors)
    if not specindex.run(root, check=True):
        errors.append("spec/spec.json is out of date (evegen index)")
    for rel in build.run(root, check=True):
        errors.append("manual/%s is out of date (evegen manual)" % rel)
    for e in errors:
        print("error:   " + e)
    if verbose:
        for w in warnings:
            print("warning: " + w)
    print("evegen check: %d feature(s), %d test(s), %d error(s), %d warning(s)%s" % (
        len(known), sum(len(s["tests"]) for s in suites), len(errors), len(warnings),
        "" if verbose or not warnings else " (-v lists them)"))
    return 1 if errors else 0
