"""Run Eve conformance tests on an Eve implementation and write Markdown reports.

usage: python script/runtest.py TARGET... [--eve PATH] [--timeout SEC] [--out DIR] [-q]

TARGET is one of:
  1 | level1          every test in test/level1 (likewise 2 to 7)
  smoke               every test in test/smoke (the tools of the VM: slot, workflow)
  all                 every level, and smoke
  a03 | a03_print     one test, by name or name prefix, searched in every level
  test/level1/a03_print.eve
                      one test, by path

A test is either a file or a folder:
  test/levelN/<name>.eve          a single script; its expectations are JSON in comment blocks of
                                  the script itself, /*@expect { "stdout": [...] } */ (D-094); the
                                  old expect.json of the level, {"<name>": {...}}, is still read
                                  and the blocks of the script override it
  test/levelN/<name>/<name>.eve   a project test (D-073): the folder is a whole Eve project, with
                                  the driver <name>.eve and any of asp/, lib/, web/ (templates), data/, out/. Its
                                  expectations are in <name>/expect.json: {...} (one object).
                                  It runs with the folder as working directory, so paths in the
                                  project are relative to it; out/ is emptied before each run.
  test/levelN/<name>/<code>_test1.eve, <code>_test2.eve, ...
                                  more drivers of the same project (D-133): each one is a variation
                                  (another use case) of the same asp/, lib/ and data/. <code> is the
                                  code of the folder (b05 for b05_apply_spread). Each file is a test
                                  of its own, with its expectations in its /*@expect*/ block; the
                                  driver inside is named like the file. `runtest.py b05` runs the
                                  project driver and its variations, `runtest.py b05_test2` one of them.
Other folders are not tests. The expectation keys, all optional:
  "exit"       expected exit code (default 0)
  "args"       command-line arguments
  "serve"      a command file (path from the repo root): the test then runs the VM as
               `eve -x -t 5 -i <serve>` (a session, no script on the command line)
  "stdout"     the exact expected output: a string, or a list of lines (line
               endings and trailing white space at the end are ignored)
  "contains"   a list of strings that must all appear in the output
  "stderr"     a list of strings that must all appear in the error output
  "files"      project tests: {"out/report.txt": "text" or [lines]}: each file must exist
               after the run with this content (line endings and trailing white space ignored).
               A value that is an object, or a list that holds objects, is JSON: the file is
               parsed and must match it (an object may have more keys; "*" matches any value).
               "{date}" in a file name is the date of the run in UTC, YYYY-MM-DD (D-114)
  "skip"       a reason: the test is not run
  "note"       free text
A test that prints (a `print` or `write` statement) must declare "stdout" or
"contains": otherwise it FAILS with "no expected output declared". An expected
output that is not found in the real output makes the test FAIL. A legacy
<name>.out file is still read when expect.json has no "stdout" for the test.

A file test runs as `<eve> test/levelN/<name>.eve [args]` from the repo root; a project test
runs as `<eve> <name>.eve [args]` from its folder.
Verdicts: PASS, FAIL (wrong exit code or stdout), ERROR (timeout, eve missing),
SKIP. Reports go to temp/output/ (git-ignored): one `<level>/<name>.md` per
test, plus a summary `<targets>.md` when a run has more than one test.
Exit status: 0 when nothing failed or errored.

After every run the framework updates status.json (history per test) and the
the list between the TESTS markers of readme.md, both in each level folder. status.json
keeps, for every test file of test/levelN/: status, failed runs, failed checks and
reason of the last run, date, title. A new test is added as NEW and a deleted one is
removed. The readme lists code, name and the title cut to 50 characters, in
fixed-width columns, and is rewritten only when that list changes. Use --no-update
to leave these files alone.

--check is a dry run for syntax errors: `eve --check <test>` must exit 0 (65 when expect.json
declares "syntax_error": true). Nothing is executed, written or recorded in status.json.

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
LEVELS = ("level1", "level2", "level3", "level4", "level5", "level6", "level7", "smoke")
# Process exit codes, plan/decision_level1.md D-010.
EXIT_MEANING = {0: "normal", 1: "abnormal exit", 2: "error", 3: "warning", 70: "VM not implemented"}


def exit_label(code):
    return "-" if code is None else f"{code} {EXIT_MEANING.get(code, '')}".strip()


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


VARIATION = re.compile(r"^([a-z]\d+)_test\d+\.eve$")


def variations(folder, name):
    """The variation drivers of a project folder (D-133): <code>_test1.eve, <code>_test2.eve, ..."""
    code = name.split("_")[0]
    found = []
    for f in sorted(os.listdir(folder)):
        m = VARIATION.match(f)
        if m and m.group(1) == code and os.path.isfile(os.path.join(folder, f)):
            found.append(os.path.join(folder, f))
    return found


def is_variation(test):
    """True for <folder>/<code>_testN.eve inside a project folder."""
    folder, name = os.path.split(test)
    m = VARIATION.match(name)
    return bool(m) and os.path.basename(folder).split("_")[0] == m.group(1)


def level_tests(level):
    folder = os.path.join(TEST_DIR, level)
    if not os.path.isdir(folder):
        die(f"no such level: test/{level}")
    tests = []
    for f in sorted(os.listdir(folder)):
        path = os.path.join(folder, f)
        if f.endswith(".eve") and os.path.isfile(path):
            tests.append(path)
        elif os.path.isfile(os.path.join(path, f + ".eve")):
            tests.append(os.path.join(path, f + ".eve"))
            tests.extend(variations(path, f))
    return tests


def find_test(name):
    if name.endswith(".eve") and os.path.isfile(os.path.join(ROOT, name)):
        return [os.path.abspath(os.path.join(ROOT, name))]
    hits = [t for lv in LEVELS if os.path.isdir(os.path.join(TEST_DIR, lv))
            for t in level_tests(lv) if os.path.basename(t)[:-4].startswith(name)]
    exact = [t for t in hits if os.path.basename(t)[:-4] == name]
    if exact:
        # a project driver brings its variations along (D-133); a variation runs alone
        return exact[:1] + (variations(os.path.dirname(exact[0]), os.path.basename(exact[0])[:-4])
                            if is_project(exact[0]) and not is_variation(exact[0]) else [])
    if not hits:
        die(f"no test matches '{name}'")
    mains = [t for t in hits if not is_variation(t)]
    if len(mains) == 1:
        hits = [mains[0]] + (variations(os.path.dirname(mains[0]), os.path.basename(mains[0])[:-4])
                             if is_project(mains[0]) else [])
    elif len(hits) > 1:
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


def is_project(test):
    """True for test/levelN/<name>/<name>.eve, a project test (D-073), and for its variations (D-133)."""
    folder, name = os.path.split(test)
    return os.path.basename(folder) == name[:-4] or is_variation(test)


def level_of(test):
    """The level folder name of a test (level1, level2, smoke, ...)."""
    folder = os.path.dirname(test)
    return os.path.basename(os.path.dirname(folder) if is_project(test) else folder)


def test_cwd(test):
    return os.path.dirname(test) if is_project(test) else ROOT


EXPECT_BLOCK = re.compile(r"/\*@expect(.*?)\*/", re.S)


def source_expect(test):
    """The expectations written in the test itself: comment blocks /*@expect { json } */ (D-094).
    Several blocks are merged: a list is extended, any other key is replaced."""
    with open(test, encoding="utf-8") as f:
        text = f.read()
    spec = {}
    for m in EXPECT_BLOCK.finditer(text):
        try:
            block = json.loads(m.group(1))
        except ValueError as e:
            die(f"{rel(test)}: bad /*@expect*/ block: {e}")
        for key, value in block.items():
            if isinstance(value, list) and isinstance(spec.get(key), list):
                spec[key] = spec[key] + value
            else:
                spec[key] = value
    return spec


def load_expect(test):
    folder, name = os.path.split(test)
    name = name[:-4]
    spec = {}
    manifest = os.path.join(folder, "expect.json")
    if os.path.isfile(manifest):
        with open(manifest, encoding="utf-8") as f:
            data = json.load(f)
        spec = dict(data if is_project(test) else data.get(name, {}))
        if is_variation(test):
            spec = {}          # expect.json is the expectation of the project driver, not of a variation
    spec.update(source_expect(test))
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


def check_test(eve, test, timeout):
    """Dry run: `eve --check <test>` only checks the syntax. Exit 0 = parses; a test that
    declares "syntax_error": true in expect.json must exit 65 (syntax errors found)."""
    want = 65 if load_expect(test).get("syntax_error") else 0
    try:
        p = subprocess.run([eve, "--check", script_arg(test)], cwd=test_cwd(test), capture_output=True,
                           timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {"test": test, "verdict": "ERROR", "reason": str(e)}
    if p.returncode == want:
        return {"test": test, "verdict": "PASS", "reason": ""}
    out = (p.stdout + p.stderr).decode("utf-8", "replace").strip().splitlines()
    return {"test": test, "verdict": "FAIL",
            "reason": f"exit code {p.returncode}, expected {want}" + (f": {out[0]}" if out else "")}


def eve_args(test, exp):
    """The arguments of `eve` for a test: the script and its args, or, with "serve", a session
    that runs the command file: `eve -x -i <serve> [-t sec]` (the test file is then only the subject
    that the command file loads)."""
    if "serve" in exp:
        return ["-x", "-t", "5", "-i", exp["serve"], *exp["args"]]
    return [script_arg(test), *exp["args"]]


def is_json_expect(want):
    """A file expectation is JSON when it is an object, or a list with something other than lines."""
    return isinstance(want, dict) or (isinstance(want, list) and any(not isinstance(x, str) for x in want))


def json_match(want, got):
    """True when got has the shape of want: "*" is any value, an object may have more keys."""
    if want == "*":
        return True
    if isinstance(want, dict):
        return isinstance(got, dict) and all(k in got and json_match(v, got[k]) for k, v in want.items())
    if isinstance(want, list):
        return isinstance(got, list) and len(got) == len(want) and all(json_match(w, g) for w, g in zip(want, got))
    return want == got


def script_arg(test):
    """The script as `eve` sees it: relative to the working directory of the test."""
    return os.path.basename(test) if is_project(test) else rel(test)


def clear_out(test):
    """Empty the out/ folder of a project test, so a file found after the run is new."""
    out = os.path.join(os.path.dirname(test), "out")
    if not os.path.isdir(out):
        return
    for top, dirs, files in os.walk(out, topdown=False):
        for f in files:
            os.remove(os.path.join(top, f))
        for d in dirs:
            os.rmdir(os.path.join(top, d))


def run_test(eve, test, timeout):
    exp = load_expect(test)
    res = {"test": test, "expect": exp, "stdout": "", "stderr": "", "exit": None, "ms": 0,
           "cmd": [rel(eve) if eve.startswith(ROOT) else eve, *eve_args(test, exp)]}
    if "skip" in exp:
        res.update(verdict="SKIP", reason=exp["skip"])
        return res
    if is_project(test):
        clear_out(test)
    start = time.perf_counter()
    try:
        p = subprocess.run([eve, *eve_args(test, exp)], cwd=test_cwd(test), capture_output=True,
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
    stderr = exp.get("stderr", [])
    for text in [stderr] if isinstance(stderr, str) else stderr:
        if text not in res["stderr"]:
            problems.append(f"expected error output not found: {text!r}")
    for name, want in exp.get("files", {}).items():
        name = name.replace("{date}", datetime.datetime.now(datetime.timezone.utc).date().isoformat())
        path = os.path.join(test_cwd(test), name)
        if not os.path.isfile(path):
            problems.append(f"file not created: {name}")
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            got = f.read()
        if is_json_expect(want):
            try:
                same = json_match(want, json.loads(got))
            except ValueError:
                same = False
            if not same:
                problems.append(f"file differs (JSON): {name}")
        elif norm(got) != norm("\n".join(want) if isinstance(want, list) else want):
            problems.append(f"file differs: {name}")
    if "stdout" not in exp and not exp.get("contains") and not exp.get("syntax_error") and prints_output(test):
        problems.append("no expected output declared (/*@expect*/ block or expect.json; the test prints)")
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


BEGIN = "<!-- TESTS:BEGIN (generated by script/runtest.py, do not edit) -->"
END = "<!-- TESTS:END -->"
DESC = 45      # width of the description column of the readme list


def title_of(test):
    """First comment line at column 1 (# title or ## subtitle), or the first ** note, or ''."""
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
    """For every level folder: sync status.json and the test list of readme.md with the files on disk."""
    by_level = {}
    for res in results:
        by_level.setdefault(level_of(res["test"]), []).append(res)
    for lv in LEVELS:
        folder = os.path.join(TEST_DIR, lv)
        if os.path.isdir(folder):
            update_level(folder, by_level.get(lv, []), now)


def update_level(folder, results, now):
    status_file = os.path.join(folder, "status.json")
    state = {}
    if os.path.isfile(status_file):
        with open(status_file, encoding="utf-8") as f:
            state = json.load(f).get("tests", {})
    tests = {os.path.basename(p)[:-4]: p for p in level_tests(os.path.basename(folder))}
    state = {k: v for k, v in state.items() if k in tests}          # removed tests disappear
    for name, path in tests.items():                                # new tests are appended
        s = state.setdefault(name, {"status": "NEW", "failures": 0, "runs": 0, "checks": 0, "last": "-"})
        mtime = int(os.path.getmtime(path))
        if s.get("mtime") != mtime:        # the title is read again only when the file changed
            s["mtime"] = mtime
            s["title"] = title_of(path)
    for res in results:
        s = state[os.path.basename(res["test"])[:-4]]
        s["status"] = res["verdict"]
        s["checks"] = res.get("checks", 0)
        s["reason"] = res.get("reason", "")
        s["last"] = now
        if res["verdict"] != "SKIP":
            s["runs"] += 1
        if res["verdict"] in ("FAIL", "ERROR"):
            s["failures"] += 1
    new_json = json.dumps({"tests": dict(sorted(state.items()))}, indent=1, ensure_ascii=False) + "\n"
    if results or not os.path.isfile(status_file) or new_json != open(status_file, encoding="utf-8", newline="").read():
        with open(status_file, "w", encoding="utf-8", newline="\n") as f:
            f.write(new_json)
    update_readme(os.path.join(folder, "readme.md"), readme_block(state))


def update_readme(path, block):
    text = ""
    if os.path.isfile(path):
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
    eol = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    if BEGIN in text and END in text:
        a, b = text.index(BEGIN), text.index(END) + len(END)
        new_text = text[:a] + block + text[b:]
    else:
        new_text = text.rstrip("\n") + "\n\n## Tests\n\n" + block + "\n"
    if new_text != text:                       # the readme changes only when the list of tests changes
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(new_text.replace("\n", eol))


def wrap_desc(text, width=DESC, rows=2):
    """The description in at most `rows` lines of `width` characters, joined with <br>, cut at a space;
    what does not fit in the last line ends with '...'."""
    words = text.split()
    lines, cur = [], ""
    for w in words:
        if cur and len(cur) + 1 + len(w) > width:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + " " + w).strip()
    lines.append(cur)
    if len(lines) > rows:
        lines = lines[:rows]
        last = lines[-1]
        lines[-1] = (last[:width - 3].rstrip() if len(last) > width - 3 else last) + "..."
    return "<br>".join(l for l in lines if l)


def readme_block(state):
    """Fixed-width list of the tests of one level, with the status of the last run. The details
    (failures, runs, last run, reason) are in status.json of the folder."""
    names = sorted(state)

    def code_of(name):
        head = name.split("_")[0]
        return head if re.fullmatch(r"[a-z]\d+", head) else "-"

    rows_data = []
    for name in names:
        desc = wrap_desc(state[name].get("title", ""))
        rows_data.append((code_of(name), name, state[name].get("status", "NEW"), desc))
    heads = ("Code", "Test", "Status", "Description")
    if all(r[0] == "-" for r in rows_data):          # tests without a code (smoke): no Code column
        heads = heads[1:]
        rows_data = [r[1:] for r in rows_data]
    cols = len(heads)
    widths = [max(len(heads[i]), *(len(r[i]) for r in rows_data)) if rows_data else len(heads[i]) for i in range(cols)]

    def line(cells):
        return "| " + " | ".join(c.ljust(w) for c, w in zip(cells, widths)) + " |"

    rows = [line(heads), "|" + "|".join("-" * (w + 2) for w in widths) + "|"]
    rows += [line(r) for r in rows_data]
    count = {}
    for r in rows_data:
        count[r[-2]] = count.get(r[-2], 0) + 1
    summary = ", ".join(f"{n} {k}" for k, n in sorted(count.items()))
    return "\n".join([BEGIN, "", f"{len(state)} tests ({summary}). Failures, runs, last run and the reason of a failure "
                      "are in `status.json` of this folder.", "", *rows, "", END])


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
    ap.add_argument("--check", action="store_true",
                    help="dry run: only check the syntax of the scripts with `eve --check`, do not execute or compare "
                         "output; no reports, no status update")
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

    if args.check:
        bad = 0
        for test in tests:
            res = check_test(eve, test, args.timeout)
            bad += res["verdict"] != "PASS"
            if not args.quiet or res["verdict"] != "PASS":
                print(f"{res['verdict']:5}  {rel(test)}" + (f"  ({res['reason']})" if res["reason"] else ""))
        print(f"{label} (syntax only): {len(tests) - bad} ok, {bad} fail")
        sys.exit(1 if bad else 0)

    results = []
    for test in tests:
        res = run_test(eve, test, args.timeout)
        results.append(res)
        report = os.path.join(args.out, level_of(test), os.path.basename(test)[:-4] + ".md")
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
