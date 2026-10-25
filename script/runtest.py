"""Run Eve conformance tests on an Eve implementation and track the results in JSON.

usage: python script/runtest.py TARGET... [--eve PATH] [--timeout SEC] [--out DIR] [-q] [--repeat N]

--repeat N runs every test N times and keeps the first run that fails: a test of parallel work must
give the same output at every run (spec/semantics/multitasking.md#determinism, D-144).

TARGET is one of:
  1 | level1          every test in test/level1 (likewise 2 to 7)
  smoke               every test in test/smoke (the tools of the VM: slot, workflow)
  all                 every level, and smoke
  bytecode            the bytecode special tests, test/bytecode: they run on the bytecode machine (EVE_ENGINE=bc);
                      never part of `all` (`python script/bctest.py` runs them too)
  scaffold            the special test of `project init` and `project new` (test/scaffold/run.sh,
                      a shell script on real folders); run on its own, never part of `all`
  a03 | a03_print     one test, by name or name prefix, searched in every level
  test/level1/a03_print.eve
                      one test, by path

A test is either a file or a folder:
  test/levelN/<name>.eve          a single script; its expectations are JSON in comment blocks of
                                  the script itself, /*@expect { "stdout": [...] } */ (D-094); the
                                  old expect.json of the level, {"<name>": {...}}, is still read
                                  and the blocks of the script override it
  test/levelN/<name>/<name>.eve   a project test (D-073): the folder is a whole Eve project, with
                                  the primary aspect <name>.eve and any of asp/, lib/, web/ (templates), data/, out/. Its
                                  expectations are in <name>/expect.json: {...} (one object).
                                  It runs with the folder as working directory, so paths in the
                                  project are relative to it; out/ is emptied before each run.
  test/levelN/<name>/<code>_test1.eve, <code>_test2.eve, ...
                                  more primary aspects of the same project (D-133): each one is a variation
                                  (another use case) of the same asp/, lib/ and data/. <code> is the
                                  code of the folder (b05 for b05_apply_spread). Each file is a test
                                  of its own, with its expectations in its /*@expect*/ block; the
                                  aspect inside is named like the file. `runtest.py b05` runs the
                                  main file of the project and its variations, `runtest.py b05_test2` one of them.
Other folders are not tests. The expectation keys, all optional:
  "exit"       expected exit code (default 0)
  "args"       command-line arguments
  "client"     with "command": the command starts a machine that keeps running; the client (a list: a program and its
               arguments) runs in the same folder with the variable EVE set to the VM; stdout = the output of the
               client, exit = the exit code of the machine, which must end by itself (F-NET-02)
  "command"    a list of arguments for `eve` alone, with no script: the test runs one command of the
               VM, `eve <command...>` (for example ["--project", "init", "out/proj"]); the file of
               the test is only its home and its expectations
  "stdout"     the exact expected output: a string, or a list of lines (line
               endings and trailing white space at the end are ignored)
               A line may hold the placeholders {Integer}, {Real}, {Logic}, {String}, {Any}: any value of that type
               (for a generator that is not seeded, library random).
  "contains"   a list of strings that must all appear in the output
  "stdin"      the standard input of the script: a string, or a list of lines (default: empty, never the terminal)
  "stderr"     a list of strings that must all appear in the error output
  "files"      project tests: {"out/report.txt": "text" or [lines]}: each file must exist
               after the run with this content (line endings and trailing white space ignored).
               A value that is an object, or a list that holds objects, is JSON: the file is
               parsed and must match it (an object may have more keys; "*" matches any value).
               "{date}" in a file name is the date of the run in UTC, YYYY-MM-DD (D-114)
  "bytes"      {"out/x.csv": "text"}: each file must hold exactly these bytes, the UTF-8 of the
               text: line endings (\r\n), a BOM (\ufeff) and trailing spaces count
  "timeout"    seconds before the run is cancelled (default: the option --timeout)
  "skip"       a reason: the test is not run
  "note"       free text
A test that prints (a `print` or `write` statement) must declare "stdout" or
"contains": otherwise it FAILS with "no expected output declared". An expected
output that is not found in the real output makes the test FAIL. A legacy
<name>.out file is still read when expect.json has no "stdout" for the test.

A file test runs as `<eve> test/levelN/<name>.eve [args]` from the repo root; a project test
runs as `<eve> <name>.eve [args]` from its folder.
Verdicts: PASS, FAIL (wrong exit code or stdout), ERROR (timeout, eve missing),
SKIP. Reports are JSON in temp/output/ (git-ignored) and exist only for what needs a look: a test that
fails or errors gets `<level>/<name>.json` (command, exit codes, stdout, stderr, expected output, diff; the
diff is also printed when one test is run), and a run of more than one test gets `<targets>.json` (the
verdict, exit code and time of every test). A test that passes leaves no file.
Exit status: 0 when nothing failed or errored.

After every run the tracking file of each suite, test/<suite>/<suite>.json (script/testtrack.py), is
updated: for every test file its status, failed runs, failed checks, reason and date of the last run, title
and the spec features it covers (`features`, written by hand, kept by the runner). A new test is added as
NEW and a deleted one is removed. Use --no-update to leave these files alone.

--check is a dry run for syntax errors: `eve --check <test>` must exit 0 (65 when expect.json
declares "syntax_error": true). Nothing is executed, written or recorded in the tracking files.

--eve defaults to $EVE, else bin/eve.exe (Windows) or bin/eve.
"""
import argparse
import datetime
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

import testtrack
from _common import die

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_DIR = os.path.join(ROOT, "test")
LEVELS = ("level1", "level2", "level3", "level4", "level5", "level6", "level7", "smoke", "bytecode")
# Process exit codes, design/decision/level1.md D-010.
EXIT_MEANING = {0: "normal", 1: "abnormal exit", 2: "error", 3: "warning", 70: "VM not implemented"}


def exit_label(code):
    return "-" if code is None else f"{code} {EXIT_MEANING.get(code, '')}".strip()


def rel(path):
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


VARIATION = re.compile(r"^([a-z]\d+)_test\d+\.eve$")


def natural(name):
    """Sort key of a test or a folder: e9 before e10 before e100 (letters, then the number, then the rest)."""
    m = re.match(r"([a-z]+)(\d+)(.*)", os.path.basename(name))
    return (m.group(1), int(m.group(2)), m.group(3)) if m else (name, 0, "")


def variations(folder, name):
    """The variation files of a project folder (D-133): <code>_test1.eve, <code>_test2.eve, ..."""
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
    for f in sorted(os.listdir(folder), key=natural):
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
        # the main file of a project brings its variations along (D-133); a variation runs alone
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
    if t == "bytecode":
        return t, level_tests(t)
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
            spec = {}          # expect.json is the expectation of the main file of the project, not of a variation
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


PLACEHOLDERS = {
    "Integer": r"-?\d+",
    "Real": r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?",
    "Logic": r"True|False",
    "String": r".*",
    "Any": r".*",
}


PLACEHOLDER_RE = re.compile(r"\{(?:" + "|".join(PLACEHOLDERS) + r")\}")


def same_output(actual, expected):
    """Equal text, or equal line by line when a line of `expected` holds a placeholder {Integer}, {Real}, {Logic}, {String}
    or {Any}: the value of an unseeded generator is not known, its type is (library random)."""
    actual, expected = norm(actual), norm(expected)
    if actual == expected:
        return True
    pat = re.compile(r"\{(" + "|".join(PLACEHOLDERS) + r")\}")
    if not pat.search(expected):
        return False
    a, e = actual.split("\n"), expected.split("\n")
    if len(a) != len(e):
        return False
    for got, want in zip(a, e):
        if got == want:
            continue
        parts = pat.split(want)  # text, name, text, name, ...
        rx = "".join(re.escape(x) if k % 2 == 0 else PLACEHOLDERS[x] for k, x in enumerate(parts))
        if not re.fullmatch(rx, got):
            return False
    return True


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
    """The arguments of `eve` for a test: the script and its args, or the command of "command"."""
    if "command" in exp:
        return list(exp["command"])
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
    """Empty the out/ and data/out/ folders of a project test, so a file found after the run is new.
    The .gitkeep at the top of a folder (it keeps the empty folder in git) stays."""
    for sub in ("out", os.path.join("data", "out")):
        out = os.path.join(os.path.dirname(test), sub)
        if not os.path.isdir(out):
            continue
        for top, dirs, files in os.walk(out, topdown=False):
            for f in files:
                if f != ".gitkeep" or top != out:
                    os.remove(os.path.join(top, f))
            for d in dirs:
                os.rmdir(os.path.join(top, d))


def run_with_client(eve, test, exp, timeout):
    """A test with a "client" (F-NET-02): "command" starts a machine that keeps running, the client (a program
    such as `node check/x.js`) runs in the same folder with the variable EVE set to the VM and talks to the machine.
    The result looks like a run of one process: stdout is the output of the client, the exit code is the one of the
    machine (it must end by itself, for example after `eve --serve stop`); a client that fails makes the exit code
    99, and a machine still running after the client ended is killed and makes the exit code 98."""
    cwd = test_cwd(test)
    env = dict(os.environ, EVE=eve)
    with tempfile.TemporaryFile() as sout, tempfile.TemporaryFile() as serr:
        server = subprocess.Popen([eve, *eve_args(test, exp)], cwd=cwd, stdout=sout, stderr=serr, env=env)
        try:
            client = subprocess.run(exp["client"], cwd=cwd, capture_output=True, timeout=timeout, env=env)
            try:
                code = server.wait(timeout=10)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
                code = 98
            if client.returncode != 0:
                code = 99
        finally:
            if server.poll() is None:
                server.kill()
                server.wait()
        serr.seek(0)
        err = client.stderr + serr.read()
    return subprocess.CompletedProcess(exp["client"], code, client.stdout, err)


def run_test(eve, test, timeout):
    exp = load_expect(test)
    timeout = exp.get("timeout", timeout)
    res = {"test": test, "expect": exp, "stdout": "", "stderr": "", "exit": None, "ms": 0,
           "cmd": [rel(eve) if eve.startswith(ROOT) else eve, *eve_args(test, exp)]}
    if "skip" in exp:
        res.update(verdict="SKIP", reason=exp["skip"])
        return res
    if is_project(test):
        clear_out(test)
    start = time.perf_counter()
    try:
        if "client" in exp:
            p = run_with_client(eve, test, exp, timeout)
        else:
            # the tests of test/bytecode run on the bytecode machine, all the others on the tree walker
            env = dict(os.environ, EVE_ENGINE="bc") if level_of(test) == "bytecode" else None
            if exp.get("env"):
                env = dict(env or os.environ, **exp["env"])
            feed = exp.get("stdin")
            if feed is not None:
                text = chr(10).join(feed) + chr(10) if isinstance(feed, list) else feed
                feed = {"input": text.encode("utf-8")}
            else:
                feed = {"stdin": subprocess.DEVNULL}
            p = subprocess.run([eve, *eve_args(test, exp)], cwd=test_cwd(test), capture_output=True,
                               timeout=timeout, env=env, **feed)
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
    if "stdout" in exp and not same_output(res["stdout"], exp["stdout"]):
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
    for name, want in exp.get("bytes", {}).items():
        path = os.path.join(test_cwd(test), name)
        if not os.path.isfile(path):
            problems.append(f"file not created: {name}")
            continue
        with open(path, "rb") as f:
            if f.read() != want.encode("utf-8"):
                problems.append(f"file bytes differ: {name}")
    if "stdout" not in exp and not exp.get("contains") and not exp.get("syntax_error") and prints_output(test):
        problems.append("no expected output declared (/*@expect*/ block or expect.json; the test prints)")
    res["verdict"] = "FAIL" if problems else "PASS"
    res["reason"] = "; ".join(problems)
    res["checks"] = len(problems)
    return res


def lines_of(text):
    return text.replace("\r\n", "\n").rstrip("\n").split("\n") if text else []


def failure_report(res):
    """The report of a test that did not pass: a JSON object with what a person needs to see (no source, the
    test file is where it is). A passing test has no report."""
    exp = res["expect"]
    rep = {"test": rel(res["test"]), "verdict": res["verdict"], "reason": res["reason"],
           "command": " ".join(res["cmd"]), "exit": res["exit"], "expected_exit": exp["exit"], "ms": res["ms"],
           "stdout": lines_of(res["stdout"]), "stderr": lines_of(res["stderr"])}
    if "stdout" in exp:
        rep["expected_stdout"] = lines_of(norm(exp["stdout"]))
        if "stdout differs" in res["reason"]:
            rep["diff"] = list(difflib.unified_diff(norm(exp["stdout"]).split("\n"), norm(res["stdout"]).split("\n"),
                                                    "expected", "actual", lineterm=""))
    return rep


def write_report(res, out):
    """temp/output/<level>/<name>.json for a test that failed; the old report of a test that passes is removed."""
    path = os.path.join(out, level_of(res["test"]), os.path.basename(res["test"])[:-4] + ".json")
    if res["verdict"] in ("PASS", "SKIP"):
        if os.path.isfile(path):
            os.remove(path)
        return None
    write(path, json.dumps(failure_report(res), indent=1, ensure_ascii=False))
    return path


def print_diff(res, limit=30):
    """The diff of a failed test on the console, so that a single run needs no report file."""
    rep = failure_report(res)
    shown = rep.get("diff") or []
    for line in shown[:limit]:
        print("      " + line)
    if len(shown) > limit:
        print(f"      ... {len(shown) - limit} more lines in the report")
    if not shown and rep["stderr"] and res["verdict"] != "PASS":
        for line in rep["stderr"][:6]:
            print("      stderr: " + line)


def eve_version(eve):
    try:
        p = subprocess.run([eve, "--version"], capture_output=True, timeout=10)
        return p.stdout.decode("utf-8", "replace").strip() or "-"
    except (OSError, subprocess.TimeoutExpired):
        return "not available"


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
    """For every suite folder: sync test/<suite>/<suite>.json with the files on disk and the results of the run.
    Prints one line with the difference to the tracking files (S15.1)."""
    by_level = {}
    for res in results:
        by_level.setdefault(level_of(res["test"]), []).append(res)
    changed, added, removed = [], 0, 0
    for lv in LEVELS:
        if os.path.isdir(os.path.join(TEST_DIR, lv)):
            c, a, r = update_level(lv, by_level.get(lv, []), now)
            changed += c
            added += a
            removed += r
    refresh_pages()
    print(f"tracking: {len(changed)} changed, {added} new, {removed} removed")
    for c in changed[:20]:
        print("  " + c)


def refresh_pages():
    """The tutorial pages of the tests follow the tests (genpages.py, D-136)."""
    try:
        import genpages
        for p in genpages.generate():
            print("genpages: " + rel(p))
    except Exception as e:          # the tutorial may be missing: the run itself is not affected
        print(f"genpages: not updated ({e})")


def update_level(suite, results, now):
    """-> (the status changes as 'name: old -> new', the number of new tests, the number of removed tests)."""
    doc = testtrack.load(suite)
    before = {x["name"]: x["status"] for x in doc.get("tests", [])}
    found = {os.path.basename(p)[:-4]: (lambda p=p: title_of(p), int(os.path.getmtime(p))) for p in level_tests(suite)}
    state = testtrack.sync(doc, found)
    for res in results:
        entry = state[os.path.basename(res["test"])[:-4]]
        testtrack.record(entry, res["verdict"], res.get("checks", 0), res.get("reason", ""), now)
    testtrack.save(doc)
    changed = [f"{suite}/{n}: {before[n]} -> {e['status']}" for n, e in state.items() if n in before and before[n] != e["status"]]
    return changed, sum(n not in before for n in state), sum(n not in state for n in before)


def run_scaffold(eve, now, update):
    """The special test of `project init` and `project new` (test/scaffold/): a shell script on real folders.
    Its verdict is the last line of its output; it is recorded in test/scaffold/scaffold.json as one test."""
    script = os.path.join(ROOT, "test", "scaffold", "run.sh")
    p = subprocess.run(["sh", script, eve], capture_output=True)
    out = p.stdout.decode("utf-8", "replace")
    print(out + p.stderr.decode("utf-8", "replace"), end="")
    failed = [l[5:].strip() for l in out.splitlines() if l.startswith("FAIL:")]
    if update:
        doc = testtrack.load("scaffold")
        state = testtrack.sync(doc, {"scaffold": (lambda: "project init and project new on real folders", int(os.path.getmtime(script)))})
        testtrack.record(state["scaffold"], "PASS" if p.returncode == 0 else "FAIL", len(failed), "; ".join(failed), now)
        testtrack.save(doc)
    return p.returncode


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text if text.endswith("\n") else text + "\n")


def run_both(eve, test, timeout):
    """Run a test on the tree walker and on the bytecode machine (EVE_ENGINE=bc). The test passes when both pass and agree."""
    saved = os.environ.pop("EVE_ENGINE", None)
    try:
        tree = run_test(eve, test, timeout)
        os.environ["EVE_ENGINE"] = "bc"
        bc = run_test(eve, test, timeout)
    finally:
        os.environ.pop("EVE_ENGINE", None)
        if saved is not None:
            os.environ["EVE_ENGINE"] = saved
    res = tree
    res["ms_bc"] = bc["ms"]
    if tree["verdict"] != "PASS":
        return res
    problems = []
    if bc["verdict"] != "PASS":
        problems.append("bytecode machine: " + (bc["reason"] or bc["verdict"]))
    else:
        if bc["exit"] != tree["exit"]:
            problems.append(f"exit codes differ: tree {tree['exit']}, bytecode {bc['exit']}")
        # both engines passed the expectation; with a placeholder {Type} the two outputs may differ in the value
        if bc["stdout"] != tree["stdout"] and not PLACEHOLDER_RE.search(str(tree["expect"].get("stdout", ""))):
            problems.append("the output differs")
        if norm(bc["stderr"]) != norm(tree["stderr"]):
            problems.append("the error output differs")
    if problems:
        res["verdict"] = "FAIL"
        res["reason"] = "; ".join(problems)
        res["stdout"] = tree["stdout"] + "\n--- bytecode machine ---\n" + bc["stdout"]
    return res


def prepare_path(eve):
    """The tests start `eve` and `python` by name: the folder of the machine under test comes first on PATH (not the
    installed one), and a `python` that is only `python3` (Linux) gets a link in temp/shim."""
    parts = [os.path.dirname(eve)] if os.path.isabs(eve) else []
    if not shutil.which("python"):
        shim = os.path.join(ROOT, "temp", "shim")
        os.makedirs(shim, exist_ok=True)
        link = os.path.join(shim, "python")
        if not os.path.lexists(link):
            os.symlink(sys.executable, link)
        parts.append(shim)
    os.environ["PATH"] = os.pathsep.join(parts + [os.environ.get("PATH", "")])


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
                    help="do not update the tracking files test/<suite>/<suite>.json")
    ap.add_argument("--repeat", type=int, default=1, metavar="N",
                    help="run every test N times; a test passes only when every run passes (determinism, D-144)")
    ap.add_argument("--engine", choices=["tree", "bc"], default="tree",
                    help="the engine of the VM: tree (the reference, default) or bc (the bytecode machine, design/design-bytecode.md); "
                         "a bc run writes its reports to temp/output-bc and never updates the tracking files or the tutorial pages")
    ap.add_argument("--both", action="store_true",
                    help="run every test on the tree walker and on the bytecode machine: both must pass and give the same exit code, "
                         "output and error output (the reports go to temp/output-both; the tracking files are not updated)")
    args = ap.parse_args()
    if args.both:
        args.no_update = True
        if args.out == os.path.join(ROOT, "temp", "output"):
            args.out = os.path.join(ROOT, "temp", "output-both")
    elif args.engine == "bc":
        os.environ["EVE_ENGINE"] = "bc"
        args.no_update = True
        if args.out == os.path.join(ROOT, "temp", "output"):
            args.out = os.path.join(ROOT, "temp", "output-bc")
    eve = os.path.abspath(args.eve) if os.path.exists(args.eve) else args.eve
    prepare_path(eve)
    version = eve_version(eve)

    if args.targets == ["scaffold"]:
        # The special test (test/scaffold/): a shell script, with its own verdict, recorded in scaffold.json.
        sys.exit(run_scaffold(eve, f"{datetime.datetime.now():%Y-%m-%d %H:%M}", not args.no_update))

    labels, tests = [], []
    for target in args.targets:
        label, found = resolve(target)
        labels.append(label)
        tests += [t for t in found if t not in tests]
    label = "-".join(labels)
    if len(label) > 60:
        label = label[:50] + "-etc"   # a long list of tests would be a file name too long for the system
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
        if args.both:
            res = run_both(eve, test, args.timeout)
        else:
            res = run_test(eve, test, args.timeout)
            for k in range(2, max(args.repeat, 1) + 1):
                if res["verdict"] != "PASS":
                    break
                again = run_test(eve, test, args.timeout)
                if again["verdict"] != "PASS":
                    again["reason"] = f"run {k} of {args.repeat}: {again['reason']}"
                    res = again
        results.append(res)
        res["report"] = write_report(res, args.out)
        if res["verdict"] != "PASS" or not args.quiet:
            print(f"{res['verdict']:5}  {rel(test)}" + (f"  ({res['reason']})" if res["reason"] else ""))
        if res["verdict"] in ("FAIL", "ERROR") and len(tests) == 1:
            print_diff(res)

    now = f"{datetime.datetime.now():%Y-%m-%d %H:%M}"
    if not args.no_update:
        update_status(results, now)
    counts = {v: sum(r["verdict"] == v for r in results) for v in ("PASS", "FAIL", "ERROR", "SKIP")}
    tally = ", ".join(f"{n} {v.lower()}" for v, n in counts.items())
    failed = counts["FAIL"] or counts["ERROR"]
    if len(results) == 1:
        where = f"  -> {rel(results[0]['report'])}" if results[0]["report"] else ""
        print(f"{label}: {tally}{where}")
        sys.exit(1 if failed else 0)
    summary_path = os.path.join(args.out, label + ".json")
    rows = ",\n".join("  " + json.dumps({"test": os.path.basename(r["test"])[:-4], "verdict": r["verdict"], "exit": r["exit"],
                                         "ms": r["ms"], "reason": r["reason"], "report": rel(r["report"]) if r["report"] else None},
                                        ensure_ascii=False) for r in results)
    head = json.dumps({"run": label, "date": now, "eve": rel(eve) if eve.startswith(ROOT) else eve, "version": version,
                       "counts": counts}, ensure_ascii=False)
    write(summary_path, head[:-1] + ', "results": [\n' + rows + "\n]}")
    print(f"{label}: {tally}  -> {rel(summary_path)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
