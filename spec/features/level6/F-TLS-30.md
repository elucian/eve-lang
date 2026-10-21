# F-TLS-30 Service mode

`eve -s`: the machine with no user interface, silent, both doors, a log and a pid file; a Windows service under the Service Control Manager, a Linux daemon, or the foreground form (`EVE_SERVICE=foreground`); `-s file.cfg` is the service reading that file, and `-s` takes nothing else; the configuration of a script, a command or a door is `-e file.cfg` (`--setup`), and the command files `.vmc` are removed (2026-10-18).

*Partial (2026-10-17):* the console and foreground forms tested on Windows (`script/service_check.py`); the Service Control Manager form compiles, run needs an administrator; the POSIX code compiles for Linux, not run; not yet: Event Log, run as another user, log rotation, `evedb serve -s`.
