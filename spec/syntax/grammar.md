# Grammar

Status: **0.1-draft**, levels 1 and 2 (a single script; a driver and its aspects). The grammar starts from the tokens of [`../lexical/lexical.md`](../lexical/lexical.md). The meaning of each rule is in [`declarations.md`](declarations.md), [`statements.md`](statements.md), [`expressions.md`](expressions.md) and in `../semantics/`. Rules for levels 2 to 7 (import, aspect, parallel, database, server) are not in this file.

Notation: `=` defines, `,` follows, `|` chooses, `[ ]` is optional, `{ }` repeats zero or more times, `( )` groups, `"…"` is a keyword or a symbol token, `(* … *)` is a note. Every statement ends with `;`. Layout (2 spaces per level) is checked after parsing, not by the grammar (see lexical.md, Layout).

## Script

```ebnf
file        = free-script | script ;
free-script = shebang , { statement } ;                       (* line 1 is "#!…": no driver, no process *)
script      = driver | aspect ;                                (* module: level 3 *)
driver      = "driver" , name , "is" , { member } , "end" , name , ";" ;
member      = declaration | process ;
process     = "process" , name , [ "(" , [ parameters ] , ")" ] , "is" ,
              { declaration | statement } ,
              [ recover ] , [ finalize ] ,
              "return" , ";" ;
recover     = "recover" , { statement } ;
finalize    = "finalize" , { statement } ;
aspect      = ( "exclusive" | "concurrent" ) , "aspect" , name , "is" ,
              { declaration } , process , "end" , name , ";" ;       (* the process is named main *)
```

A driver has one process named `main`, which is the entry point. An aspect has exactly one process, also named `main`, and nothing in it is public (`../semantics/aspects.md`). `end name;` repeats the name of the header.

## Declarations

```ebnf
declaration = variable | constant | alias | function | procedure | class ;

variable    = "new" , init-list , ";" ;
init-list   = binding , { "," , binding } , [ type-hint ]
            | "(" , name , { "," , name } , ")" , ( "=" | ":=" ) , expression , [ type-hint ]
            | pattern-list , ( ":=" | "::" ) , expression      (* deconstruct: new x, y, _, *rest, _ :: a; *)
            | name , "::" , expression
            | name , "<-" , expression                          (* capture: the first element, see statements.md *)
            | name , ":" , type ;                               (* no value: the zero value of the type *)
binding     = name , ( "=" | ":=" ) , expression ;
pattern-list = pattern , { "," , pattern } ;
type-hint   = ":" , type ;

constant    = "set" , ( binding , { "," , binding } | "(" , names , ")" , "=" , expression ) , [ type-hint ] , ";" ;
alias       = "def" , name , "=" , name-path , ";" ;

procedure   = "procedure" , name , [ "(" , [ parameters ] , ")" ] , "is" ,
              { declaration | statement } , "return" , ";" ;       (* no result, never "!" (D-100, D-101) *)
function    = "function" , name , [ "!" ] , "(" , [ parameters ] , ")" , "=>" , results , "is" ,
              { declaration | statement } , "return" , ";" ;
results     = "(" , result , { "," , result } , ")" ;
result      = [ "@" ] , name , ":" , type ;
parameters  = parameter , { "," , parameter } ;
parameter   = [ "*" | "@" ] , name , [ ( "=" | ":=" ) , expression ] , [ type-hint ] ;

class       = "class" , name , [ "(" , ":" , name , { "," , name } , ")" ] ,
              "=" , class-shape , "<:" , type , ( ";" | "is" , { class-member } , "end" , name , ";" ) ;
                                                                          (* the superclass is mandatory (Q-029) *)
class-shape = "{" , members , "}"                                         (* attributes: {x, y: Real} *)
            | "{" , ordinal-value , { "," , ordinal-value } , "}"        (* ordinal: {Red, Green} <: Ordinal *)
            | "(" , expression , ".." , expression , ")" , [ "(" , expression , ")" ]   (* range: (0..1)(0.1) <: Range *)
            | "(" , [ parameters ] , ")" , [ ":" , type ] ;              (* function type: (p1, p2: Integer): Integer <: Function; there are no procedure types (D-101) *)
ordinal-value = name , [ ":" , integer ] ;
class-member = [ visibility ] , ( method | constructor | destructor | property ) ;
visibility  = "public" | "protected" | "private" ;
method      = "method" , name , "(" , "@self" , { "," , parameter } , ")" , [ "=>" , results ] , "is" , body ;
constructor = "constructor" , "(" , [ parameters ] , ")" , "=>" , "(" , "@self" , ")" , "is" , body ;
destructor  = "destructor" , "(" , "@self" , ")" , "is" , body ;
body        = { declaration | statement } , "return" , ";" ;
```

## Types

```ebnf
type        = name-path , [ "(" , ":" , type , { "," , type } , ")" ]      (* Integer, Vector(:Real) *)
            | "[" , [ integer | "?" ] , "]" , type                            (* array: []Integer, [10]Integer *)
            | "{" , ":" , "}" , "(" , type , "," , type , ")"                  (* DataMap: {:}(String, Integer) *)
            | "{" , type , { "|" , type } , "}"                                (* variant: {Real | Integer} *)
            | "(" , expression , ".." , expression , ")" , [ "(" , expression , ")" ]   (* range type *)
            | type , "?" ;                                                       (* optional *)
```

## Statements

```ebnf
statement   = ( simple , [ "if" , expression ] , ";" ) | block ;
simple      = variable-stmt | let-stmt | call-stmt | apply-stmt | expect-stmt | raise-stmt | jump | "return" | "pass"
            | "retry" | "resume" | "abort" | "exit" | "over" | "panic" | "stop" ;
let-stmt    = "let" , target , modifier , expression ;
modifier    = ":=" | "::" | "+=" | "-=" | "*=" | "/=" | "%=" | "^=" | "<+" | "+>" | "<<" | ">>" | "->" | "<-" ;
target      = name-path , { "[" , index-list , "]" } | "_" ;
call-stmt   = name-path , [ "(" , [ arguments ] , ")" | arguments ] ;     (* print x;  save(data);  foo; *)
expect-stmt = ( "expect" | "assert" ) , expression ;
raise-stmt  = "raise" , expression ;
jump        = ( "break" | "skip" ) , [ label ] ;
apply-stmt  = "apply" , name-path , "(" , [ arguments ] , ")" ;      (* only in the process of a driver *)
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
pattern     = name | "(" , pattern , { "," , pattern } , ")" | "*" | "_" ;
label       = name ;
```

`if` after a simple statement is the conditional suffix: `break if c;`. It is not allowed after `done` or after `expect`. A `match`, `while` or `for` that has a label closes with `done label;`; one without a label closes with `done;` (D-034).

## Expressions

```ebnf
expression  = conditional ;
conditional = or-expr , [ "if" , or-expr , "else" , conditional ] ;
or-expr     = xor-expr , { "or" , xor-expr } ;
xor-expr    = and-expr , { "xor" , and-expr } ;
and-expr    = relation , { "and" , relation } ;
relation    = union , { ( "==" | "<>" | "<" | ">" | "<=" | ">=" | "=~" | "is" | "is" "not" | "in" | "not" "in" | "eq" | "not" "eq" ) , union } ;
union       = inter , { "||" , inter } ;
inter       = shift , { "&&" , shift } ;
shift       = range , { ( "<<" | ">>" ) , range } ;
range       = sum , [ ( ".." | "..<" | ">.." | ">..<" | "+-" | "><" ) , sum ] ;
sum         = product , { ( "+" | "-" ) , product } ;
product     = power , { ( "*" | "/" | "%" ) , power } ;
power       = unary , [ "^" , power ] ;                    (* right to left; the unary minus applies first: -2 ^ 2 is 4 (Q-030) *)
unary       = ( "-" | "not" ) , unary | postfix ;
postfix     = primary , { "." , name | "(" , [ arguments ] , ")" | "[" , index-list , "]" } ;
index-list  = index , { "," , index } ;
index       = expression | "*" ;                                               (* a range slices, "*" is a whole dimension *)
primary     = number | rune | string | text | name-path | sysname | "(" , expression , ")"
            | "(" , lambda , ")"                            (* called at once: ((x) => (x * 2))(5); lambdas and closures: level 2, D-109 *)
            | list | array | brace | "_" ;
list        = "(" , ")" | "(" , expression , "," , [ expression , { "," , expression } ] , ")"
            | "(" , expression , "|" , generators , ")" ;          (* list builder *)
array       = "[" , [ expression , { "," , expression } ] , "]" | "[" , expression , "|" , generators , "]" ;
brace       = "{" , "}" | "{" , ":" , "}" | "{" , expression , { "," , expression } , "}"
            | "{" , pair , { "," , pair } , "}" | "{" , expression , "|" , generators , "}" ;
pair        = ( name | string | number ) , ":" , expression ;
generators  = generator , { "and" , ( generator | expression ) } ;
generator   = pattern , "in" , expression ;
name-path   = name , { "." , name } ;
```

The postfix `(…)` after a range is the step of the range: `(0..10)(2)`. `(x)` is a grouping; the list of one element is `(x,)`. A bracket after a value is an index or a slice, never a range (D-022, D-023).
