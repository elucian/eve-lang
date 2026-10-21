# Grammar

Status: **draft**, levels 1 to 4 (a primary aspect; the aspects it calls; modules; parallel processing, traits and generic classes), and the generic subprograms and the Eve macro of level 5. The grammar starts from the tokens of [`../lexical/lexical.md`](../lexical/lexical.md). The meaning of each rule is in [`declarations.md`](declarations.md), [`statements.md`](statements.md), [`expressions.md`](expressions.md) and in `../semantics/`. Rules for levels 5 to 7 (data language, database, server, web) are not in this file yet. A level section may add alternatives to a rule of the base grammar by repeating its name; the note `(* adds to … *)` says so.

Notation: `=` defines, `,` follows, `|` chooses, `[ ]` is optional, `{ }` repeats zero or more times, `( )` groups, `"…"` is a keyword or a symbol token, `(* … *)` is a note. Every statement ends with `;`. Layout (2 spaces per level) is checked after parsing, not by the grammar (see lexical.md, Layout).

## Script

```ebnf
file        = script ;
script      = aspect | module ;                                (* module: level 3 *)
aspect      = [ kind ] , "aspect" , name , "is" , { member } , "end" , name , ";" ;
kind        = "exclusive" | "concurrent" | "primary" ;         (* without a kind word the aspect is exclusive *)
member      = declaration | process ;
process     = "process" , name , [ "(" , [ parameters ] , ")" ] , "is" ,
              { declaration | statement } ,
              [ recover ] , [ finalize ] ,
              "return" , ";" ;
recover     = "recover" , { statement } ;
finalize    = "finalize" , { statement } ;
```

An aspect has a process named `main`, the entry point, and may have other processes, which are private (`../semantics/aspects.md`). The grammar does not check that `main` exists, nor that a primary aspect is never applied or started: the checker does (`declarations.md#scripts`). A file has no `#!` line and no statement outside a process, a function, a procedure or a method. `end name;` repeats the name of the header.

## Modules and imports (level 3)

```ebnf
module      = [ "managed" | "direct" ] , "module" , name , "is" ,
              { export | declaration } ,
              [ "initialize" , { statement } ] ,
              [ "recover" , { statement } ] ,
              [ "finalize" , { statement } ] ,
              "end" , name , ";" ;                                (* modules.md; without a safety word the module is direct *)
export      = "export" , "(" , exported , { "," , exported } , ")" , ";" ;
exported    = name , [ "!" ] ;                                    (* a function that ends with ! is exported with the ! *)
import      = "from" , path , "use" , "(" , import-item , { "," , import-item } , ")" , ";" ;
path        = string | segment , { "/" , segment } ;              (* from lib use (m); from "lib" use (m); from $EVE_LIB/db use (m); *)
segment     = name | sysname ;
import-item = "*" | name , [ "as" , name | "(" , "*" , ")" ] ;    (* a module, an alias, all public names, or every module of the folder *)
```

## Parallel processing (level 4)

```ebnf
block       = parallel-block ;                                    (* adds to block *)
simple      = start-stmt | spawn-stmt | await-call | wait-stmt ;  (* adds to simple *)
declaration = async-sub ;                                         (* adds to declaration *)
unary       = await-call ;                                        (* adds to unary: new n := await measure(p); *)
primary     = duration | name-path , [ "!" ] , type-args ;                  (* adds to primary: 30s, Channel(:Integer)(capacity: 10) *)

parallel-block = [ label , ":" ] , "parallel" , [ "on" , "error" , "cancel" ] , [ "within" , expression ] ,
              { declaration } , "do" , { statement } , "done" , [ label ] , ";" ;   (* multitasking.md *)
start-stmt  = "start" , { name , "/" } , name , "(" , [ arguments ] , ")" ;         (* only in the do region of a group *)
async-sub   = "async" , ( function | procedure ) ;
spawn-stmt  = "spawn" , name-path , "(" , [ arguments ] , ")" ;   (* only in the do region of a job; an async procedure *)
await-call  = "await" , name-path , "(" , [ arguments ] , ")" ;
wait-stmt   = "wait" , expression ;                                (* wait 10ms; *)
type-args   = "(" , ":" , type , { "," , ":" , type } , ")" ;
```

`duration` is a token: an integer followed at once by `ms`, `s`, `m` or `h` (`../semantics/multitasking.md#durations`). `on`, `error`, `cancel`, `within` and `async` are contextual words; `parallel`, `start`, `spawn`, `await` and `wait` are reserved.

## Traits and generic classes (level 4)

```ebnf
declaration = trait ;                                             (* adds to declaration *)
class-member = [ visibility ] , partial-method ;                  (* adds to class-member: an abstract class *)

trait       = "trait" , name , [ type-params ] , "is" , { trait-member } , "end" , name , ";" ;
trait-member = partial-method | method ;                          (* every method of a trait is public *)
declaration = adopt ;                                             (* adds to declaration: a type adopts a trait outside its declaration *)
adopt       = "adopt" , name , "for" , type , "is" , { method } , "end" , "adopt" , ";" ;   (* the methods are extension methods of the type; they write every required method of the trait *)
partial-method = "method" , name , "(" , "@self" , [ ":" , type ] , { "," , parameter } , ")" , [ "=>" , results ] , ";" ;
```

A class with a partial method is abstract: it is never created, only called by the constructor of a subclass. A generic class is made with its type arguments written: `Box(:Integer)(5)` (`declarations.md#traits-and-generic-classes`).

## Generic subprograms and overloading (level 5)

```ebnf
procedure   = "procedure" , name , type-params , "(" , [ parameters ] , ")" , "is" ,
              { declaration | statement } , "return" , ";" ;       (* adds to procedure: procedure show_all(:T)(items: ()T) *)
function    = "function" , name , [ "!" ] , type-params , "(" , [ parameters ] , ")" , "=>" , results , "is" ,
              { declaration | statement } , "return" , ";" ;       (* adds to function: function largest(:T <: Comparable)(items: ()T) *)
method      = "method" , name , type-params , "(" , "@self" , [ ":" , type ] , { "," , parameter } , ")" , [ "=>" , results ] , "is" , body ;
process     = "process" , name , type-params , "(" , [ parameters ] , ")" , "is" ,
              { declaration | statement } , [ recover ] , [ finalize ] , "return" , ";" ;   (* only the main process of an aspect *)
call-stmt   = name-path , [ "!" ] , type-args , "(" , [ arguments ] , ")" ;  (* adds to call-stmt: show_all(:String)(names); *)
apply-stmt  = "apply" , { name , "/" } , name-path , type-args , "(" , [ arguments ] , ")" ;   (* adds to apply-stmt: apply sorter(:Row)(rows); *)
```

`type-params` and `type-args` are the rules of the generic classes (level 4). In an expression, `name-path , type-args` is already a primary (level 4), followed by the call: `largest(:Integer)(xs)`. A lambda has no type list. Several declarations of a subprogram with the same name are allowed when their signatures differ; the grammar does not check it (`declarations.md#overloading`).

## Eve macro (level 5)

```ebnf
file        = macro ;                                           (* adds to file *)
macro       = { top-level } , primary-aspect , { top-level } ;   (* at least one other top-level; exactly one primary aspect *)
primary-aspect = "primary" , "aspect" , name , "is" , { member } , "end" , name , ";" ;
top-level   = declaration | aspect ;
```

A file with a single aspect is an aspect, not a macro, whatever its kind word. The grammar does not count the primary aspects: a macro with none or with two is a compile error, and so is a statement at the top level of a macro (`declarations.md#eve-macro-level-5`).

## Generators (level 5)

```ebnf
declaration    = … | generator-decl ;                                (* adds to declaration *)
generator-decl = [ visibility ] , "generator" , name , "(" , [ parameters ] , ")" , "=>" , results , "is" ,
                 { declaration | statement } , "return" , ";" ;       (* exactly one result; no "@" parameter other than it *)
simple         = … | yield-stmt ;                                    (* adds to simple; only in the body of a generator *)
yield-stmt     = "yield" , [ expression ] ;
```

## Database declarations and statements (level 5)

```ebnf
declaration  = … | table ;                                           (* adds to declaration: in an aspect, a module or a macro *)
table        = "table" , name , ":" , name-path , "in" , string , [ "as" , string ] ,
               ( ";" | "is" , { table-clause } , "end" , name , ";" ) ;
table-clause = "key" , "(" , names , ")" , ";"
             | "generated" , "(" , names , ")" , ";"
             | "version" , name , ";"
             | "column" , name , "as" , string , ";"
             | "reference" , name , "to" , name , ";"
             | "read" , "only" , ";"
             | "temporary" , ";"
             | "cached" , duration , ";" ;                           (* level 6, the Eve server *)
simple       = … | commit-stmt | rollback-stmt ;                    (* adds to simple; only in the do region of a job *)
commit-stmt  = "commit" ;
rollback-stmt = "rollback" ;                                         (* both take the suffix: rollback if dry_run; *)
update-block = "update" , name-path , "do" , { statement } , "done" , ";" ;     (* only for a record; the names of its fields are in scope *)
retry-stmt   = "retry" , [ "after" , duration ] ;                    (* replaces "retry" in recover: retry after 2s if $error.attempt < 5; *)
function     = "sql" , "function" , name , "(" , [ parameters ] , ")" , "=>" , results , "is" ,
               { declaration | statement } , "return" , ";" ;       (* adds to function: a SQL function in Eve, no "!", no type list *)
declaration  = … | external ;                                        (* adds to declaration *)
module-external = "external" , ( "function" , name , "(" , [ parameters ] , ")" , "=>" , results
                              | "procedure" , name , "(" , [ parameters ] , ")" ) , ";" ;   (* in a module: a signature, the machine has the body; name may be a reserved word (, tests c29 to c31) *)
external     = "external" , ( "procedure" , name , [ "(" , [ parameters ] , ")" ]
                            | "function" , name , "!" , "(" , [ parameters ] , ")" , "=>" , results ) ,
               "in" , string , [ "as" , string ] , ";" ;             (* a native stored procedure of a connection *)
```

`table`, `commit`, `rollback`, `update`, `after`, `sql` (only before `function`), `external` and the words of the clauses (`key`, `generated`, `version`, `column`, `reference`, `read`, `only`, `temporary`, `cached`) are contextual: each is a keyword only in the position shown, and stays a free name elsewhere, so a field called `key` or `version` is still allowed. Meaning: `../library/database.md`. A table that has no `end` is the short form `table countries: Country in "sales";`.

## Declarations

```ebnf
declaration = variable | constant | alias | function | procedure | class | method | import ;   (* a method outside a class is an extension method *)

variable    = "new" , init-list , ";" ;
init-list   = binding , { "," , binding } , [ type-hint ]
            | "(" , name , { "," , name } , ")" , ( "=" | ":=" ) , expression , [ type-hint ]
            | pattern-list , ( ":=" | "::" ) , expression      (* deconstruct: new x, y, _, *rest, _ :: a; *)
            | name , "::" , expression
            | name , "<-" , expression                          (* capture: the first element, see statements.md *)
            | names , type-hint ;                               (* no value: the zero value of the type *)
binding     = var-name , ( "=" | ":=" ) , expression ;
var-name    = name , [ "!" ] | "self" , "." , name ;                 (* name! only when the value is a function ; self is reserved *)                       (* new self.x := v; creates an attribute inside a class *)
const-binding = ( name | sysname ) , ( "=" | ":=" ) , expression ;   (* set $epsilon = 0.5; *)
pattern-list = pattern , { "," , pattern } ;
type-hint   = ":" , type ;

constant    = "set" , ( const-binding , { "," , const-binding } | "(" , names , ")" , "=" , expression ) , [ type-hint ] , ";" ;
alias       = "def" , name , "=" , name-path , ";" ;

procedure   = "procedure" , name , [ "(" , [ parameters ] , ")" ] , "is" ,
              { declaration | statement } , [ recover ] , "return" , ";" ;   (* no result, never "!" ; recover: *)
function    = "function" , name , [ "!" ] , "(" , [ parameters ] , ")" , "=>" , results , "is" ,
              { declaration | statement } , [ recover ] , "return" , ";" ;   (* recover: *)
results     = "(" , result , { "," , result } , ")" ;
result      = [ "@" ] , name , [ "!" ] , ":" , type ;           (* a result of a non-deterministic kind may be named name! *)
parameters  = parameter , { "," , parameter } ;
parameter   = [ "*" | "@" ] , name , [ ( "=" | ":=" ) , expression ] , [ type-hint ] ;

class       = "class" , name , [ type-params ] ,
              [ "=" , class-shape ] , "<:" , supers , ( ";" | "is" , { class-member } , "end" , name , ";" ) ;
                                                                          (* without a shape: class SageInteger <: Atomic(:Integer); *)
                                                                          (* the superclass is mandatory *)
class-shape = "{" , members , "}"                                         (* attributes: {x, y: Real} *)
            | "{" , ordinal-value , { "," , ordinal-value } , "}"        (* ordinal: {Red, Green} <: Ordinal *)
            | "(" , expression , ".." , expression , ")" , [ "(" , expression , ")" ]   (* range: (0..1)(0.1) <: Range *)
            | "(" , [ parameters ] , ")" , [ ":" , type ] ;              (* function type: (p1, p2: Integer): Integer <: Function; there are no procedure types *)
type-params = "(" , ":" , type-param , { "," , ":" , type-param } , ")" ;   (* class Box(:T), class Sorted(:T <: Comparable) *)
type-param  = name , [ "<:" , type ] ;
supers      = type | "(" , type , { "," , type } , ")" ;                  (* one class, then traits: <: (Object, Printable) *)
ordinal-value = name , [ ":" , integer ] ;
members     = attribute , { "," , attribute } ;
attribute   = names , type-hint ;
names       = name , { "," , name } ;
class-member = [ visibility ] , ( method | constructor | destructor ) | constant ;   (* a constant of the class, read as Class.NAME *)
visibility  = "public" | "protected" | "private" ;
method      = "method" , name , "(" , "@self" , [ ":" , type ] , { "," , parameter } , ")" , [ "=>" , results ] , "is" , body , [ recover ] ;   (* recover:; a constructor, a generator and a lambda have none *)
constructor = "constructor" , "(" , [ parameters ] , ")" , "=>" , "(" , "@self" , ")" , "is" , body ;
destructor  = "destructor" , "(" , "@self" , ")" , "is" , body ;
body        = { declaration | statement } , "return" , ";" ;
```

## Types

```ebnf
type        = name-path , [ "(" , ":" , type , { "," , type } , ")" ]      (* Integer, Vector(:Real), Atomic(:Integer) *)
            | "[" , [ dimension , { "," , dimension } ] , "]" , type          (* array: []Integer, [10]Integer, matrix: [2, 2]Integer *)
            | "(" , ")" , type                                                 (* list: ()Integer *)
            | "{" , "}" , type                                                 (* DataSet: {}Integer *)
            | "{" , ":" , "}" , "(" , type , "," , type , ")"                  (* DataMap: {:}(String, Integer) *)
            | "{" , type , { "|" , type } , "}"                                (* variant: {Real | Integer} *)
            | "(" , expression , ".." , expression , ")" , [ "(" , expression , ")" ]   (* range type *)
            | type , "?" ;                                                       (* optional *)
dimension   = integer | "?" ;
```

## Statements

```ebnf
statement   = ( simple , [ "if" , expression ] , ";" ) | block | variable ;
simple      = let-stmt | defer-stmt | call-stmt | apply-stmt | expect-stmt | raise-stmt | jump | "return" | "pass"
            | retry-stmt | "resume" | "abort" | exit-stmt | "panic" | "stop" ;
exit-stmt   = ( "exit" | "over" ) , [ expression ] ;                            (* the number is the exit code of the program, 0 or 6 to 125: errors.md#ending-the-process (G-2) *)
let-stmt    = "let" , target , modifier , ( expression | "new" , names ) ;      (* let lst -> new f;  the explicit capture *)
defer-stmt  = "defer" , simple ;                                                (* registers a statement for the end of the subprogram *)
modifier    = ":=" | "::" | "+=" | "-=" | "*=" | "/=" | "%=" | "^=" | "<+" | "+>" | "<<" | ">>" | "->" | "<-" ;
target      = ( name-path | sysname ) , { "[" , index-list , "]" } | "_" ;   (* a system variable is a target too; a constant one is a run-time error *)
call-stmt   = name-path , [ "!" ] , [ "(" , [ arguments ] , ")" | arguments ]     (* print x;  save(data);  foo; *)
            | postfix ;                                                         (* a call on any value, its result dropped: "abc".replace("", "x");  rows[1].close(); *)
expect-stmt = ( "expect" | "assert" ) , expression ;
raise-stmt  = "raise" , expression ;
jump        = ( "break" | "skip" ) , [ label ] ;
apply-stmt  = "apply" , { name , "/" } , name-path , "(" , [ arguments ] , ")" ;      (* in any process; a folder may precede the aspect name; a private process is applied by its bare name *)
arguments   = argument , { "," , argument } ;
argument    = [ name , ":" ] , [ "@" ] , expression
            | "*" , expression ;                                        (* spread a list or a map, aspects.md *)

block       = if-block | match-block | job-block | update-block | while-block | for-block | repeat-block ;
if-block    = "if" , expression , "do" , { statement } ,
              { "else" , "if" , expression , "do" , { statement } } ,
              [ "else" , { statement } ] , "done" , ";" ;
match-block = [ label , ":" ] , "match" , expression , [ "one" | "all" ] , { declaration } ,
              { "when" , when-values , "do" , { statement } } ,
              [ "when" , "other" , "do" , { statement } ] ,
              "done" , [ label ] , ";" ;
when-values = expression , { "," , expression } | "(" , expression , { "," , expression } , ")" ;
job-block   = label , ":" , "job" , { declaration } , "do" , { statement } , "done" , label , ";" ;
loop-head   = [ label , ":" ] , "loop" , { declaration } ;      (* the label of a while or for loop sits here *)
while-block = [ loop-head ] , "while" , expression , "do" , { statement } ,
              [ "else" , { statement } ] , "done" , [ label ] , ";" ;
for-block   = [ loop-head ] , "for" , pattern , "in" , expression , "do" , { statement } ,
              [ "else" , { statement } ] , "done" , [ label ] , ";" ;
repeat-block = [ label , ":" ] , "loop" , { declaration } , "do" , { statement } ,
              "repeat" , [ label ] , [ "while" , expression ] , ";" ;
pattern     = name | "(" , pattern , { "," , pattern } , ")" | "(" , name , ":" , name , ")" | "*" , [ name ] | "_" ;   (* (k: v) visits a map *)
label       = name ;
```

`if` after a simple statement is the conditional suffix: `break if c;`. It is not allowed after `done` or after `expect`. A `match`, `while` or `for` that has a label closes with `done label;`; one without a label closes with `done;`.

## Expressions

```ebnf
expression  = lambda | conditional ;
lambda      = "(" , [ parameters ] , ")" , "=>" , expression ;           (* (x) => (x * 2); level 2 *)
conditional = or-expr , [ "if" , or-expr , "else" , conditional ] ;
or-expr     = xor-expr , { "or" , xor-expr } ;
xor-expr    = and-expr , { "xor" , and-expr } ;
and-expr    = relation , { "and" , relation } ;
relation    = union , { ( "==" | "<>" | "<" | ">" | "<=" | ">=" | "=~" | "is" | "is" "not" | "in" | "not" "in" | "eq" | "not" "eq" ) , union } ;
union       = inter , { "||" , inter } ;
inter       = shift , { "&&" , shift } ;
shift       = range , { ( "<<" | ">>" ) , range } ;
range       = sum , [ range-op , ( sum | "?" ) ] | "?" , range-op , sum ;                      (* "?" is the open end: (0..?), (?..0) *)
range-op    = ".." | "..<" | ">.." | ">..<" | "+-" | "><" ;
sum         = product , { ( "+" | "-" | "<+" | "+>" ) , product } ;      (* "<+" and "+>" as expressions return a new list *)
product     = power , { ( "*" | "/" | "%" ) , power } ;
power       = unary , [ "^" , power ] ;                    (* right to left; the unary minus applies first: -2 ^ 2 is 4 *)
unary       = ( "-" | "not" ) , unary | postfix ;
postfix     = primary , { "." , ( name | "job" | "done" ) | "(" , [ arguments ] , ")" | "[" , index-list , "]" } ;   (* no call on a lambda ; .done is the flag of a generator object (level 5) *)
index-list  = index , { "," , index } ;
index       = expression | "*" ;                                               (* a range slices, "*" is a whole dimension *)
primary     = number | rune | string | text | name-path , [ "!" ] | sysname | "(" , expression , ")"
            | list | array | brace | "_" ;
list        = "(" , ")" | "(" , expression , "," , [ expression , { "," , expression } , [ "," ] ] , ")"
            | "(" , expression , "|" , generators , ")" ;          (* list builder *)
array       = "[" , [ expression , { "," , expression } , [ "," ] ] , "]" | "[" , expression , "|" , generators , "]" ;
brace       = "{" , "}" | "{" , ":" , "}" | "{" , expression , { "," , expression } , [ "," ] , "}"
            | "{" , pair , { "," , pair } , [ "," ] , "}" | "{" , expression , "|" , generators , "}" ;
pair        = ( name | string | rune | number ) , ":" , expression ;
generators  = generator , { "and" , ( generator | expression ) } ;
generator   = pattern , "in" , expression ;
name-path   = ( name | "self" ) , { "." , name } ;                          (* self is reserved: it names the current object only *)
```

The postfix `(…)` after a range is the step of the range: `(0..10)(2)`. `(x)` is a grouping; the list of one element is `(x,)`. A bracket after a value is an index or a slice, never a range.
