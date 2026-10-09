# Grammar

Status: **0.1-draft**, levels 1 to 4 (a single script; a driver and its aspects; modules; parallel processing, traits and generic classes), and the generic subprograms of level 5. The grammar starts from the tokens of [`../lexical/lexical.md`](../lexical/lexical.md). The meaning of each rule is in [`declarations.md`](declarations.md), [`statements.md`](statements.md), [`expressions.md`](expressions.md) and in `../semantics/`. Rules for levels 5 to 7 (data language, database, server, web) are not in this file yet. A level section may add alternatives to a rule of the base grammar by repeating its name; the note `(* adds to … *)` says so.

Notation: `=` defines, `,` follows, `|` chooses, `[ ]` is optional, `{ }` repeats zero or more times, `( )` groups, `"…"` is a keyword or a symbol token, `(* … *)` is a note. Every statement ends with `;`. Layout (2 spaces per level) is checked after parsing, not by the grammar (see lexical.md, Layout).

## Script

```ebnf
file        = free-script | script ;
free-script = shebang , { statement } ;                       (* line 1 is "#!…": no driver, no process *)
script      = driver | aspect | module ;                       (* module: level 3 *)
driver      = "driver" , name , "is" , { member } , "end" , name , ";" ;
member      = declaration | process ;
process     = "process" , name , [ "(" , [ parameters ] , ")" ] , "is" ,
              { declaration | statement } ,
              [ recover ] , [ finalize ] ,
              "return" , ";" ;
recover     = "recover" , { statement } ;
finalize    = "finalize" , { statement } ;
aspect      = [ "exclusive" | "concurrent" ] , "aspect" , name , "is" ,
              { declaration } , process , "end" , name , ";" ;       (* the process is named main; without a kind word the aspect is exclusive (D-130) *)
```

A driver has one process named `main`, which is the entry point. An aspect has exactly one process, also named `main`, and nothing in it is public (`../semantics/aspects.md`). `end name;` repeats the name of the header.

## Modules and imports (level 3)

```ebnf
module      = [ "managed" | "direct" ] , "module" , name , "is" ,
              { export | declaration } ,
              [ "initialize" , { statement } ] ,
              [ "recover" , { statement } ] ,
              [ "finalize" , { statement } ] ,
              "end" , name , ";" ;                                (* modules.md; D-068, D-085, D-126; without a safety word the module is direct (D-129) *)
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
primary     = duration | name-path , type-args ;                  (* adds to primary: 30s, Channel(:Integer)(capacity: 10) *)

parallel-block = [ label , ":" ] , "parallel" , [ "on" , "error" , "cancel" ] , [ "within" , expression ] ,
              { declaration } , "do" , { statement } , "done" , [ label ] , ";" ;   (* multitasking.md, D-140 *)
start-stmt  = "start" , { name , "/" } , name , "(" , [ arguments ] , ")" ;         (* only in the do region of a group *)
async-sub   = "async" , ( function | procedure ) ;                (* D-104, D-143 *)
spawn-stmt  = "spawn" , name-path , "(" , [ arguments ] , ")" ;   (* only in the do region of a job; an async procedure *)
await-call  = "await" , name-path , "(" , [ arguments ] , ")" ;
wait-stmt   = "wait" , expression ;                                (* wait 10ms; *)
type-args   = "(" , ":" , type , { "," , ":" , type } , ")" ;
```

`duration` is a token: an integer followed at once by `ms`, `s`, `m` or `h` (`../semantics/multitasking.md#durations`). `on`, `error`, `cancel`, `within` and `async` are contextual words; `parallel`, `start`, `spawn`, `await` and `wait` are reserved.

## Traits and generic classes (level 4)

```ebnf
declaration = trait ;                                             (* adds to declaration *)
class-member = [ visibility ] , partial-method ;                  (* adds to class-member: an abstract class (D-145) *)

trait       = "trait" , name , [ type-params ] , "is" , { trait-member } , "end" , name , ";" ;
trait-member = partial-method | method ;                          (* every method of a trait is public *)
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
call-stmt   = name-path , type-args , "(" , [ arguments ] , ")" ;  (* adds to call-stmt: show_all(:String)(names); *)
apply-stmt  = "apply" , { name , "/" } , name-path , type-args , "(" , [ arguments ] , ")" ;   (* adds to apply-stmt: apply sorter(:Row)(rows); *)
```

`type-params` and `type-args` are the rules of the generic classes (level 4). In an expression, `name-path , type-args` is already a primary (level 4), followed by the call: `largest(:Integer)(xs)`. A lambda has no type list. Several declarations of a subprogram with the same name are allowed when their signatures differ; the grammar does not check it (`declarations.md#overloading`).

## Declarations

```ebnf
declaration = variable | constant | alias | function | procedure | class | method | import ;   (* a method outside a class is an extension method (D-086) *)

variable    = "new" , init-list , ";" ;
init-list   = binding , { "," , binding } , [ type-hint ]
            | "(" , name , { "," , name } , ")" , ( "=" | ":=" ) , expression , [ type-hint ]
            | pattern-list , ( ":=" | "::" ) , expression      (* deconstruct: new x, y, _, *rest, _ :: a; *)
            | name , "::" , expression
            | name , "<-" , expression                          (* capture: the first element, see statements.md *)
            | names , type-hint ;                               (* no value: the zero value of the type *)
binding     = var-name , ( "=" | ":=" ) , expression ;
var-name    = name , [ "!" ] | "self" , "." , name ;                 (* name! only when the value is a function (D-117); self is reserved *)                       (* new self.x := v; creates an attribute inside a class *)
const-binding = ( name | sysname ) , ( "=" | ":=" ) , expression ;   (* set $epsilon = 0.5; *)
pattern-list = pattern , { "," , pattern } ;
type-hint   = ":" , type ;

constant    = "set" , ( const-binding , { "," , const-binding } | "(" , names , ")" , "=" , expression ) , [ type-hint ] , ";" ;
alias       = "def" , name , "=" , name-path , ";" ;

procedure   = "procedure" , name , [ "(" , [ parameters ] , ")" ] , "is" ,
              { declaration | statement } , "return" , ";" ;       (* no result, never "!" (D-100, D-101) *)
function    = "function" , name , [ "!" ] , "(" , [ parameters ] , ")" , "=>" , results , "is" ,
              { declaration | statement } , "return" , ";" ;
results     = "(" , result , { "," , result } , ")" ;
result      = [ "@" ] , name , [ "!" ] , ":" , type ;           (* a result of a non-deterministic kind may be named name! *)
parameters  = parameter , { "," , parameter } ;
parameter   = [ "*" | "@" ] , name , [ ( "=" | ":=" ) , expression ] , [ type-hint ] ;

class       = "class" , name , [ type-params ] ,
              [ "=" , class-shape ] , "<:" , supers , ( ";" | "is" , { class-member } , "end" , name , ";" ) ;
                                                                          (* without a shape: class SageInteger <: Atomic(:Integer); (D-132) *)
                                                                          (* the superclass is mandatory (Q-029) *)
class-shape = "{" , members , "}"                                         (* attributes: {x, y: Real} *)
            | "{" , ordinal-value , { "," , ordinal-value } , "}"        (* ordinal: {Red, Green} <: Ordinal *)
            | "(" , expression , ".." , expression , ")" , [ "(" , expression , ")" ]   (* range: (0..1)(0.1) <: Range *)
            | "(" , [ parameters ] , ")" , [ ":" , type ] ;              (* function type: (p1, p2: Integer): Integer <: Function; there are no procedure types (D-101) *)
type-params = "(" , ":" , type-param , { "," , ":" , type-param } , ")" ;   (* class Box(:T), class Sorted(:T <: Comparable) (D-145) *)
type-param  = name , [ "<:" , type ] ;
supers      = type | "(" , type , { "," , type } , ")" ;                  (* one class, then traits: <: (Object, Printable) (D-145) *)
ordinal-value = name , [ ":" , integer ] ;
members     = attribute , { "," , attribute } ;
attribute   = names , type-hint ;
names       = name , { "," , name } ;
class-member = [ visibility ] , ( method | constructor | destructor ) ;
visibility  = "public" | "protected" | "private" ;
method      = "method" , name , "(" , "@self" , [ ":" , type ] , { "," , parameter } , ")" , [ "=>" , results ] , "is" , body ;
constructor = "constructor" , "(" , [ parameters ] , ")" , "=>" , "(" , "@self" , ")" , "is" , body ;
destructor  = "destructor" , "(" , "@self" , ")" , "is" , body ;
body        = { declaration | statement } , "return" , ";" ;
```

## Types

```ebnf
type        = name-path , [ "(" , ":" , type , { "," , type } , ")" ]      (* Integer, Vector(:Real), Atomic(:Integer) (D-132) *)
            | "[" , [ dimension , { "," , dimension } ] , "]" , type          (* array: []Integer, [10]Integer, matrix: [2, 2]Integer *)
            | "(" , ")" , type                                                 (* list: ()Integer (D-117) *)
            | "{" , "}" , type                                                 (* DataSet: {}Integer (D-117) *)
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
            | "retry" | "resume" | "abort" | "exit" | "over" | "panic" | "stop" ;
let-stmt    = "let" , target , modifier , ( expression | "new" , names ) ;      (* let lst -> new f;  the explicit capture *)
defer-stmt  = "defer" , simple ;                                                (* registers a statement for the end of the subprogram (D-117) *)
modifier    = ":=" | "::" | "+=" | "-=" | "*=" | "/=" | "%=" | "^=" | "<+" | "+>" | "<<" | ">>" | "->" | "<-" ;
target      = name-path , { "[" , index-list , "]" } | "_" ;
call-stmt   = name-path , [ "(" , [ arguments ] , ")" | arguments ] ;     (* print x;  save(data);  foo; *)
expect-stmt = ( "expect" | "assert" ) , expression ;
raise-stmt  = "raise" , expression ;
jump        = ( "break" | "skip" ) , [ label ] ;
apply-stmt  = "apply" , { name , "/" } , name-path , "(" , [ arguments ] , ")" ;      (* only in the process of a driver; a folder may precede the aspect name *)
arguments   = argument , { "," , argument } ;
argument    = [ name , ":" ] , [ "@" ] , expression
            | "*" , expression ;                                        (* spread a list or a map, aspects.md *)

block       = if-block | match-block | job-block | while-block | for-block | repeat-block ;
if-block    = "if" , expression , "do" , { statement } ,
              { "else" , "if" , expression , "do" , { statement } } ,
              [ "else" , { statement } ] , "done" , ";" ;
match-block = [ label , ":" ] , "match" , expression , [ "one" | "all" ] , { declaration } ,
              { "when" , when-values , "do" , { statement } } ,
              [ "when" , "other" , "do" , { statement } ] ,
              [ "then" , { statement } ] , "done" , [ label ] , ";" ;
when-values = expression , { "," , expression } | "(" , expression , { "," , expression } , ")" ;
job-block   = label , ":" , "job" , { declaration } , "do" , { statement } , "done" , label , ";" ;
loop-head   = [ label , ":" ] , "loop" , { declaration } ;      (* the label of a while or for loop sits here *)
while-block = [ loop-head ] , "while" , expression , "do" , { statement } ,
              [ "else" , { statement } ] , [ "then" , { statement } ] , "done" , [ label ] , ";" ;
for-block   = [ loop-head ] , "for" , pattern , "in" , expression , "do" , { statement } ,
              [ "then" , { statement } ] , "done" , [ label ] , ";" ;
repeat-block = [ label , ":" ] , "loop" , { declaration } , "do" , { statement } ,
              "repeat" , [ label ] , [ "while" , expression ] , ";" ;
pattern     = name | "(" , pattern , { "," , pattern } , ")" | "(" , name , ":" , name , ")" | "*" , [ name ] | "_" ;   (* (k: v) visits a map *)
label       = name ;
```

`if` after a simple statement is the conditional suffix: `break if c;`. It is not allowed after `done` or after `expect`. A `match`, `while` or `for` that has a label closes with `done label;`; one without a label closes with `done;` (D-034).

## Expressions

```ebnf
expression  = lambda | conditional ;
lambda      = "(" , [ parameters ] , ")" , "=>" , expression ;           (* (x) => (x * 2); level 2, D-109 *)
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
sum         = product , { ( "+" | "-" | "<+" | "+>" ) , product } ;      (* "<+" and "+>" as expressions return a new list (D-117) *)
product     = power , { ( "*" | "/" | "%" ) , power } ;
power       = unary , [ "^" , power ] ;                    (* right to left; the unary minus applies first: -2 ^ 2 is 4 (Q-030) *)
unary       = ( "-" | "not" ) , unary | postfix ;
postfix     = primary , { "." , ( name | "job" ) | "(" , [ arguments ] , ")" | "[" , index-list , "]" } ;   (* no call on a lambda (D-147) *)
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

The postfix `(…)` after a range is the step of the range: `(0..10)(2)`. `(x)` is a grouping; the list of one element is `(x,)`. A bracket after a value is an index or a slice, never a range (D-022, D-023).
