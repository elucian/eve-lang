"""Run a test level through ONE Eve VM session driven over the stdio door, then read the reports.

usage: python script/workflow.py TARGET... [--eve PATH] [--out DIR] [--ast-depth N] [--timeout SEC]

TARGET is the same as for runtest.py (1, level1, all, a03, test/level1/a03_print.eve).

The workflow talks to one machine, `eve --stdio` (JSON-RPC 2.0, one message per line; the command
files `.vmc` and `eve -i` are gone, D-188):

  1. this script opens a session (`vm.open`) and sends, for every test, the lines
         load <test>, parse, run, errors, ast <depth>, inspect, status
     each as one `vm.eval`; it keeps them in DIR/<label>.commands for reading;
  2. the machine is started once: one process for the whole level. It feeds on one file at a time,
     parses it, executes the syntax tree, logs the errors and writes the reports of the file in
     DIR/<label>/: <name>.out (what the script printed), <name>.err (errors), <name>.ast (the
     syntax tree), <name>.inspect (introspection: node counts, declarations, globals), and one
     line per file in summary.log;
  3. `vm.stop` ends the machine. Only then does this script read the reports: it
     compares exit code and output with test/levelN/expect.json (as runtest.py does) and writes
     DIR/<label>.report.md; for every failing test it quotes the errors and the introspection,
     and names the .ast file to open.

Exit status: 0 when every test passed, 1 otherwise, 2 when the session itself failed.
"""
import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import runtest as rt  # noqa: E402  (same folder)
from _common import die  # noqa: E402


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def summary_rows(path):
    """{name: {key: value}} from summary.log (tab separated, `name key=value ...`)."""
    rows = {}
    for line in (read(path) or "").splitlines():
        parts = line.split("\t")
        if len(parts) < 2 or "=" not in parts[1]:
            continue  # a `log` line
        rows[parts[0]] = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
    return rows


def judge(test, row, folder):
    """Return (verdict, [problems]) for one test from its reports."""
    name = os.path.basename(test)[:-4]
    exp = rt.load_expect(test)
    if "skip" in exp:
        return "SKIP", [exp["skip"]]
    if exp["args"] or "command" in exp:
        return "SKIP", ["the test needs command line arguments: run it with runtest.py"]
    if row is None:
        return "ERROR", ["the session did not log this test (see the session log)"]
    problems = []
    if row.get("parse") != "ok":
        if not (row.get("parse") == "FAIL" and exp["exit"] == 65):  # a test of a syntax error expects the parse to fail
            problems.append(f"parse {row.get('parse')}")
    elif row.get("run") in (None, "-"):
        problems.append("not executed")
    else:
        code = int(row["run"])
        if code != exp["exit"]:
            problems.append(f"exit code {code}, expected {exp['exit']}")
        out = read(os.path.join(folder, name + ".out")) or ""
        if "stdout" in exp and rt.norm(out) != rt.norm(exp["stdout"]):
            problems.append("stdout differs")
        for text in exp.get("contains", []):
            if text not in out:
                problems.append(f"expected output not found: {text!r}")
    return ("FAIL" if problems else "PASS"), problems


def run_session(eve, lines, log_path, timeout):
    """Start `eve --stdio`, open a session, send each line as `vm.eval`, stop. Returns 0, or 2 when the session failed."""
    try:
        p = subprocess.Popen([eve, "--stdio"], cwd=rt.ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace")
    except OSError as e:
        die(f"cannot start the machine: {e}")
    log, ids = [], iter(range(1, 1 << 30))

    def call(method, params=None):
        n = next(ids)
        p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params or {}}) + "\n")
        p.stdin.flush()
        while True:  # notifications (no id) are skipped; the answer has our id
            line = p.stdout.readline()
            if not line:
                raise RuntimeError("the machine ended")
            msg = json.loads(line)
            if msg.get("id") == n:
                if "error" in msg:
                    raise RuntimeError(msg["error"].get("message", "error"))
                return msg.get("result")

    status = 0
    try:
        session = call("vm.open", {"cwd": rt.ROOT})["session"]
        for line in lines:
            r = call("vm.eval", {"session": session, "line": line})
            log.append(f"> {line}\n{(r or {}).get('output', '')}")
        call("vm.stop")
    except (RuntimeError, ValueError, OSError, KeyError, TypeError) as e:
        log.append(f"--- the session failed: {e}")
        status = 2
    try:
        p.stdin.close()
        p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        status = 2
    with open(log_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(log) + "\n")
    return status


def head(text, n=12):
    lines = (text or "").replace("\r\n", "\n").rstrip("\n").splitlines()
    more = f"\n... {len(lines) - n} more lines" if len(lines) > n else ""
    return "\n".join(lines[:n]) + more


def main():
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="+", metavar="TARGET")
    default_eve = os.path.join(rt.ROOT, "bin", "eve.exe" if os.name == "nt" else "eve")
    ap.add_argument("--eve", default=os.environ.get("EVE", default_eve))
    ap.add_argument("--out", default=os.path.join(rt.ROOT, "temp", "workflow"))
    ap.add_argument("--ast-depth", type=int, default=6)
    ap.add_argument("--timeout", type=int, default=60, help="seconds a single command may take")
    args = ap.parse_args()

    labels, tests = [], []
    for target in args.targets:
        label, found = rt.resolve(target)
        labels.append(label)
        tests += [t for t in found if t not in tests]
    label = "-".join(labels)
    if not tests:
        die(f"no tests in {label}")

    out = os.path.abspath(args.out)
    folder = os.path.join(out, label)
    os.makedirs(folder, exist_ok=True)
    for old in os.listdir(folder):  # reports of a previous session
        os.remove(os.path.join(folder, old))
    cmd_path = os.path.join(out, label + ".commands")
    rel_folder = rt.rel(folder) if folder.startswith(rt.ROOT) else folder

    lines = [f"outdir {rel_folder}", "capture on", f"log == {label} =="]
    for t in tests:
        lines += [f"load {rt.rel(t)}", "parse", "run", "errors", f"ast {args.ast_depth}", "inspect", "status"]
    lines += [f"log == end of {label} =="]
    with open(cmd_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    session_log = os.path.join(out, label + ".session.log")
    print(f"session: eve --stdio, {len(lines)} commands ({len(tests)} tests)")
    status = run_session(args.eve, lines, session_log, args.timeout)
    if status != 0:
        print(f"the session ended with status {status}; see {session_log}")

    # The machine has stopped: now the reports can be read.
    rows = summary_rows(os.path.join(folder, "summary.log"))
    verdicts, report = [], []
    for t in tests:
        name = os.path.basename(t)[:-4]
        verdict, problems = judge(t, rows.get(name), folder)
        verdicts.append((name, verdict, problems))
        print(f"{verdict:5}  {rt.rel(t)}" + (f"  ({'; '.join(problems)})" if problems else ""))
    n = {v: sum(1 for _, x, _ in verdicts if x == v) for v in ("PASS", "FAIL", "ERROR", "SKIP")}
    summary = f"{label}: {n['PASS']} pass, {n['FAIL']} fail, {n['ERROR']} error, {n['SKIP']} skip"
    print(summary)

    report += [f"# Workflow {label}", "", summary, "",
               f"Commands: `{rt.rel(cmd_path) if cmd_path.startswith(rt.ROOT) else cmd_path}`; "
               f"session log: `{os.path.basename(session_log)}`; reports: `{os.path.basename(folder)}/`.", "",
               "| Test | Verdict | Steps | Errors | Reason |", "|---|---|---|---|---|"]
    for name, verdict, problems in verdicts:
        row = rows.get(name) or {}
        report.append(f"| {name} | {verdict} | {row.get('steps', '-')} | {row.get('errors', '-')} | {'; '.join(problems)} |")
    for name, verdict, problems in verdicts:
        if verdict not in ("FAIL", "ERROR"):
            continue
        report += ["", f"## {name}: {verdict}", "", "; ".join(problems), ""]
        for ext, title in (("err", "Errors"), ("out", "Output"), ("inspect", "Introspection")):
            text = read(os.path.join(folder, f"{name}.{ext}"))
            if text:
                report += [f"**{title}** (`{os.path.basename(folder)}/{name}.{ext}`)", "", "```text", head(text), "```", ""]
        report.append(f"Syntax tree: `{os.path.basename(folder)}/{name}.ast`")
    with open(os.path.join(out, label + ".report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report) + "\n")
    sys.exit(0 if n["FAIL"] == 0 and n["ERROR"] == 0 else (2 if status != 0 else 1))


if __name__ == "__main__":
    main()
