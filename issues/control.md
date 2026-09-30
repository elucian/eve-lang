# Issues: control.html

Page: `tutorial/control.html` (399 lines). Reviewed 2026-09-28. How to answer: [README](README.md).

## Questions

### CTL-01 Job block syntax
Pattern: `job job_name try … catch error1: … catch other: … resolve: … done [name];`.
syntax.html lists `job` ("scope block with error handlers") and `try` ("start job block region")
as separate keywords. Is `try` required after the job name? Is the name optional? Do `catch …`
and `resolve` take `:` (D-012 dropped header colons)? Is `catch other` the only catch-all form?
**Answer:** Jon is simplified.
Status: answered → D-016, simplified by D-020: name: job … do … done job [name]; no handlers

### CTL-02 Leaving a job: `break`, `exit`, `stop`
`break if condition;` "interrupts the job without error", but syntax.html defines `exit` as
"interrupt a process or sub-program without raising an error" and `stop` for loops. Is `break`
only for jobs? Does `exit` leave the job or the whole routine?
**Answer:** The exit exit the process, the stop, stop the job and can't be used to stop anything else. the break stop the loop.
Status: answered → D-016: stop ends a job without error, break leaves a loop; exit still ends the process or subprogram

### CTL-03 Job status
`let job_name.status = "pass" if condition;` A job "is an object with methods and properties"
and its status "is recorded for reporting". Which status values exist (`pass`, `fail`, …)? Where
is the report written? Is the job object readable after `done`?
**Answer:** a job that is not executed at all has status: "none". Job status belong to the process. Job state is transfered in an internal map: "jobs["label"].status", jobs["label"].error jobs["label"].line, the $error object knows the job that failed $error.job (string). 
Status: partly answered by D-020: status is automatic (pass at done or stop, fail on error); report format open

### CTL-04 `then` and `loop` keywords
Blocks are `if c then … done`, `when v then`, `while c loop … repeat`, `for x in r loop … repeat`.
Are `then` and `loop` mandatory?
**Answer:** No, then, loop are optional.
Status: answered → D-016: branches use do, loops use cycle; then is the after-block clause

### CTL-05 `repeat … if`
The unconditional loop allows `repeat [label] [if condition];` but `while` and `for` say "you
can't use if here", and the conditional-statement note says `if` "can be used sometimes after
repeat to terminate a loop". What does `repeat if c;` mean: loop again only while `c` is true (a
do-while)? Only in `cycle … loop`?
**Answer:** We need to fix this, we use repeat while condition. 
Status: open

### CTL-06 Scopes of blocks
"The if block doesn't have a local scope", "in the ladder the local scope is optional", "match has
a local scope (before `when`)", loops declare locals in `cycle`. Which blocks open a scope? Can
`new` appear inside an `if` branch, and where does that variable live?
**Answer:** Correct, if do not have a local scope, the parent scope is scope for if. The loop declare scope, the cycle keyword was repurpose.
Status: partly answered: loop, match and job have a declaration region; if has no scope

### CTL-07 Match selector details
`match s [all | one] [Type]:` What is the optional `[Type]`? `when [any | other] then`: are
`any` and `other` both valid for the default path? In `all` mode, does the default run when an
earlier `when` matched? Can `when` take ranges (`when 1..5`)?
**Answer:** Yes range is valid when (1..5) then add an example. When any is no longer required because we have "then" this will be executed for any match, the other will execute if none match.
Status: partly answered: match has a label and a then clause; [Type] and when-ranges still open

### CTL-08 `cycle` region
Every loop starts with `cycle [label]:` holding its local declarations. Is `cycle` required when
the loop has no locals? Is the label written after `cycle` only, or also after `repeat`, `stop`,
`skip`? 
**Answer:** skip was replaced with "next", stop is replaced with break, cycle is replaced by "loop" and "loop" is now labeled.
Status: answered → D-016: [label:] loop is the header with declarations; the label follows repeat

### CTL-09 `skip` or `next`
The unconditional loop uses `skip [label] [if condition];`; the `for` loop uses
`next if condition;`; syntax.html's keyword table has `skip` and `pass` but no `next`. Which
keyword starts the next iteration?
**Answer:** next is universal for next iteration
Status: answered → D-016: next

### CTL-10 `while … else`
"If the condition is never true only the `else` block is executed; if it was true for a while,
`else` is not executed." Is that the rule (Python runs `else` after a normal end instead)?
**Answer:** correct, if while faile first time, else is executed if was true one time, else is not executed but "then" is executed all the time. 
Status: open

### CTL-11 `for` control variable
"Control variable must be declared in local scope" (the `loop` region) and "is not available
after the loop", yet the pattern initializes it (`new var := 0;`). Is the declaration mandatory,
or can `for i in (1..10) cycle` declare `i` itself? 
**Answer:** Yes, if the for belong to a loop, we need to declare "i" otherwise an implicit scope is created for anonymous loop. 
Status: open

### CTL-12 Loops without declarations
The new header `[label:] loop` holds declarations, then `cycle` / `while c cycle` /
`for x in r cycle` starts the body. Other pages had loops with no declarations; they were
converted to `for x in r cycle … repeat;` (no header) and, for an unconditional loop, `loop`
followed directly by `cycle`. Are both right? Is the `loop` header optional for `while` and `for`?
**Answer:** yes, loop is optional, if the loop is missing the cycle has no private scope it's scope is the parent scope.
Status: open

### CTL-13 `repeat if condition`
The loop patterns end with `repeat [label];`, but the note under "Conditional If" still says `if`
"can be used sometimes after repeat to terminate a loop", and 3 examples use it (concurrency.html
×2, algorithms.html). Keep `repeat if c;` (repeat while c holds), or replace it with
`break if not c;` before `repeat;`?
**Answer:** repeat while c; is correct "repead if" must be corrected.
Status: open

### CTL-14 `check` and `clean`
`check` "executes if successfully finished, include abort"; `clean` closes resources. Does `clean`
always run (after errors too), like `finally`? Does `check` run after `stop`? What does "include
abort" mean here?
**Answer:** removed
Status: answered → D-020: check and clean are removed; tear-down goes in the process finalize region

### CTL-15 `stop` inside a loop inside a job
`stop` ends the job, `break` the loop. In a loop nested in a job, does `stop` leave both? Is
`break label` the way to leave an outer loop? 
**Answer:** Yes, stop can break the job from inside the loop but break can only break the loop or the loops if label is used.
Status: open

### CTL-16 Label rules
Labels are written `name: loop`, `name: match`, `name: job`, `name: parallel`. Is the label
optional everywhere except `job` and `parallel` (whose closer names it: `done job name`,
`join name`)? Must the closer repeat the label?
**Answer:** The job name is optional. If not used an implicit name is created "job24" where 24 is the line of the code.
Status: open

## Fixes (applied unless you write "no")

### CTL-F1 Broken images
`/images/decision.svg`, `/images/ladder.svg`, `/images/while.svg` do not exist in scl; the files
are in `/assets/images/`. Point the links there (or copy them to `projects/eve/img/`).
**Answer:** make a copy, we may need to morify later.

### CTL-F2 Wrong examples
- `print "a is even" if (a % 2 = 0);` uses `=` for comparison → `==`.
- Match pattern: `when V1` then `when V1, V2`: V1 twice; the second should be `V2, V3`.
- while_demo: `set this := (…)` (`:=` in global, `this` as a name), `new i := 0 : Integer;`,
  `new e : Symbol;` holding strings `"a"`, `write ',' if e is not this.tail` (identity on
  strings), expected output shows quotes and `i = 5` that nothing prints, comment
  `/** … */`, "in canse".
- Job pattern: `let job_name.status = "pass"` → `:=`.
- "(min..nax)" → `(min..max)`.
**Answer:** Fix examples. 

### CTL-F3 Typos
intrerupt, prematurly, automaticly, rezolved, reffer, "it's name", optionall, "dont have",
"if closed", necesarly, "It two variants", encounter.
**Answer:** need fix

### CTL-F4 Authoring standard
"Job block is one of most powerful Eve feature" → factual wording.
**Answer:** remove

## Improvements (applied only if you write "yes")

### CTL-I1 Block summary table
One table: block, opener, middle keywords, closer, has label, opens scope, allows `if` after
closer. Answers SYN-11 on the page.
**Answer:** Ok create a sumary table for open/close block keywords.

## Spec additions once answered

- `spec/syntax/statements.md`: conditional statement, blocks (CTL-04..08, 11).
- `spec/semantics/control.md`: job, errors, status (CTL-01..03), loop semantics (CTL-05, 09, 10).
