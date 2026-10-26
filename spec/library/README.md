# The libraries of Eve

Status: **draft**. One page for each library; a function is on a page only when a test calls it. The rules for every library and the order of the work are in the plan of the libraries (step L0 to L9 of the standard library); the layout is:

```
lib/sys/        the signature files of the modules written in Zig (primitives)
lib/<name>.eve  a small standard module written in Eve
lib/<domain>/   a large library, one folder with sub-folders for the sub-domains: lib/math/trig, lib/stats/describe, ...
```

A folder library is imported by its path, `from lib/math/trig use (…)`. A function on a value is a method (`xs.sort()`, `s.upper()`); a function of mathematics that takes plain numbers is a function of the module `math` (`math.sqrt(x)`), never a global name. The only global functions are `floor`, `ceiling`, `round` and `type`.

## Built in (no import)

| Library | Page | What it holds |
|---|---|---|
| built-in names | [builtins.md](builtins.md) | `print`, `write`, `read`, `error`, `warning`, `log_err`, `log_wrn`, `raise`, `expect`, `assert` |
| strings | [strings.md](strings.md) | the functions of a `String` |
| lists | [lists.md](lists.md) | the functions of a `List`, an `Array` and a `DataSet` |
| maps | [maps.md](maps.md) | the functions of a `DataMap` |
| atomic | [atomic.md](atomic.md) | `Atomic(:T)` |
| math | [math.md](math.md) | `lib/math/`: `basic`, `explog`, `trig`, `constants`, `numtheory`, `linear`, `random`, `rational`, `complex` |
| stats | [stats.md](stats.md) | `lib/stats/`: `describe`, `correlate`, `regress`, `distrib`, `sample`, `histogram`, `moving` |
| calendar | [calendar.md](calendar.md) | `lib/calendar/`: `period`, `holidays`, `business` |
| text | [text.md](text.md) | `lib/text/`: `encode`, `slug`, `template`, `diff`, `regex`, `unicode` |
| finance | [finance.md](finance.md) | `lib/finance/`: `money`, `percent`, `interest`, `loan`, `invest`, `tax`, `depreciation`, `invoice`; the rounding of `Decimal` |
| time and dates | [time.md](time.md) | `Date`, `Time`, `DateTime`, `Duration`, `Zone` and the module `time` (draft) |
| bytes and ids | [bytes.md](bytes.md) | `Bytes` and `Uuid` (draft) |
| meta database | [meta.md](meta.md) | reference data embedded in the machine: time zones (`zone`, `meta`), `database.connect("meta")` (draft) |

## Modules written in Zig (`lib/sys/`)

| Module | Page | Feature |
|---|---|---|
| `fs` | the generated reference `lib/doc/fs.md` | F-LIB-04 |
| `csv`, `json`, `txt` | [data-language.md](data-language.md), `lib/doc/` | F-LIB-05 |
| `time` | [time.md](time.md), `lib/doc/time.md` | F-LIB-06 |
| `os` | [os.md](os.md) | F-LIB-07 |
| `secret` | [data-language.md](data-language.md#secrets) | F-LIB-08 |
| `crypto` | [crypto.md](crypto.md) | F-LIB-10 |
| `net` | [net.md](net.md) | F-NET-02 |
| `database`, `checkpoint` | [database.md](database.md) | F-DAT-01, F-DAT-04 |

## Modules written in Eve (`lib/`)

| Module | Page |
|---|---|
| `config` | [config.md](config.md) |
| `http` | [http.md](http.md) |
| `route` | [route.md](route.md) |
| `rpc` | [rpc.md](rpc.md) |
| `service` | [route.md](route.md) |
| `test` | [test.md](test.md) |

The registry that binds a signature file to the machine is [registry.md](registry.md). `python script/libcoverage.py` lists the members of the modules above and how many test files call each; `--missing` lists only the members without a test.

## Libraries to come

mathematics (`lib/math/`), statistics (`lib/stats/`), time and calendar (`lib/time/`), text and encoding (`lib/text/`), business (`lib/finance/`), engineering (`lib/eng/`), data (`lib/data/`): each gets its page here before its code.
