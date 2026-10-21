<!-- Generated from the specification, the tests and the benchmarks. Do not edit this page. -->

# Keywords

The words of the language. A **contextual** word is a keyword only where the grammar expects it and an ordinary name everywhere else.

| Word | Category | Meaning |
|---|---|---|
| `all` | block (contextual) | Option of match: every matching path runs. |
| `cancel` | block (contextual) | In `parallel on error cancel`: stops the other tasks after the first failure (level 4). |
| `do` | block | Starts the executable region of a job, loop, branch or path. |
| `done` | block | Closes an if, match, job, while or for: `done;` or `done label;`. |
| `else` | block | Alternative branch of an if, of a ternary expression, or of a while loop. |
| `error` | block (contextual) | In `parallel on error cancel` (level 4). |
| `for` | block | Loop over a range or a collection: `for x in r do`. |
| `if` | block | Conditional block `if c do … done;`, conditional statement suffix, and the ternary `a if c else b`. |
| `job` | block | A labeled block of a process: `name: job` … `do` … `done name;`. |
| `loop` | block | Header of a loop (label and declarations), or a loop tested at the end: `loop … do … repeat;`. |
| `match` | block | Multi-path selector: `match s [one \| all]`. |
| `on` | block (contextual) | In `parallel on error cancel` (level 4). |
| `one` | block (contextual) | Option of match: only the first matching path runs (the default). |
| `other` | block (contextual) | `when other do`: the path taken when no other `when` matched. |
| `parallel` | block | Group of concurrent aspects that run on several cores; `done` waits for all (level 4). |
| `repeat` | block | Closes a loop tested at the end: `repeat [label] [while c];`. |
| `then` | block | Removed: the statements go after `done;`. The word stays reserved; the parser says so. |
| `update` | block (contextual) | Block that changes the fields of one record without repeating its name: `update c do let city:= "Lyon"; done;` (level 5). |
| `when` | block | A path of a match: `when v1, v2 do`. |
| `while` | block | Loop tested at the start `while c do`, or the test of a `repeat while c;`. |
| `within` | block (contextual) | In `parallel within 30s`: a deadline for the tasks of the group (level 4). |
| `aspect` | declaration | Header of a script that runs: `[exclusive\|concurrent\|primary] aspect name is` … `end name;`. |
| `async` | declaration (contextual) | Declares a function or procedure that runs as a task of a job: `async procedure name is` (level 4). |
| `cached` | declaration (contextual) | Clause of `table`: the Eve server keeps the table in its cache, `cached 1h;` (version 0.5). |
| `class` | declaration | Declares a class, an ordinal, a range type or a function type; the superclass after `<:` is mandatory; a class body closes with `end Name;`. |
| `column` | declaration (contextual) | Clause of `table`: `column name as "cust_name";` renames the column of a field. |
| `concurrent` | declaration | Kind of an aspect that is thread safe: called with `apply` or started in a parallel group with `start`. |
| `constructor` | declaration | Declares the constructor of a class, inside its body. |
| `def` | declaration | Declares an alias of a name. |
| `destructor` | declaration | Declares the cleanup of an object, inside the class body. |
| `direct` | declaration (contextual) | Marks a module that is not thread safe: `direct module name is`; the default of a module (level 3). |
| `end` | declaration | Closes an aspect, module, class or trait: `end name;`. |
| `exclusive` | declaration | Kind of an aspect that is called with `apply` and never with `start`; the default of an aspect; a command may run it alone, for testing. |
| `export` | declaration | Lists the members a module makes public (level 3). |
| `external` | declaration (contextual) | Declares a native stored procedure of a connection by its signature: `external procedure archive_orders(before: Date) in "sales";` (level 5). |
| `from` | declaration | Starts an import: `from lib use (a, b);` (level 3). |
| `function` | declaration | Declares a function: a subprogram outside a class that has a result, `function f(x: T) => (@r: R) is`. |
| `generated` | declaration (contextual) | Clause of `table`: the columns that the database fills. |
| `generator` | declaration | Declares a function that gives its values one at a time with `yield` (version 2). |
| `is` | declaration | Ends a declaration header (`procedure p is`); also the operators `x is T` and `a is b`. |
| `key` | declaration (contextual) | Clause of `table`: the primary or unique key, `key (id);`. |
| `managed` | declaration (contextual) | Marks a module that is thread safe: `managed module name is`; every variable is atomic and it calls only safe members (level 3). |
| `method` | declaration (contextual) | Declares a method of a class, or an extension method outside it. |
| `module` | declaration | Header of a library script (level 3); `end name;` closes it. |
| `only` | declaration (contextual) | In the clause `read only;` of `table`. |
| `primary` | declaration | Kind of an aspect that is designed to be run first, by a command; no aspect applies or starts it; it is serial and its parallel groups start aspects: `primary aspect name is`. |
| `private` | declaration (contextual) | Visibility of a class member: the class only (the default). |
| `procedure` | declaration | Declares a procedure: a subprogram outside a class without a result, called as a statement, `procedure p(x: T) is` (from Ada). |
| `protected` | declaration (contextual) | Visibility of a class member: the class and its subclasses. |
| `public` | declaration (contextual) | Visibility of a class member: seen everywhere. |
| `read` | declaration (contextual) | In the clause `read only;` of `table`. |
| `reference` | declaration (contextual) | Clause of `table`: a foreign key to another table, `reference customer_id to customers;`. |
| `self` | declaration | Names the current object inside a constructor, a destructor and a method; reserved, it can't name anything else. |
| `set` | declaration | Declares a constant: `set pi = 3.14:Real;`. |
| `sql` | declaration (contextual) | Only before `function`: `sql function tax(…)` is an Eve function that SQLite and DuckDB can call from SQL (level 5). |
| `table` | declaration (contextual) | Binds a record class to a table of a connection: `table customers: Customer in "sales" is … end customers;` (level 5). |
| `temporary` | declaration (contextual) | Clause of `table`: the VM creates the table from the class (only in `"eve"` and `"stage"`). |
| `to` | declaration (contextual) | In the clause `reference f to t;` of `table`. |
| `trait` | declaration | Declares a stateless set of required and provided methods (level 4). |
| `use` | declaration | Lists the imported names in an import (level 3). |
| `version` | declaration (contextual) | Clause of `table`: the column for optimistic locking, `version version;`. |
| `and` | operator | Logical and. |
| `as` | operator | Formats a value: `d as T24`. |
| `eq` | operator | Equivalence: same value and same type. |
| `in` | operator | Membership: `x in collection`; also the generator of `for` and of a builder. |
| `not` | operator | Logical negation. |
| `or` | operator | Logical or. |
| `xor` | operator | Logical exclusive or. |
| `finalize` | region | Final region of a process; runs when the process ends normally, by `exit` or by `abort`. |
| `initialize` | region | Initialization region of a module (level 3). |
| `process` | region | The executable part of an aspect: `process main is` … `return;`; `main` is the entry point, the other processes are private. |
| `recover` | region | Error region of a process: decides `retry`, `resume` or `abort`. |
| `abort` | statement | In `recover`: ends the process, runs `finalize`, passes the error on. |
| `after` | statement (contextual) | In `recover`: `retry after 2s;` waits before it runs the failed job again (level 5). |
| `apply` | statement | Runs an aspect and waits for it (level 2). |
| `assert` | statement | Checks a condition; a failed assert is an error with code 3: the process goes to `recover` and ends when it is not recovered. |
| `await` | statement | Starts an async subprogram and waits for it at once: `await load(p, @t);`, `new n:= await size(p);` (level 4). |
| `break` | statement | Leaves a loop: `break [label] [if c];`. |
| `call` | statement | Runs a shell command (level 3). |
| `commit` | statement (contextual) | In a job: writes the pending changes, commits and begins a new transaction (level 5). |
| `defer` | statement | Registers a statement that runs when the enclosing subprogram ends. |
| `exit` | statement | Leaves the subprogram or process it is written in, back to the caller; in the main process of an aspect run by a command the program ends with code 0. `exit n;` also sets the exit code of the program. |
| `expect` | statement | Checks a condition; a failed expect is an error with code 2. |
| `let` | statement | Executes an assignment or an expression: `let x += 1;`. It may change several names and creates a missing name by type inference. |
| `new` | statement | Creates a variable or an attribute: `new x:= 0;`. |
| `over` | statement | Ends the whole process it is in at once with code 0, from any depth: `over;`; `over n;` gives the exit code of the program. No `recover`; `finalize` runs. |
| `panic` | statement | Ends the whole application at once with code 1. |
| `pass` | statement | The empty statement. |
| `raise` | statement | Creates an error: `raise "message";`; the process jumps to `recover`. |
| `resume` | statement | In `recover`: goes on after the failed job. |
| `retry` | statement | In `recover`: runs the failed job again. |
| `return` | statement | Closes a process, function, method, constructor or destructor. |
| `rollback` | statement (contextual) | In a job: undoes the transaction and ends the job with the status `rolled back` (level 5). |
| `skip` | statement | Goes to the continuation point of a loop: `skip [label] [if c];`. |
| `spawn` | statement | In the do region of a job, starts an async procedure as a task and goes on (level 4). |
| `start` | statement | Starts a concurrent aspect, only in the do region of a parallel group (level 4). |
| `stop` | statement | Ends a job without error. |
| `wait` | statement | Pauses the task for a duration and gives its core away: `wait 10ms;` (level 4). |
| `yield` | statement | In a generator: gives a value to the caller (version 2). |
