# Library documentation

**Generated.** Do not edit the pages here: change the comments and signatures in [`../lib/`](../lib/README.md)
and run `zig build doc` in `evevm/`. The tool is `eved` (Eve doc), source in [`eved.zig`](eved.zig).

For each `lib/<name>.eve`, `eved` writes `doc/<name>.md` with:

- the summary: the comment block above the `module` line;
- one section for each declaration (`module`, `class`, `trait`, `function`, `method`, `process`, `routine`,
  `set`, `def`, and any signature that starts with `external`): the signature line as the title and the comment block right above it.

Comment forms read: `#` and `##` at column 0 (not the `#!` line), `**` to the end of the line, and `/* ... */` blocks. Expression comments `(** ... **)` are ignored. A comment separated from a declaration by a line of code is not documentation.

## The tool

`eved <source-dir> <output-dir>` writes Markdown from Eve sources: `**` comment blocks above a declaration and signatures. It scans lines for now; planned: use the real parser of the VM, add cross-links, examples and the `since` version. Tests: `zig build test`.
