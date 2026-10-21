# Scopes

Status: **draft**, level 1. Where a name lives and who can see it. Declarations: [declarations.md](../syntax/declarations.md#variables-and-constants); blocks: [control.md](control.md); aspects: [aspects.md](aspects.md); modules: [modules.md](modules.md).

## Blocks

A **scope** is the place where the names declared with `new`, `set` and the other declarations live. A name is visible from its declaration to the end of its scope, in that scope and in the scopes inside it, and nowhere else.

| Place | Opens a scope | What lives there |
|---|---|---|
| an aspect or a module | one scope for the whole file | constants, variables, functions, procedures, classes, imports: declared in any order |
| `process` | one scope | its parameters and the names declared in its body |
| a function, a procedure, a method | one scope for each call | its parameters, its result variables and the names declared in its body |
| `if` and its `else if` and `else` branches | **no** | a name created in a branch belongs to the enclosing scope |
| `match` | yes: the part before the first `when` | the declarations of the match |
| `job` | yes: the declarations before `do` | the declarations of the job |
| `while`, `for`, `loop` | the header declarations once, the body at every cycle | `loop new n := 0; while …`: `n` lives in the loop scope and survives the cycles; a name created in the body is new at each cycle |
| a `for` without header | only its control variable | `x` in `for x in r do` |

A name created inside a loop, a `match` or a job is gone after `done;`: the control variable of a `for`, the names of the body and the names of the header are a compile error (exit 65, `undefined name`) when used after the block. A variable that is read after the loop is declared before it, in the scope of the process.

## Visibility

- **Aspect level.** The variables and constants of an aspect are shared by its processes, functions and procedures, and by nobody else. Another aspect sees only the arguments it is given ([aspects.md](aspects.md#declarations-of-an-aspect)).
- **Order.** At the level of an aspect or a module the declarations are hoisted: a function may use a variable or another function declared after it. In a process, a name exists from the line of its `new`: reading it before is a compile error.
- **Functions.** A function, a procedure or a method does not see the variables of the process that calls it, only the names of its aspect or module, its parameters and the names it declares. Using a variable of the caller is a compile error.
- **System variables.** `$name` variables ([variables.md](variables.md)) are visible everywhere in the run.
- **Modules.** A module shows only what it exports ([modules.md](modules.md)); the other names are private to it.

## Redeclaration

Declaring a name that already exists **in the same scope** is a compile error (`'a' is already declared in this scope`), except overloaded subprograms ([declarations.md](../syntax/declarations.md#generic-subprograms-and-overloading)). A constant (`set`) can not be assigned with `let`.

## Open points

A name declared in a block that already exists in an enclosing scope hides it inside the block. The tree walker (the reference) does so; the bytecode machine reuses the outer variable. The behavior is not fixed by a test yet.
