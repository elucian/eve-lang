"""Run Eve conformance tests on an Eve implementation and write Markdown reports.

usage: python script/runtest.py TARGET... [--eve PATH] [--timeout SEC] [--out DIR] [-q]

TARGET is one of:
  1 | level1          every test in test/level1 (likewise 2, 3)
  all                 every level
  a03 | a03_print     one test, by name or name prefix, searched in every level
  test/level1/a03_print.eve
                      one test, by path

A test is a `*.eve` file directly inside test/levelN/ (subfolders hold level-2
aspects and are not run on their own). Its expectations are in expect.json, one
file per level: {"<name>": {...}} with these optional keys:
  "exit"       expected exit code (default 0)
  "args"       command-line arguments
  "stdout"     the exact expected output: a string, or a list of lines (line
               endings and trailing white space at the end are ignored)
  "contains"   a list of strings that must all appear in the output
  "skip"       a reason: the test is not run
  "note"       free text
A test that prints (a `print` or `write` statement) must declare "stdout" or
"contains": otherwise it FAILS with "no expected output declared". An expected
output that is not found in the real output makes the test FAIL. A legacy
<name>.out file is still read when expect.json has no "stdout" for the test.

Each test runs as `<eve> test/levelN/<name>.eve [args]` from the repo root.
Verdicts: PASS, FAIL (wrong exit code or stdout), ERROR (timeout, eve missing),
SKIP. Reports go to temp/output/ (git-ignored): one `<level>/<name>.md` per
test, plus a summary `<targets>.md` when a run has more than one test.
Exit status: 0 when nothing failed or errored.

After every run the framework updates test/status.json (history per test) and the
the list between the TESTS markers of test/readme.md. status.json keeps, for every
test file found in test/levelN/: status, failed runs, failed checks and reason of the
last run, date, title. A new test is added as NEW and a deleted one is removed. The
readme lists code, name, level and the title cut to 50 characters, in fixed-width
columns, and is rewritten only when that list changes. Use --no-update to leave both
files alone.

--eve defaults to $EVE, else bin/eve.exe (Windows) or bin/eve.
"""
import argparse
import datetime
import difflib
import json
import os
import re
import subprocess
import sys
import time

from _common import die

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DIR = os.path.join(ROOT, "test")
LEVELS = ("level1", "level2", "level3")
# Process exit codes, plan/decisions.md D-010.
EXIT_MEANING = {0: "normal", 1: "abnormal exit", 2: "error", 3: "warning", 70: "VM not implemented"}


def exit_label(code):
    return "-" if code is None else f"{code} {EXIT_MEANING.get(code, '')}".strip()


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def level_tests(level):
    folder = os.path.join(TEST_DIR, level)
    if not os.path.isdir(folder):
        die(f"no such level: test/{level}")
    return [os.path.join(folder, f) for f in sorted(os.listdir(folder)) if f.endswith(".eve")]


def find_test(name):
    if name.endswith(".eve") and os.path.isfile(os.path.join(ROOT, name)):
        return [os.path.abspath(os.path.join(ROOT, name))]
    hits = [t for lv in LEVELS if os.path.isdir(os.path.join(TEST_DIR, lv))
            for t in level_tests(lv) if os.path.basename(t)[:-4].startswith(name)]
    exact = [t for t in hits if os.path.basename(t)[:-4] == name]
    if exact:
        return exact[:1]
    if not hits:
        die(f"no test matches '{name}'")
    if len(hits) > 1:
        die(f"'{name}' is ambiguous: " + ", ".join(rel(t) for t in hits))
    return hits


def resolve(target):
    """Return (label, [test paths]) for one command-line target."""
    t = target.lower()
    if t == "all":
        return "all", [p for lv in LEVELS if os.path.isdir(os.path.join(TEST_DIR, lv))
                       for p in level_tests(lv)]
    if t.isdigit():
        t = "level" + t
    if t in LEVELS:
        return t, level_tests(t)
    tests = find_test(target)
    return os.path.basename(tests[0])[:-4], tests


def load_expect(test):
    folder, name = os.path.split(test)
    name = name[:-4]
    spec = {}
    manifest = os.path.join(folder, "expect.json")
    if os.path.isfile(manifest):
        with open(manifest, encoding="utf-8") as f:
            spec = dict(json.load(f).get(name, {}))
    if isinstance(spec.get("stdout"), list):
        spec["stdout"] = "\n".join(spec["stdout"])
    out = os.path.join(folder, name + ".out")
    if "stdout" not in spec and os.path.isfile(out):
        with open(out, encoding="utf-8") as f:
            spec["stdout"] = f.read()
    spec.setdefault("exit", 0)
    spec.setdefault("args", [])
    return spec


def norm(text):
    return text.replace("\r\n", "\n").rstrip()


def prints_output(test):
    """True when the source has a print or write statement (comments ignored)."""
    with open(test, encoding="utf-8", errors="replace") as f:
        src = f.read()
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return any(re.match(r"\s*(?:\w+:\s*)?(print|write)\b", re.sub(r"\*\*.*", "", line))
               for line in src.splitlines())


def run_test(eve, test, timeout):
    exp = load_expect(test)
    res = {"test": test, "expect": exp, "stdout": "", "stderr": "", "exit": None, "ms": 0,
           "cmd": [rel(eve) if eve.startswith(ROOT) else eve, rel(test), *exp["args"]]}
    if "skip" in exp:
        res.update(verdict="SKIP", reason=exp["skip"])
        return res
    start = time.perf_counter()
    try:
        p = subprocess.run([eve, rel(test), *exp["args"]], cwd=ROOT, capture_output=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired as e:
        res.update(verdict="ERROR", reason=f"timeout after {timeout}s",
                   stdout=(e.stdout or b"").decode("utf-8", "replace"))
        return res
    except OSError as e:
        res.update(verdict="ERROR", reason=f"cannot start eve: {e}")
        return res
    res["ms"] = round((time.perf_counter() - start) * 1000)
    res["exit"] = p.returncode
    res["stdout"] = p.stdout.decode("utf-8", "replace")
    res["stderr"] = p.stderr.decode("utf-8", "replace")
    problems = []
    if p.returncode != exp["exit"]:
        problems.append(f"exit code {p.returncode}, expected {exp['exit']}")
    if "stdout" in exp and norm(res["stdout"]) != norm(exp["stdout"]):
        problems.append("stdout differs")
    for text in exp.get("contains", []):
        if text not in res["stdout"]:
            problems.append(f"expected output not found: {text!r}")
    if "stdout" not in exp and not exp.get("contains") and prints_output(test):
        problems.append("no expected output declared in expect.json (the test prints)")
    res["verdict"] = "FAIL" if problems else "PASS"
    res["reason"] = "; ".join(problems)
    res["checks"] = len(problems)
    return res


def fence(text, lang="text"):
    text = text.replace("\r\n", "\n").rstrip("\n")
    tick = "````" if "```" in text else "```"
    return f"{tick}{lang}\n{text}\n{tick}\n" if text else "_(empty)_\n"


def test_report(res):
    name = os.path.basename(res["test"])[:-4]
    exp = res["expect"]
    with open(res["test"], encoding="utf-8", errors="replace") as f:
        source = f.read()
    exit_cell = exit_label(res["exit"])
    lines = [
        f"# {name}: {res['verdict']}", "",
        "| | |", "|---|---|",
        f"| Test | `{rel(res['test'])}` |",
        f"| Command | `{' '.join(res['cmd'])}` |",
        f"| Exit code | {exit_cell} (expected {exit_label(exp['exit'])}) |",
        f"| Time | {res['ms']} ms |",
        f"| Reason | {res['reason'] or '-'} |", "",
        "## Source", "", fence(source, "eve"),
        "## stdout", "", fence(res["stdout"]),
        "## stderr", "", fence(res["stderr"]),
    ]
    if "stdout" in exp:
        lines += ["## Expected stdout", "", fence(exp["stdout"])]
        if "stdout differs" in res["reason"]:
            diff = difflib.unified_diff(norm(exp["stdout"]).split("\n"),
                                        norm(res["stdout"]).split("\n"),
                                        "expected", "actual", lineterm="")
            lines += ["## Diff", "", fence("\n".join(diff), "diff")]
    return "\n".join(lines)


def eve_version(eve):
    try:
        p = subprocess.run([eve, "--version"], capture_output=True, timeout=10)
        return p.stdout.decode("utf-8", "replace").strip() or "-"
    except (OSError, subprocess.TimeoutExpired):
        return "not available"


STATUS_FILE = os.path.join(TEST_DIR, "status.json")
README = os.path.join(TEST_DIR, "readme.md")
BEGIN = "<!-- TESTS:BEGIN (generated by script/runtest.py, do not edit) -->"
END = "<!-- TESTS:END -->"
DESC = 50      # width of the description column of the readme list


def all_tests():
    """Every test file on disk: {key: path}, key is 'levelN/name'."""
    found = {}
    for lv in LEVELS:
        if os.path.isdir(os.path.join(TEST_DIR, lv)):
            for p in level_tests(lv):
                found[f"{lv}/{os.path.basename(p)[:-4]}"] = p
    return found


def title_of(test):
    """First comment line at column 1 (# title or ## subtitle), or ''."""
    note = ""
    with open(test, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("#") and not line.startswith("#!"):
                return line.lstrip("#").strip()
            if line.startswith("**") and not note:
                note = line.lstrip("*").strip()
            if line.strip() and not line.startswith(("#", "/*", "*")):
                break
    return note


def update_status(results, now):
    """Sync test/status.json with the files on disk, record this run, rewrite the readme table."""
    state = {}
    if os.path.isfile(STATUS_FILE):
        with open(STATUS_FILE, encoding="utf-8") as f:
            state = json.load(f).get("tests", {})
    tests = all_tests()
    state = {k: v for k, v in state.items() if k in tests}          # removed tests disappear
    for key in tests:                                               # new tests are appended
        state.setdefault(key, {"status": "NEW", "failures": 0, "runs": 0, "checks": 0, "last": "-"})
        mtime = int(os.path.getmtime(tests[key]))
        if state[key].get("mtime") != mtime:       # the title is read again only when the file changed
            state[key]["mtime"] = mtime
            state[key]["title"] = title_of(tests[key])
    for res in results:
        key = f"{os.path.basename(os.path.dirname(res['test']))}/{os.path.basename(res['test'])[:-4]}"
        s = state[key]
        s["status"] = res["verdict"]
        s["checks"] = res.get("checks", 0)
        s["reason"] = res.get("reason", "")
        s["last"] = now
        if res["verdict"] != "SKIP":
            s["runs"] += 1
        if res["verdict"] in ("FAIL", "ERROR"):
            s["failures"] += 1
    with open(STATUS_FILE, "w", encoding="utf-8", newline="\n") as f:
        json.dump({"tests": dict(sorted(state.items()))}, f, indent=1, ensure_ascii=False)
        f.write("\n")
    block = readme_block(state)
    with open(README, encoding="utf-8", newline="") as f:
        text = f.read()
    eol = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    if BEGIN in text and END in text:
        a, b = text.index(BEGIN), text.index(END) + len(END)
        new_text = text[:a] + block + text[b:]
    else:
        i = text.index("## Level 1") if "## Level 1" in text else len(text)
        new_text = text[:i] + "## Test list\n\n" + block + "\n\n" + text[i:]
    if new_text != text:                       # the readme changes only when the list of tests changes
        with open(README, "w", encoding="utf-8", newline="") as f:
            f.write(new_text.replace("\n", eol))


def readme_block(state):
    """Fixed-width list of the tests (no status: that is in status.json)."""
    widths = (4, 20, 6, DESC)

    def line(cells):
        return "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"

    rows = [line(("Code", "Test", "Level", "Description")),
            "|" + "|".join("-" * (w + 2) for w in widths) + "|"]
    for key in sorted(state):
        lv, name = key.split("/")
        desc = state[key].get("title", "")
        if len(desc) > DESC:
            desc = desc[:DESC - 3] + "..."
        rows.append(line((name.split("_")[0], name, lv, desc)))
    return "\n".join([BEGIN, "",
                      f"{len(state)} tests. Status, failures and last run of every test are in `status.json`.", "",
                      *rows, "", END])


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text if text.endswith("\n") else text + "\n")


def main():
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="+", metavar="TARGET")
    default_eve = os.path.join(ROOT, "bin", "eve.exe" if os.name == "nt" else "eve")
    ap.add_argument("--eve", default=os.environ.get("EVE", default_eve))
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--out", default=os.path.join(ROOT, "temp", "output"))
    ap.add_argument("-q", "--quiet", action="store_true", help="print only the summary line")
    ap.add_argument("--no-update", action="store_true",
                    help="do not update test/status.json and test/readme.md")
    args = ap.parse_args()
    eve = os.path.abspath(args.eve) if os.path.exists(args.eve) else args.eve
    version = eve_version(eve)

    labels, tests = [], []
    for target in args.targets:
        label, found = resolve(target)
        labels.append(label)
        tests += [t for t in found if t not in tests]
    label = "-".join(labels)
    if not tests:
        die(f"no tests in {label}")

    results = []
    for test in tests:
        res = run_test(eve, test, args.timeout)
        results.append(res)
        level = os.path.basename(os.path.dirname(test))
        report = os.path.join(args.out, level, os.path.basename(test)[:-4] + ".md")
        write(report, test_report(res))
        res["report"] = report
        if not args.quiet:
            print(f"{res['verdict']:5}  {rel(test)}" + (f"  ({res['reason']})" if res["reason"] else ""))

    if not args.no_update:
        update_status(results, f"{datetime.datetime.now():%Y-%m-%d %H:%M}")
    counts = {v: sum(r["verdict"] == v for r in results) for v in ("PASS", "FAIL", "ERROR", "SKIP")}
    tally = ", ".join(f"{n} {v.lower()}" for v, n in counts.items())
    if len(results) == 1:
        print(f"{label}: {tally}  -> {rel(results[0]['report'])}")
        sys.exit(1 if counts["FAIL"] or counts["ERROR"] else 0)
    summary_path = os.path.join(args.out, label + ".md")
    rows = [f"| [{os.path.basename(r['test'])[:-4]}]"
            f"({os.path.relpath(r['report'], args.out).replace(os.sep, '/')}) | {r['verdict']} | "
            f"{exit_label(r['exit'])} | {r['ms']} | {r['reason'] or '-'} |"
            for r in results]
    write(summary_path, "\n".join([
        f"# Test run: {label}", "",
        f"- Date: {datetime.datetime.now():%Y-%m-%d %H:%M}",
        f"- Implementation: `{rel(eve) if eve.startswith(ROOT) else eve}` ({version})",
        f"- Result: {tally}", "",
        "| Test | Verdict | Exit | ms | Reason |", "|---|---|---|---|---|", *rows,
    ]))
    print(f"{label}: {tally}  -> {rel(summary_path)}")
    sys.exit(1 if counts["FAIL"] or counts["ERROR"] else 0)


if __name__ == "__main__":
    main()
