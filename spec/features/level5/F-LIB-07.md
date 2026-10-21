# F-LIB-07 Shell commands

`call` with pipes, and a safe `run(cmd, args, cwd)`.

*Partial (2026-10-18):* module `os` with `run!` (no shell), `env!`, `hostname!`, `pid!`, `platform` (`spec/library/os.md`).

## Missing

- Pipes and `call` beyond `run!`; streaming output of `run!`.
- `os.platform` is not a member of `os` although `spec/library/os.md` names it.
