"""Run Eve conformance tests on an Eve implementation and write Markdown reports.

usage: python script/runtest.py TARGET... [--eve PATH] [--timeout SEC] [--out DIR] [-q]

TARGET is one of:
  1 | level1          every test in test/level1 (likewise 2, 3)
  all                 every level
  a03 | a03-print     one test, by name or name prefix, searched in every level
  test/level1/a03-print.eve
                      one test, by path

A test is a `*.eve` file directly inside test/levelN/ (subfolders hold level-2
aspects and are not run on their own). Its expectations, all optional:
  <name>.out          exact expected stdout (line endings and trailing
                      whitespace at the end are ignored)
  expect.json         per level: {"<name>": {"exit": 1, "args": [...],
                      "skip": "reason"}}; default exit code is 0

Each test runs as `<eve> test/levelN/<name>.eve [args]` from the repo root.
Verdicts: PASS, FAIL (wrong exit code or stdout), ERROR (timeout, eve missing),
SKIP. Reports go to temp/output/ (git-ignored): one `<level>/<name>.md` per
test, plus a summary `<targets>.md` when a run has more than one test.
Exit status: 0 when nothing failed or errored.

--eve defaults to $EVE, else bin/eve.exe (Windows) or bin/eve.
"""
import argparse
import datetime
import difflib
import json
import os
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
    out = os.path.join(folder, name + ".out")
    if os.path.isfile(out):
        with open(out, encoding="utf-8") as f:
            spec["stdout"] = f.read()
    spec.setdefault("exit", 0)
    spec.setdefault("args", [])
    return spec


def norm(text):
    return text.replace("\r\n", "\n").rstrip()


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
    res["verdict"] = "FAIL" if problems else "PASS"
    res["reason"] = "; ".join(problems)
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
