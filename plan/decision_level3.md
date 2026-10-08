# Decisions, level 3: modules, libraries, classes and methods (version 0.2)

Decisions (`D-nnn`) are settled; questions (`Q-nnn`) wait for the author. Ids are shared by all the decision files and keep counting across them; a new entry goes to the file of its topic. The levels and their versions are in [version_map.md](version_map.md).

| File | Level | Topic | Version | Tests |
|---|---|---|---|---|
| [decision_level1.md](decision_level1.md) | 1 | the project, and the language of a single script | 0.1 | `test/level1` (a) |
| [decision_level2.md](decision_level2.md) | 2 | a project: aspects, and the procedures and functions inside them | 0.1 | `test/level2` (b) |
| [decision_level3.md](decision_level3.md) | 3 | modules and imports, local libraries, classes and methods | 0.2 | `test/level3` (c) |
| [decision_level4.md](decision_level4.md) | 4 | parallel processing and streams | 0.3 | `test/level4` (d) |
| [decision_level5.md](decision_level5.md) | 5 | data language, database layer and the Eve database | 0.4 | `test/level5` (e) |
| [decision_level6.md](decision_level6.md) | 6 | the Eve machine and the server | 0.5 | `test/level6` (f) |
| [decision_level7.md](decision_level7.md) | 7 | web: HTML and WebAssembly | 0.6 | `test/level7` (g) |

## Scope

Level 3 is the structure of a larger program (version 0.2): **modules and imports first (c01 to c22), then the local libraries, then classes and methods (c10 to c17)**. Classes and methods moved here from level 1 (D-122); a class hosts only methods (D-123). The data language (types, records, generators, files, JSON and CSV, the HTTP client, secrets, compression) is level 5 (D-125); its draft features and open questions moved to `decision_level5.md`.

Moved from level 2 (D-112, 2026-10-07): modules, imports, libraries, extension methods across files and the library search path (`lib/`, `$EVE_LIB_PATH`, the standard library first). Tests c01 to c09; features F-STR-01 and F-STR-03.

Specification: `spec/semantics/modules.md` and the grammar `modules-and-imports-level-3`.

## Q-024 The system library: names and members (2026-10-06)
The page `syslib.html` lists the modules that connect a program to the machine: `io`, `exception`, `fs`, `path`, `time`, `secret`, `task`, `database`, `http`, with their level and status; only `io` and `exception` are drafted (`evevm/lib/`). Are these the names and the split you want (for example one `fs` and `path`, or one `file` module)? Is the shell `call` part of the system library or of the language? Which module holds the time types (`time`), given that Date and Time have their own page?
**Answer:**

## D-123 A class hosts only methods; only a method has @self (2026-10-08)
Author decision. Inside a class body only `constructor`, `destructor` and `method` are declared: a `function` or a `procedure` there is a compile error (before, D-103 allowed private functions). A function or a procedure can not be bound to a class with `@self`: `@self` belongs to methods only, in the class body or outside it as an extension method (D-086). A helper of a class is a private method or a function outside the class. Tests: c15 (procedure in a class), c16 (function with `@self`), c17 (function in a class). The parser reports both errors. Applied: `syntax/declarations.md`.

## Roundup of level 3 (2026-10-08, revised): implemented on the VM
**Implemented (2026-10-08):** level 3 passes 31 of 31 (c01 to c31) and level 4 d01, d02 pass; the VM reads `EVE_LIB_PATH`. Notes of the work: a module is a scope of its own with the Value `module`; the link step (`project.zig`) reads, parses and checks every module before the run and stores it under `path|name`; `from … use` is run by the interpreter, which loads a module once (a map by tree) and runs `initialize` as a small process, so `recover` handles its errors; `finalize` runs in the reverse order when the driver ends. The checks of exports, conflicts, free scripts, instances, safe modules and concurrent aspects are compile errors (exit 65) from the link step; a module not found is the run-time error 30 (exit 4). Not covered by a test: `$EVE_LIB_PATH` (the runner sets no environment), a module that imports a module in a cycle, an aspect that imports a module with `(*)`.
**What was ready before the work:**
**Ready to implement: modules, libraries, classes.**
- Spec: `semantics/modules.md`, the grammar `modules-and-imports-level-3` (`grammarcheck.py test/level3`: every file parses), `declarations.md` (classes, D-123).
- Tests: c01 to c09 (imports, aliases, `m(*)`, `use (*)`, life cycle, singleton, private member, extension of an imported class), c10 to c17 (classes; pass on the VM), c18 to c22 (name conflict, exported variable, exported undeclared name, module instance, initialization order), c23 and c24 (a free statement in a module; a free script imported), c25 (module not found), c26 to c28 (safe modules); level 4: d01, d02 (concurrent aspects and modules). The negative tests c18 to c21, c23 and c24 pass today only because `from` and `module` are not implemented yet (exit 65 for the wrong reason): check their messages when the loader exists.
- VM to build: loader of `module` files, the import forms of the table in `modules.md`, `export`, `initialize`, `recover` and `finalize` in module order, the search path (standard library, `lib/`, `$EVE_LIB_PATH`), the refusal of a free script as an import.
**Open points** (`modules.md`, Open points): atomic variables (level 4), the layout of the folders of `$EVE_LIB_PATH`, a manifest.

## D-125 The data language is level 5 (2026-10-08)
Author decision. The data language (Decimal and time types, records, optional values, generators, files and paths, JSON, CSV, XML, HTML, DAT, the HTTP client, secrets, shell by argument list, compression) is **level 5**, with the database layer (version 0.4). Level 3 (version 0.2) is modules, imports, local libraries, classes and methods. Applied: the draft features and Q-038 moved to `decision_level5.md`; `version_map.md` (0.2 "Modules and classes", 0.4 "Data and database"), the features F-LNG-12 to F-LNG-14, F-VM-04, F-VM-06, F-LIB-04 to F-LIB-09, F-NET-01 and F-DOC-02 are v0.4; `data-types.md`, the tutorial section "Data File Types" and the readmes say level 5. The sections that mention a bytecode VM for generators are for level 5.

## D-126 What a module can contain; free scripts are not shared (2026-10-08)
Author decision. A **free script** is executable and may hold control statements, but it can not export anything and can not be imported. Free statements, which are not encapsulated in a function, a procedure, a method or a class, can not be exported; the only code outside those, in a module, are the regions import, export, initialize, finalize and recover. So a module holds declarations and those regions, and a free statement in a module is a compile error. The questions about cycles and about what can be exported (my roundup of 2026-10-08) had no sense and are dropped. Tests: c23 (a free statement in a module) and c24 (a free script imported). Applied: `modules.md`, `grammar.md` (the `recover` region of a module), `declarations.md`.

## D-127 Project folders `web/` and `data/` (2026-10-08)
Author decision. A project that uses templates has a `web/` folder, and a project that uses data files has a data folder; a test of such a project is a folder with those folders (D-124). The folders of a project are `asp/`, `lib/`, `web/`, `data/` and `out/`. The author wrote the data folder as `dat`; it is kept as `data/` (design-service.md, D-073) until the author says otherwise.

## D-128 `$EVE_HOME`, `$EVE_LIB` and `$EVE_LIB_PATH` (2026-10-08)
Author decision. `$EVE_LIB` is where the `lib` folder of the project is located: its local library. `$EVE_LIB_PATH` is where external modules are installed, a list of folders separated like the `PATH` of the operating system; they may be installed in different folders, for example `/eve/modules/<module_name>`, from GitHub with `npm install`. Both are searched by `from … use`, after the standard library. Closes the open point "`$EVE_LIB` against `$EVE_LIB_PATH`": the tutorial and D-112 g are both right. `$EVE_HOME` is new (D-131). Applied: `variables.md`, `modules.md`, the tutorial `modules.html`. The default of `$EVE_LIB` is `lib` relative to `$EVE_HOME`; the author wrote "where /lib folder is located" and this is read as the lib folder itself.

## D-129 Thread safety: `safe` and `unsafe` modules (2026-10-08)
Author decision. A concurrent aspect can call a procedure or a function as long as it is thread safe. The compiler flags the thread safety of each function and procedure by checking whether non-atomic variables are used. The signature of a module takes a word, `safe` or `unsafe`; the default is `unsafe`. A `safe` module is checked as a whole: all its variables must be atomic, and it is rejected if it uses unsafe functions or procedures. The author wrote the word "trade safe"; it is read as thread safe. The position of the word is proposed: in front of `module`, like `exclusive` in front of `aspect` (`safe module name is`); `safe` and `unsafe` are contextual keywords (D-116). Tests: c26 (non-atomic variable), c27 (unsafe call), c28 (a safe module is accepted); level 4: d01 (a concurrent aspect calls an unsafe procedure), d02 (a concurrent aspect calls a safe function). Atomic variables are level 4. Applied: `modules.md`, `grammar.md`, `keywords.json`.

## D-130 The default aspect is exclusive (2026-10-08)
Author decision. An aspect declared without a kind word is `exclusive`: `aspect name is` is `exclusive aspect name is`. `concurrent` must be written. Replaces the rule of D-090 that the kind word is required (test b23 `aspect_no_kind`, a compile error, is now b23 `aspect_default_exclusive`, which runs). VM: the parser takes the missing word as `exclusive`. Applied: `aspects.md`, `declarations.md`, `grammar.md`, `keywords.json`.

## D-131 Import paths are relative to `$EVE_HOME` (2026-10-08)
Author decision. An import path that does not start with `/` is relative to `$EVE_HOME`, the home of the project (by default the folder of the driver): `lib` is `$EVE_HOME/lib`. A path that starts with `/` is absolute: `/test/eve1/lib/`. The folders of `$EVE_LIB_PATH` follow the same rule. A module that is not found is the error `$err_module` (code 30, already registered in `exception.eve` and `errors.md`): raised at the import, exit code 4 when nobody recovers it. Circular imports are possible: a module that is being loaded is not loaded again. Test: c25. Applied: `modules.md`, `variables.md`.

## D-132 `Atomic(:T)` is a class of the standard library (2026-10-08)
Author decision. The class `Atomic` is defined in the standard library, so a variable can be declared `Atomic(:T)` (a type argument is written with a colon in front, a visual signal that a type follows), where `T` is a type: Logic, a number, a reference or an ordinal. The virtual machine is written in Zig and `Atomic` is a wrapper of the Zig atomic. It is initialized with a value: `new safe_integer = 0 :Atomic(:Integer);`. A type is declared by derivation: `class SageInteger <: Atomic(:Integer);`. A `safe` module (D-129) accepts a variable that is atomic, by `:Atomic(:T)` or by a class derived from it. Replaces the form `Atomic(:Integer)(0)` of the tutorial. VM: `Atomic(:T)` in a type hint is read as `T` flagged atomic (a single-threaded machine, so the value is a plain value and the operators work); `class Name <: Parent(T);` has no shape; the link step checks the variables of a `safe` module with it. Tests: c29, c30, c31. Applied: `grammar.md`, `modules.md`, `library/atomic.md`, `multitasking.html`, `modules.html`. Open: the atomic operations (level 4).
