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

**Done (2026-10-08).** Version 0.2 is implemented: level 3 passes 50 of 50 on the VM. Its decisions are settled and archived (`plan/archive/decision_level3.md`, `python script/plan.py show D-139`). Q-024 (system library) moved to level 5, where its modules are. Level 3 has no open entry.

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
