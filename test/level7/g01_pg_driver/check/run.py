"""The client of test f01: wait for evedb on its PostgreSQL port, run the Eve script with the VM of the test, stop evedb."""
import os
import socket
import subprocess
import sys
import time

eve = os.environ['EVE']
evedb = os.path.join(os.path.dirname(os.path.abspath(eve)), 'evedb' + ('.exe' if os.name == 'nt' else ''))
end = time.time() + 20
while time.time() < end:
    try:
        socket.create_connection(('127.0.0.1', 55431), timeout=1).close()
        break
    except OSError:
        time.sleep(0.2)
r = subprocess.run([eve, '-x', 'f01_pg_driver.eve'], capture_output=True, text=True)
sys.stdout.write(r.stdout)
sys.stderr.write(r.stderr)
subprocess.run([evedb, 'stop', '--connect', '127.0.0.1:55433'], capture_output=True)
sys.exit(r.returncode)
