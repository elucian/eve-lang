# Modules and libraries

Status: **0.1-draft**, level 3 (version 0.2), first part of the level: modules and imports, then the local libraries; classes and methods follow (`declarations.md#classes-and-objects`, D-122, D-123). Sources: D-041, D-056, D-068, D-072, D-085, D-087, D-112 (g), D-122, D-126, D-129, D-131. Tests: `test/level3` (c01 to c28), `test/level4` (d01, d02). Grammar: `../syntax/grammar.md#modules-and-imports-level-3`. Items marked *(proposed)* are not stated by the author. **Implemented in the VM (2026-10-08):** the loader, the import forms, `export`, the regions, the search path, `safe` and `unsafe`, the checks of c08 and c18 to c28; `$EVE_LIB_PATH` is read from the environment of the machine (`EVE_LIB_PATH`).

## What a module is

A module is a script file that holds declarations to be shared. It is not run: it has no `process`. Its header is `module name is`, with an optional safety word in front (`managed module name is`, `direct module name is`, see below), and it ends with `end name;`; the file name is the module name (`lib/counter.eve` holds `module counter`). A module has one scope (D-041), like a driver: everything between the header and `end` is indented by 2 spaces.

```eve
# counter: a constant, private state, life cycle
module counter is
  export (LIMIT, tick, count!);

  set LIMIT = 100 :Integer;
  new total = 0 :Integer;           ** private: a variable can't be exported

  procedure tick() is
    let total += 1;
  return;

  function count!() => (@result: Integer) is
    let result := total;
  return;

  initialize
    print "counter: loaded";
  finalize
    print "counter: {total} ticks";
end counter;
```

## What a module may contain

A module holds **declarations** and the regions around them (D-126): `from … use` (import), `export`, `initialize`, `recover` and `finalize`. A statement that is not inside a function, a procedure, a method, a constructor or a region (`print "x";`, `if … do`, an assignment) is a compile error in a module: the code of a module runs only when a member is called, or in `initialize`. A **free script** (`#!` on line 1) is the opposite: it is executable and may hold control statements, but it can not export anything and can not be imported; `from lib use (tool)` where `tool` is a free script is a compile error (c24). Only an encapsulated declaration can be shared. An **Eve macro** (level 5, D-152) is self-contained in the same way: it holds a driver, its aspects and declarations shared inside the file, and it can not be imported.

## Members

| Member | Declared with | Can be exported |
|---|---|---|
| constant | `set NAME = v :T;` | yes |
| function, procedure | `function`, `procedure` | yes; a non-deterministic function is exported with its `!` (`count!`) |
| class | `class Name = {…} <: Parent is … end Name;` | yes |
| extension method | `method name(@self: Class, …)` | no: visible in the module that declares it and in the scripts that import the class (D-086, D-072) |
| variable | `new name …;` | **no**: a module is shared, and a public variable is not safe when tasks run at the same time (D-068). `export (total)` of a variable is a compile error *(proposed)* |
| channel | `set name := new Channel(:T)(capacity: n);` | yes (level 4) |
| external | `external function …` | as any other; the body is in the machine (D-056) |

A member is **private** unless `export (…)` lists it. `export` may stand anywhere in the module, once or more. Exporting a name that is not declared is a compile error *(proposed)*.

## Life cycle

- **Singleton.** A module is loaded once, at the first import, whoever imports it: the driver, an aspect or another module. Every import gets the same copy and the same state (c07).
- **No instances.** A module is not a class: `new m := module_name();` is an error. Objects with their own state come from an exported class.
- **`initialize`** runs once, right after loading, before the importing script goes on. **`finalize`** runs once, when the driver has ended, after its process, in the reverse order of the initialization (c06, c22). A module that imports another is initialized after it: the dependencies come first. **`recover`** handles an error raised in `initialize`, as the `recover` of a process does *(proposed)*. The three regions are optional, indented like the declarations, and end at the next region or at `end name;`.
- A module can't read the variables of the script that imports it; it communicates through parameters (D-072 f).
- An aspect that imports a module may call its procedures; since they change the shared state, the aspect is `exclusive` *(proposed: a `concurrent` aspect may call only functions of a module, D-068)*.

## Import

```eve
from lib use (counter);              ** members as counter.name
from "lib" use (counter as c);       ** members as c.name
from lib use (counter(*));           ** the exported names of counter, without a prefix
from lib use (*);                    ** every module of the folder, the names merged
```

| Form | Brings in |
|---|---|
| `use (m)` | the module `m`; members as `m.name` (c01, c02) |
| `use (m as x)` | the module under the name `x`; members as `x.name` (c03) |
| `use (m(*))` | the exported members of `m` as bare names (c04) |
| `use (*)` | every module of the folder, namespaces merged (c05) |

- **The path** is written in two ways: folder names joined by `/` (`lib`, `lib/db`, `$EVE_LIB/db`) or a string expression (`"lib"`, `$root_path/"lib"`). Both are the same import (c01, c02).
- **Relative and absolute (D-131).** A path that does **not** start with `/` is relative to `$EVE_HOME`, the home of the project (by default the folder of the driver), also in an import written inside a module or an aspect: `lib` is `$EVE_HOME/lib`. A path that starts with `/` is absolute: `/test/eve1/lib`. The same rule holds for each folder of `$EVE_LIB_PATH`.
- **Where a module is searched.** When the import gives no path, in this order: the standard library (`io`, `exception`; `print` comes from `io`); the folder `$EVE_LIB`, the `lib` folder of the project (its local library); then each folder of `$EVE_LIB_PATH`, the external modules installed outside the project, for example `/eve/modules/<module_name>`, placed there from GitHub with `npm install`. These folders can be several and in different places.
- **Position.** An import is a declaration: it may stand anywhere in the scope of a driver, an aspect or a module, before or after the code that uses it (D-041).
- **Conflicts.** `use (*)` and `use (m(*))` merge names. If two modules give the same name, the import fails with a compile error that lists the modules one by one; no name is chosen silently (D-112 a).
- **Private members.** Reading a member that is not exported is a compile error at check time, exit 65: nothing runs (D-112 b, c08).
- **A module not found** is the error `$err_module` (code 30, `Module {name} not found in {library}`), raised at the import, before the process starts. Nobody can recover it, so the program ends with exit code 4 and the message on stderr (c25).
- **Circular imports** are possible: a module that is being loaded is not loaded again (`tutorial/modules.html`).

## Managed and direct modules

A module that is shared by tasks must not be changed by two of them at the same time. The compiler checks it, function by function and procedure by procedure: one that reads or writes a variable that is not atomic, or calls something that does, is **thread unsafe** (D-129). The header of a module states the promise:

| Header | Meaning |
|---|---|
| `direct module m is` | the default, also when the word is missing: the module may hold plain variables; its members are checked one by one |
| `managed module m is` | the whole module is thread safe: **every variable of the module is atomic**, and it calls only members that are safe. The compiler **rejects** the module when a variable is not atomic (c26) or when it uses an unsafe function or procedure, also of another module (c27) |

- A **concurrent aspect** may call a function or a procedure of a module as long as it is thread safe: a member of a managed module, or a member of a direct module that the compiler proves safe. Calling an unsafe member is a compile error (level 4, d01, d02).
- An **exclusive aspect** is the default (`aspect name is`, D-130) and may call anything; it is never started in a parallel group.
- Constants, classes and plain functions that touch no variable are safe in any module.
- **Atomic variables (D-132).** A variable is atomic when it is declared `:Atomic(:T)`, with `T` a Logic, a number, a reference or an ordinal (`new total = 0 :Atomic(:Integer);`), or with a class derived from it (`class SageInteger <: Atomic(:Integer);` and `new hits = 0 :SageInteger;`). The class `Atomic` is a wrapper of the atomic of the machine, defined in the standard library ([../library/atomic.md](../library/atomic.md)). Tests: c29, c30, c31.

## Libraries

A **library** is a folder of modules. The folder `lib/` of a project (`$EVE_LIB`) is its **local library**; the standard library is the library of the machine (`evevm/lib/`), found first; the external modules installed outside the project are in the folders of `$EVE_LIB_PATH`. A module in a library is imported by the name of its file. Libraries are not packaged or versioned at this level; a manifest and the installation of libraries are later (`tutorial/manifest.html`).

## Extension methods

A `method` declared outside a class, with `@self` of the class, extends the class (D-086): it is called as `obj.name(…)`, never changes the class, can't hide a method of the class, sees only its public members, and is visible only in the scripts that declare it or import the class. Only a method can have `@self` (D-123). Tests: c09 (class from a module, extended in the driver) and c11 (class and extension in one script).

## Open points

1. **Atomic operations:** the methods of `Atomic` (`add`, `get!`, `swap!`, …) belong to level 4; until then an atomic variable is read and changed with the ordinary operators (`library/atomic.md`).
2. **The folders of `$EVE_LIB_PATH`:** the layout of an installed package (one folder per package, `/eve/modules/<module_name>`), and who installs it: `npm install` is outside Eve; a manifest is later.
3. **Version and manifest** of a library (later).
4. **Exported extension methods:** a class exported with its extensions, or the extensions imported by name *(c09 shows the first form is enough)*.
5. **Generators** are declared in a module and exported like a function (D-087); they wait for the data language, level 5 (draft 1 in `decision_level5.md`).
