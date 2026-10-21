# The module `config`

Status: **draft**, level 6. Feature: F-TLS-12. Written in Eve: `lib/config.eve`, over the string functions ([strings.md](strings.md)).

Reads the `key = value` files of the machine (`eve.cfg`, `evedb.cfg`, `eve.env`; format in [machine.md](machine.md#configuration)) into a `DataMap`.

```eve
from lib use (config);
new cfg := config.read!("eve.cfg");
print config.get(cfg, "http_port", 8042);
```

## Format

- One `key = value` per line; spaces around `=` and at the ends are ignored. The key is the text before the first `=`.
- A line that is empty, or whose first non-blank rune is `#`, is ignored. A `#` after a value is part of the value (no end-of-line comments).
- A value in double quotes is a `String` without the quotes (`domain = "localhost"`). A whole number (`-?[0-9]+`) is an `Integer`; `true` and `false` are `Logic`; anything else is the text of the value, trimmed.
- A line without `=` is ignored. A repeated key keeps the last value.

## Members

| Member | Meaning |
|---|---|
| `parse(text: String)` | the `DataMap` of a text |
| `read!(path: String)` | the `DataMap` of a file (`fs.read!` then `parse`); a missing file is `$err_file` |
| `get(:T)(settings, key: String, default: T)` | the value of `key`, or `default` when the key is not there |
| `has(settings, key: String)` | `Logic`: is the key there |
