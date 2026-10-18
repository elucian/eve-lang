"""Tests of the service mode of eve (`eve -s`, design-service.md section 17).

What it checks, without a person at a terminal:
  1. `eve -s file.cfg` ends with status 0 and prints nothing, and the machine answers on both doors;
  2. a second `eve -s file.cfg` says "already running" on the error output and ends with a status other than 0;
  3. `eve --serve stop` stops it, and the log file of the machine exists;
  4. with EVE_SERVICE=foreground the process itself is the machine: silent, a pid file that holds its pid, a clean stop;
  5. on POSIX systems SIGTERM stops the foreground machine with status 0;
  6. on Windows, when the user is an administrator: the Service Control Manager installs, starts, stops and removes it.

usage: python script/service_check.py [--eve bin/eve.exe]

Runs in `temp/service_check/`, with ports 4421 and 8421 and its own runtime folder. Exit status 0 when all the checks pass.
"""
import argparse
import ctypes
import os
import shutil
import signal
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, 'temp', 'service_check')
failures = []


def check(ok, what):
    print(('ok   ' if ok else 'FAIL ') + what)
    if not ok:
        failures.append(what)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--eve', default=os.path.join(ROOT, 'bin', 'eve.exe'))
    args = ap.parse_args()
    eve = os.path.abspath(args.eve)
    shutil.rmtree(WORK, ignore_errors=True)
    run = os.path.join(WORK, 'run')
    os.makedirs(os.path.join(WORK, 'web'))
    os.makedirs(run)
    with open(os.path.join(WORK, 'web', 'index.html'), 'w') as f:
        f.write('<h1>service</h1>')
    with open(os.path.join(WORK, 'eve.cfg'), 'w') as f:
        f.write('domain = "localhost"\nipc_port = 4421\nhttp_port = 8421\nweb = "web"\n')
    env = dict(os.environ, TMPDIR=run, TEMP=run, XDG_RUNTIME_DIR=run)
    env.pop('EVE_SERVICE', None)

    def eve_run(*a, extra=None):
        e = dict(env, **(extra or {}))
        return subprocess.run([eve, *a], capture_output=True, text=True, cwd=WORK, env=e, timeout=60)

    def status():
        return eve_run('--serve', 'status', '-e', 'eve.cfg')

    def wait_status(up, seconds=10):
        end = time.time() + seconds
        while time.time() < end:
            if (status().returncode == 0) == up:
                return True
            time.sleep(0.2)
        return False

    # 1. start from a console
    p = eve_run('-s', 'eve.cfg')
    check(p.returncode == 0 and p.stdout == '' and p.stderr == '', 'eve -s eve.cfg: status 0 and silent (stdout=%r stderr=%r)' % (p.stdout, p.stderr))
    check(wait_status(True), 'the machine answers after eve -s')
    st = status().stdout
    check('ipc: listening' in st and 'http: listening' in st, 'both doors are open: %s' % st.splitlines()[1:3])
    # 2. a second start
    p = eve_run('-s', 'eve.cfg')
    check(p.returncode != 0 and 'already running' in (p.stdout + p.stderr), 'a second eve -s says already running (status %d): %s' % (p.returncode, (p.stdout + p.stderr).strip()))
    # 3. stop
    p = eve_run('--serve', 'stop', '-e', 'eve.cfg')
    check(p.returncode == 0, 'eve --serve stop ends the machine')
    check(wait_status(False), 'and nobody answers afterwards')
    log = os.path.join(run, 'eve-localhost-4421.log')
    check(os.path.exists(log) and 'ipc localhost:4421' in open(log).read(), 'the log file of the machine exists and names the door')

    # 4. the foreground form
    pid_file = os.path.join(run, 'eve-localhost-4421.pid')
    fg = subprocess.Popen([eve, '-s', 'eve.cfg'], cwd=WORK, env=dict(env, EVE_SERVICE='foreground'), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    check(wait_status(True), 'EVE_SERVICE=foreground: this process is the machine and it answers')
    time.sleep(0.3)
    check(os.path.exists(pid_file) and open(pid_file).read().strip() == str(fg.pid), 'the pid file holds the pid of the process: %s' % (open(pid_file).read().strip() if os.path.exists(pid_file) else 'missing'))
    if os.name == 'posix':
        fg.send_signal(signal.SIGTERM)
    else:
        eve_run('--serve', 'stop', '-e', 'eve.cfg')
    try:
        fg.wait(timeout=10)
        check(fg.returncode == 0, 'the foreground machine ends with status 0 (%s)' % fg.returncode)
    except subprocess.TimeoutExpired:
        fg.kill()
        check(False, 'the foreground machine did not stop within 10 s')
    out, err = fg.communicate()
    check(out == '', 'and printed nothing on the standard output: %r' % out)
    check(not os.path.exists(pid_file), 'the pid file is removed at the stop')

    # 6. the Service Control Manager
    if os.name == 'nt':
        admin = False
        try:
            admin = bool(ctypes.windll.shell32.IsUserAnAdmin())
        except Exception:
            pass
        if not admin:
            print('skip the Service Control Manager checks: they need an administrator (run this script from an elevated prompt)')
        else:
            sc_checks(eve)

    print('\n%d check(s) failed' % len(failures) if failures else '\nall checks passed')
    return 1 if failures else 0


def sc(*a):
    return subprocess.run(['sc', *a], capture_output=True, text=True)


def sc_checks(eve):
    name = 'eve_check'
    cfg = os.path.join(WORK, 'eve.cfg')
    sc('delete', name)
    p = sc('create', name, 'binPath=', '"%s" -s "%s"' % (eve, cfg), 'start=', 'demand')
    check(p.returncode == 0, 'sc create installs the service: %s' % p.stdout.strip()[:60])
    try:
        p = sc('start', name)
        time.sleep(2)
        q = sc('query', name).stdout
        check('RUNNING' in q, 'the service is RUNNING under the Service Control Manager')
        p = subprocess.run([eve, '--serve', 'status', '-e', cfg], capture_output=True, text=True, cwd=WORK)
        check(p.returncode == 0, 'and the machine answers on its doors')
        sc('stop', name)
        time.sleep(2)
        check('STOPPED' in sc('query', name).stdout, 'sc stop brings the service to STOPPED')
    finally:
        sc('delete', name)


if __name__ == '__main__':
    sys.exit(main())
