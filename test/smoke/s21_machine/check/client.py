"""Client of the smoke test s21: talks to the machine that the runner started with `eve --listen`, and to `eve --stdio`."""
import json
import os
import subprocess
import sys
import time

EVE = os.environ.get("EVE", "eve")
failed = []


def check(ok, text):
    print(("ok " if ok else "FAIL ") + text)
    if not ok:
        failed.append(text)


def eve(*args):
    return subprocess.run([EVE, *args], capture_output=True, text=True, timeout=20)


# 1. the IPC door of the machine started by the runner
for _ in range(100):
    if eve("--listen", "status").returncode == 0:
        break
    time.sleep(0.1)
check(eve("--listen", "status").returncode == 0, "the machine answers")
r = eve("-loc", "s21_machine.eve")
check(r.returncode == 0 and r.stdout.strip() == "sum 55", "-loc runs the script on the machine: %s" % r.stdout.strip())

# 2. the stdio door: a machine of its own, JSON-RPC one message per line (D-188 replaces the command files)
p = subprocess.Popen([EVE, "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
ids = iter(range(1, 100))


def call(method, params=None):
    n = next(ids)
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n, "method": method, "params": params or {}}) + "\n")
    p.stdin.flush()
    while True:
        msg = json.loads(p.stdout.readline())
        if msg.get("id") == n:
            return msg.get("result")


check(call("vm.ping") == "pong", "the stdio door: pong")
session = call("vm.open", {"cwd": os.getcwd()})["session"]
out = call("vm.eval", {"session": session, "line": "run s21_machine.eve"})["output"]
check("sum 55" in out, "vm.eval runs session commands: %s" % out.strip().splitlines()[-1])
call("vm.stop")
p.stdin.close()
p.wait(timeout=10)

# 3. stop the machine of the runner
check(eve("--listen", "stop").returncode == 0, "--listen stop ends with 0")
print("machine: all checks passed" if not failed else "machine: %d check(s) failed" % len(failed))
sys.exit(1 if failed else 0)
