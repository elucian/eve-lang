# Issues: processing.html

Page: `tutorial/processing.html` (414 lines). Reviewed 2026-09-28. Retired 2026-10-06: PRC-02, PRC-09 (D-055, on the page), PRC-F1 to F3 and PRC-I1 (applied). How to answer:
[README](README.md).

## Questions

### PRC-10 Process arguments from the command line
`process main(*args ()String)` here and `process main(*args: ()String)` with `eve:>start test.eve 1 2 3` on concurrency.html (D-040: the parameters belong to the process). For the VM (`bin/eve.exe script.eve 1 2 3`): are command-line arguments always strings, bound to the parameters of `main` by position? Can `main` declare typed parameters (`process main(n: Integer)`) that the VM converts?
**Answer:** yes, parameter name will be supported using -p if parameter is short and --param if parameter name is  long. In comments above main, the convention will say ** @param x: "description of parameter" so if a command is issued: run test.eve -h it will display the help automaticly generated from comments or if no comments are provided will just list the parameters. Parameters can be any eve literal, they will be parsed and converted to data.
Status: documented in the tutorial (D-055); only the VM and `manual/usage.md` are left: not a tutorial issue

## Spec additions once answered

- `spec/semantics/control.md`: interruptions, recover, finalize, exit codes (PRC-02, 03, 08; D-020, D-038).
- `spec/semantics/topology.md`: aspects, `apply`, `start`, groups, recursion (PRC-06, 07, 11, 13, 14; D-042, D-043).
- `manual/usage.md`: command-line arguments (PRC-10).
