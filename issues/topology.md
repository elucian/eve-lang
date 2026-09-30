# Issues: topology.html

Page: `tutorial/topology.html` (597 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### TOP-01 Is indentation significant?
"Region members use indentation, like Python" and syntax.html: "regions and nested blocks use
mandatory indentation". Yet statements end with `;` and blocks end with keywords (`return`,
`repeat`, `done`). Must the lexer/parser check indentation (an error when it is wrong), or is it a
style rule only?
**Answer:** Yes indentation is mandatory at 2 spaces.
Status: open

### TOP-02 The full region list and order
The text lists `import, alias, constant, global, process, initialize`; the pattern also has
`class`, `[recover]`, `[finalize | release]`; syntax.html lists `finalize` and says `release` is
"object clear region for a class", but the module example ends with `release`. What are the
regions of a driver, an aspect and a module, in which order, and which may repeat (`global` can)?
Module end region: `release` or `finalize`?
**Answer:** to be clarified case by case.
Status: open

### TOP-03 System variables before `import`
"New system variables can be defined in the first region after `:`, with indentation, no keyword
needed": `set $sys_con = value;` directly under the header. With D-012 the header has no `:`.
Is this unnamed first region kept? May it only hold `$` variables?
**Answer:** The "set" create constants that belong to global scope the same scope used by driver. set can be used after #! or after keyword driver. 
Status: open

### TOP-04 Alias syntax
Two forms: `AliasName1 = library_name.MemberName;` and `set new_name := module_name.member_name;`.
Which one? Can an alias name a parameterized class (`ClassName[parameters]`)?
**Answer:** : we make `def AliasName1 = library_name.MemberName;` convention for making alias, create new keyword "def" that will loved by Python users who learn Eve. But ClassName[parameters] is not supported, does not make sens to me now.    
Status: open

### TOP-05 Constant declarations
Three forms: `constant` + `set PI = 3.14 :Float;`, `constant` + `E = 2.52 :Real;`, and
`NAME = Value;`. Is `set` used inside `constant`? Is the uppercase first letter enforced by the
compiler or only a convention? (Class names also start with a capital.). 
**Answer:** The constant name is not enforced by compiler just recommanded by ttorial. The constant region is a visual delimiter. set can be used anywhere in any declaration region like local scopes. The constant region is script level keyword. You can't use "set" in variable region. You need a constant region and you can't define global variables in constant region. But you can ignore both and create constants and variables in the global scope with 2 space indentaiton inside of a driver or module or aspect. The scope is bind to process scope.
Status: open

### TOP-06 `class` region or inline class
The pattern has a `class` region (`class` then `NewType = {} <: Type;`); the example writes
`class Person = {…} <: Object;` on one line. Both allowed?
**Answer:** No, we must use class to define new types. The `NewType = {} <: Type;` is the same thing, and is not allowed. 
Status: open

### TOP-07 Type inference in global regions
"In the global regions you can not use type inference" and globals use `=`, but the import
example writes `set $user_path := root_path/relative_path;`. Is `:=` allowed with `set`?
**Answer:** := is used to execute an expression not only to infere a type. "=" is used to assign values but this is an exception. We must allow simple expressions like string concatenation. This is a demonstration that := can be used in global region. We must eliminate the restriction.
Status: open

### TOP-08 Built-in system variables for 0.1
The pages name `$EVE_DIR`, `$EVE_LIB`, `$MY_DIR`, `$MY_LIB`, `$MY_LOG`, `$OS_PWD`, `$error`,
`$stack`, `$trace`, `$object`, `$result`, and user ones like `$user_path`. "System constants are
capitalized". Which system variables must the VM provide in 0.1, with which types? Are OS
environment variables visible as `$NAME`?
**Answer:** Yes, environment variables are visible as $NAME. 
Status: open

### TOP-09 `panic` codes versus D-010
"`panic N` ends with an error code, otherwise it returns 1 with panic and 0 with over; `panic 0`
is equivalent to `over`." D-010 has `over 1` = 1 (abnormal) and failed `expect` = 2 (error).
What code does a bare `panic` return: 1 or 2? Is `panic 0` really allowed? (See SYN-13.)
**Answer:** panic return 1, remove panix x, where x is variable. expect retunr 2 all the time let's match it with a simple code. raise will return error code > 0. So panic 0, is not allowed, we have "over" for ending a program with 0 code.
Status: open

### TOP-10 Aspect process and errors
"An aspect contains its own process" and "you can execute main() of an aspect with `run`", but
later "an aspect does not have a main process". "An aspect must handle its own errors, it can't
raise errors; unhandled errors make the program panic." Does an aspect have a `process`? Can an
aspect return a result or an error code to the driver?
**Answer:** Yes, aspect can have a process, actually this is mandatory. A library do not have a process, a module do not have a process and can't be apply but can be imported.
Status: open

### TOP-11 Module: file or folder?
The page says four things: a module "exists in a folder and consists of several scripts"; its
name is "the last segment in a library path" / "the folder name"; "a module is a single script
file, modules can be grouped into crates"; syntax.html says "module-name = file-name". Is a module
one `.eve` file or one folder? Is "crate" a term Eve keeps?
**Answer:** A folder is a library (crate) but we eliminate the term (crate) to go away from rust. We use terminology library/module. A module is a script file with header: module name is 
Status: open

### TOP-12 Import syntax and path operators
`from $path/library_name use (*);` and `use (module_name, …);`. Paths are built with a "smart
operator `/`", and elsewhere "`+`, `/` or `\`". Is `from <path> use (<names> | *);` the only import
form? Is a path an expression, a string, or a special literal?
**Answer:** The path is a string, created with concatenation opeprator. "/" is preffered concatenation operator for building the path. This is usually division but for string is "smart concatenation" it will flip to \ on windows.
Status: open

### TOP-13 Configuration file format
`.cfg` files hold "`$name:value` pairs" in one paragraph and "`$key = value` pairs" in the next.
Which syntax? Is the `.cfg` file Eve syntax (comments, literals) or its own format?
**Answer:** $key = value, Value can be a valid Eve literal. Configuration file can contain comments #.
Status: open

### TOP-14 VM modes in 0.1
The page describes console mode, service (daemon) mode, a REPL with 12 commands, `-c file.cfg`,
`-m 2048GB`, and `-x` exclusive mode. The Zig VM (D-006) starts as `eve <script.eve>`. Which of
these are in scope for 0.1? The rest can be marked "planned".
**Answer:** VM Parameters are planned but not for 0.1 maybe 0.9 version.
Status: open

### TOP-15 `load` and `debug` contradict
Text: "load will load a driver into memory without running the main process". Table: "load:
compile a driver and execute the main process"; "debug: compile but does not execute". Which is
right?
**Answer:** retink, we need comprehensive operations: parse, debug, execute. The debug will execute in debug mode, execute will execute in production mode.
Status: open

### TOP-16 Module globals merge
"Global variables are all merged in the context of driver or aspect." What happens when two
modules define the same global name?
**Answer:** Good question, only a driver define globals, the aspect and modules can define public or private variables. (defined using . are public) in this case, variables are accessible using dot operator "." with alias. 
Status: open

## Fixes (applied unless you write "no")

### TOP-F1 Wrong content
- Project tree uses `.bee` files → `.eve`.
- `E = 2.52` "Euler's number" → `2.718281828`.
- Example "terminated after 100 iterations" but `over if i > 10` stops after 11.
- "these regions are right side aligned" → left-aligned (start at column 0).
- `set local = value1: user_tupe;` → `user_type`.
- "In console you can run only a one driver"; "In each session you can have run single driver".
- Exclusive mode: "`start` is not starting a new driver", but `start` starts a coroutine.
**Answer:** Yes, "bee" is previous language I have design and is now "eve".

### TOP-F2 Removed comment forms in examples
The syntax pattern and the module example still use `+--- … ---+` boxes and `------` separator
lines, removed by D-011. Replace with `#`/`**` lines (after SYN-18).
**Answer:** correct

### TOP-F3 Colons after headers
`[driver | aspect | module] name:`, `process:`, `process | initialize:`, `cycle:`,
`aspect aspect_name(parameter_list):` → no colon (D-012), once TOP-02 confirms for `cycle` and
`initialize`.
**Answer:** removed
Status: done → D-015 (headers end with is, process has no colon)

### TOP-F4 Typos
overwriten, tunning, "it's" (its) ×5, "a eve", "have run", "separate with underscore",
"encounter".
**Answer:** _(open)_

## Improvements (applied only if you write "yes")

### TOP-I1 One canonical script skeleton
One annotated skeleton per script kind (driver, aspect, module) that matches the grammar exactly,
instead of a pattern with `[a | b]` alternatives mixed into code.
**Answer:** agree yes

### TOP-I2 Move the REPL to command.html
The REPL and daemon sections describe the tool, not the language. Move them to command.html (or
the manual's `usage.md`), and keep topology.html about projects, scripts, regions and modules.
**Answer:** agree

## Spec additions once answered

- `spec/semantics/topology.md`: projects, scripts, modules (TOP-11), imports (TOP-12), execution.
- `spec/syntax/regions.md`: regions and order (TOP-02, 03, 06), declarations (TOP-04, 05, 07).
- `spec/semantics/scopes.md`: system variables (TOP-08), module globals (TOP-16).
- `manual/usage.md`: VM modes and options (TOP-14, 15).
