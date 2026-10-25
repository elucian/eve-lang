# Decisions, level 3: modules, libraries, classes and methods (version 0.2)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files and keep counting across them; a new entry goes to the file of its topic. The levels and their versions are in spec/features.

| File | Level | Topic | Version | Tests |
|---|---|---|---|---|
| [decision_level1.md](level1.md) | 1 | the project, and the language of a single script | 0.1 | `test/level1` (a) |
| [decision_level2.md](level2.md) | 2 | a project: aspects, and the procedures and functions inside them | 0.1 | `test/level2` (b) |
| [decision_level3.md](level3.md) | 3 | modules and imports, local libraries, classes and methods | 0.2 | `test/level3` (c) |
| [decision_level4.md](level4.md) | 4 | parallel processing and streams | 0.3 | `test/level4` (d) |
| [decision_level5.md](level5.md) | 5 | data language, database layer and the Eve database | 0.4 | `test/level5` (e) |
| [decision_level6.md](level6.md) | 6 | the Eve machine and the server | 0.5 | `test/level6` (f) |
| [decision_level7.md](level7.md) | 7 | web: HTML and WebAssembly | 0.6 | `test/level7` (g) |

## Scope

Level 3 is the structure of a larger program (version 0.2): **modules and imports first (c01 to c22), then the local libraries, then classes and methods (c10 to c17)**. Classes and methods moved here from level 1 (D-122); a class hosts only methods (D-123). The data language (types, records, generators, files, JSON and CSV, the HTTP client, secrets, compression) is level 5 (D-125); its draft features and open questions moved to `decision_level5.md`.

Moved from level 2 (D-112, 2026-10-07): modules, imports, libraries, extension methods across files and the library search path (`lib/`, `$EVE_LIB_PATH`, the standard library first). Tests c01 to c09; features F-STR-01 and F-STR-03.

Specification: `spec/semantics/modules.md` and the grammar `modules-and-imports-level-3`.

**Done (2026-10-08).** Version 0.2 is implemented: level 3 passes 50 of 50 on the VM. Its decisions are settled and archived (`design/decision/archive/level3.md`, `python script/plan.py show D-139`). Q-024 (system library) moved to level 5, where its modules are. Level 3 has no open entry.

- Q-024 The system library: names and members [open]
- D-123 A class hosts only methods; only a method has @self
- D-125 The data language is level 5
- D-126 What a module can contain; free scripts are not shared
- D-127 Project folders `web/` and `data/`
- D-128 `$EVE_HOME`, `$EVE_LIB` and `$EVE_LIB_PATH`
- D-129 Thread safety: `safe` and `unsafe` modules
- D-130 The default aspect is exclusive
- D-131 Import paths are relative to `$EVE_HOME`
- D-132 `Atomic(:T)` is a class of the standard library
- D-137 A module is identified by its file; bare names are checked for thread safety
- D-139 Module words renamed: `managed` and `direct`

- D-123 A class hosts only methods; only a method has @self
- D-125 The data language is level 5
- D-126 What a module can contain; free scripts are not shared
- D-127 Project folders `web/` and `data/`
- D-128 `$EVE_HOME`, `$EVE_LIB` and `$EVE_LIB_PATH`
- D-129 Thread safety: `safe` and `unsafe` modules
- D-130 The default aspect is exclusive
- D-131 Import paths are relative to `$EVE_HOME`
- D-132 `Atomic(:T)` is a class of the standard library
- D-137 A module is identified by its file; bare names are checked for thread safety
- D-139 Module words renamed: `managed` and `direct`

## Q-097 to Q-105 The library stats: names, shapes and the optional type (2026-10-24)

The design of the library `lib/stats/` is in `design/design-libraries.md` section 0.8. Questions, each with the proposal of that section:

- **Q-097 Names of the variance and the deviation.** Sample (divided by n - 1) and population (divided by n) each need a name. Proposal: `stats.variance(xs)` and `stats.stddev(xs)` are the sample forms (Excel `VAR.S`, `STDEV.S`), and `stats.variance_p(xs)` and `stats.stddev_p(xs)` the population forms (`VAR.P`, `STDEV.P`). Eve names cannot hold a dot.
**answer** Eve can have method p that is public in class variance. Or can have a module variance that has function p then stats.variance.p(xs) is perfectly legal. But also _p is acceptable. You chose the most convenient. Is the stdev.s and stdev.p teach in schools? If yes we can do this, the convention for a class to start with capital letter can support exceptions. Is just a convention, the compiler will not complain if user do not comply. 

- **Q-098 Mode with several modes.** Proposal: `stats.mode(xs)` gives the smallest of the most frequent values; `stats.modes(xs)` gives all of them as a list.
**answer** good yes

- **Q-099 Shape of `describe`.** Proposal: `stats.describe(xs)` gives a `Map` with the keys `count`, `mean`, `median`, `stddev`, `min`, `max`, `range`, `skew` and `kurtosis`; every key is also a function of its own. An empty list is `$err_argument` for every function except `count`.
**answer** good idea
- **Q-100 Moving averages at the start.** A simple moving average of window n has no value for the first n - 1 items. Proposal: the output is shorter (n - 1 fewer items) until the optional type `T?` exists (S15.50, D6); then the first items are `null`.
**answer** This require implementation of `T?` first. Let's try this after T? is implemented.
- **Q-101 Shape of the regression.** Proposal: `regress.linear(xs, ys)` gives a `Map` with `slope`, `intercept` and `r2`; `regress.poly(xs, ys, degree)` gives the list of coefficients, lowest power first, solved with `math.linear`.
**answer** great
- **Q-102 Distributions.** Proposal: one function per use, not a flag: `distrib.norm_pdf(x, mean, sd)`, `distrib.norm_cdf(x, mean, sd)`, `distrib.norm_inv(p, mean, sd)`, and the same triple for `binom_` (n, p), `poisson_` (lambda) and `uniform_` (low, high).
**answer** brilliant. agree.
- **Q-103 Random sampling.** Proposal: `sample.draw(xs, n, replace)` and `sample.bootstrap(xs, rounds)` take the generator as the last optional argument; without it they use the seeded generator of `math.random` in its unseeded form, so a test gives the same result with a seed (Q-075).
**answer** agree
- **Q-104 Histogram.** Proposal: `histogram.bins(xs, count)` gives a list of records with `low`, `high` and `count`; the bins are equal width from the minimum to the maximum; the last bin is closed on the right.
**answer** agree
- **Q-105 Spearman ties.** Proposal: tied values get their average rank (the usual rule); no question unless the author wants another rule.
**answer** agree

## Q-111 and Q-112 Typed exceptions: `recover` by class, and the exit code of a class (2026-10-25)
- **Q-111 `recover` by type.** Proposal: a `recover` region names the classes it handles, for example `recover FormatError` before its statements, with `$error` the object raised; a `recover` without a class handles every error as now. Which syntax do you want, and may the classes be the user's own classes (`class Failure = {...}`) as well as the built-in error classes of `errors.md`?
**answer** No, recover is just one region, inside this region, user can issue normal statements to analyze errors. Using match is one way but using decision if statement to check the error type: if $error is FormatError do... or match $error ...
- **Q-112 Exit code of a class.** Proposal: an error that is not recovered exits with code 4 as now, unless its class says otherwise: a field `exit: n` in the class declaration (0 or from 6 to 125, the codes that `over n;` may use). Which form do you want?

Status: the object of a class raised with `raise` already gives its code and message, and its fields are read from `$error` (tests e161). The two questions above are open.
**answer** 
User will be adiced to use raise instead of exit. Using exit n is dirty programming and force a low code user can decide what code to use but if code is not in error list the compiler will object. The code "n" will identify the error. Make a function that we can use to find the error type from code for error handling. Of course over n; is nore useful because in this case we do not catch anything.

## D-232 Error classes: `recover` stays one region, the class is tested with `is` (2026-10-26)
The answer to Q-111 and Q-112. `recover` is one region and has no class list: inside it the program tests the error with `if $error is FormatError do ... done;` or `match $error when FormatError do ...` (a class as pattern tests the class of the object, as `is` does). The built-in errors have classes, one per `$err_` code, all below `Error`, `SqlError` below `DatabaseError` (`errclasses.zig`, `errors.md#error-classes`); a raised object of the program's own class keeps its class in `$error`. The function `error_type(code)` gives the class of a code (null when the language has none). There is no `exit` field in a class (Q-112): the program raises an error, and `over n;` is the way to end with a code of its own. **Open (Q-113):** the author wrote that a code that is not in "the error list" is refused by the compiler; there is no such list for the codes of the program yet.

## D-233 The library stats: the answers to Q-097 to Q-105 (2026-10-26)
`stats.variance(xs)` and `stats.stddev(xs)` are the sample forms and `variance_p`, `stddev_p` the population forms (the author accepts `_p`); `stats.mode(xs)` the smallest most frequent value and `stats.modes(xs)` all of them; `stats.describe(xs)` a `Map` with `count`, `mean`, `median`, `stddev`, `min`, `max`, `range`, `skew` and `kurtosis`, each key also a function; the moving averages with `null` at the start wait for `T?` (now built: D-221), `regress.linear` gives a `Map` with `slope`, `intercept`, `r2` and `regress.poly` the coefficients, the distributions are one function per use (`norm_pdf`, `norm_cdf`, `norm_inv`, then `binom_`, `poisson_`, `uniform_`), `sample.draw` and `sample.bootstrap` take the generator as an optional last argument, `histogram.bins(xs, count)` gives records with `low`, `high`, `count`, Spearman ties take the average rank.

## Q-113 The codes of the program (2026-10-26)
D-232 keeps the answer of Q-112: no exit code in a class. Your answer says the compiler refuses a code that is not in an error list. Today `raise (code, message)` and `Error(code, message)` take any whole number, and `error_type(code)` gives `null` for a number the language has no class for. Two ways to make "the list": (a) the program declares its own errors, for example `class Failure = {...} <: Error with code 101;` or a `set` of named codes, and the compiler refuses a literal code that is neither a `$err_` constant nor declared; (b) no list: any code from 100 up is the program's. Which one?

## Q-114 `expect` and `assert` with a message (2026-10-26)
`errors.md` says the error of a failed `expect` or `assert` has the custom message, but no syntax gives one (`expect a, b;` is a list like in `print`). Proposal: `expect cond else "message";` and `assert cond else "message";`. Which form do you want?
