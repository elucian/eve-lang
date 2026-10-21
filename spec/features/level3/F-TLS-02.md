# F-TLS-02 REPL

Prompt, file completion, commands `check`, `execute`, `help`, `quit`; *2026-10-13:* the full-screen interface at a terminal (upper part with scrollback, command line between two rules, status bar with Ready / Running / time of the last run, Page Up and Down, resize), `help` as a table with a line between commands and `help <command>` pages that wrap to the window (`EVE_WIDTH`, `eve_width`), `clear`, `stop`, `listen`, `serve`, `status`, `eve <command>` without the prompt.

*Partial:* `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `setup` not implemented.

## Missing

- Commands `compile`, `debug`, `begin`, `enter`, `print`, `resume`, `setup`.
- A scripted session test through `eve --stdio` and `vm.eval`.
