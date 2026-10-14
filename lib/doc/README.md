# Library documentation

**Generated.** Do not edit the pages here: change the comments and signatures in [`../lib/`](../lib/README.md) and run `zig build doc` in `evevm/`, which runs `eve --doc lib doc` (D-082). The generator is the `doc` command of the Eve virtual machine, source in [`../src/doc.zig`](../src/doc.zig).

For each `lib/<name>.eve`, `eve --doc` writes `doc/<name>.md` with:

- the summary: the comment block above the `module` line;
- one section for each declaration (`module`, `class`, `trait`, `function`, `method`, `generator`, `process`, `service`, `set`, `def`, and any signature that starts with `external`): the signature line as the title and the comment block right above it.

Comment forms read: `#` and `##` at column 0 (not the `#!` line), `**` to the end of the line, and `/* ... */` blocks. Expression comments `(** ... **)` are ignored. A comment separated from a declaration by a line of code is not documentation.

## The command

`eve --doc <folder | file.eve> [output folder]` writes Markdown from Eve sources; the output folder is `doc` by default. In the REPL the same command is `doc`. It scans lines for now; planned: use the real parser of the VM, add cross-links, examples and the `since` version. Tests: `zig build test`. Usage: [`manual/usage.md`](../../manual/usage.md#documentation-doc).
