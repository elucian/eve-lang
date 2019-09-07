## Single Symbols

In the syntax description "..." represent content and ",,," represents a sequence of elements. In descriptions vertical bar "|" represents second alternative. Some operators can have multiple purposes depending on the context and data types.

## Delimiters

|Symbol       | Description
|-------------|--------------------------------------------------------------
| `+-...-+`   | Block comments   \| Header comments
| `/*...*/`   | Outline comments \| Expression comments
| `(_,_,_)`   | Expression \| Tuple literal
| `[_,_,_]`   | Range \| Index \| List literals 
| `{_,_,_}`   | Ordinal type \| Set of values \| Hash type \| Generic types
| `#(....)`   | String interpolation (placeholder) for operator "?"


## Single symbols

|Symbol | Description
|-------|-------------------------------------------------------------------
| `!`   | Negation symbol
| `?`   | String template find & replace
| `#`   | Title comment a module level (not indented)
| `$`   | System constant prefix
| `@`   | System variable prefix
| `;`   | Statement separator \| End of statement
| `:`   | Define something   \| Pair-up operator (a:b)
| `=`   | Setup initial value for something
| `~`   | Check if two variables have same type
| `.`   | Decimal separator \| Public member \| Member of ,,,
| `,`   | Enumeration for elements \| complex expression 
| `*`   | Variable arguments \| Multiplication
| `\|`  | Used in set builders \| Set union "∪"
| `&`   | String concatenation \| Set intersection "∩"

## Double symbols

Eve use two symbols to create supplementary operators.

|Symbol| Description
|------|---------------------------------------------------------------
| `**` | Single line comment | Indented at least 2 spaces
| `//` | End of line comment | Not usable in expressions
| `..` | Domain (n..m) or slice [n..m] 
| `.!` | Domain exclude upper limit
| `!.` | Domain exclude lower limit
| `!!` | Domain exclude both limits
| `=+` | Outer join operator used in data "select" statement
| `<:` | Define sub-type for a class 
| `<+` | Append to the end of a collection
| `+>` | Append to the beginning of a collection
| `<<` | Shift ordered collection to left with n: X := C << n
| `>>` | Shift ordered collection to right with n: Y := C >> n 
| `:=` | Assign value of expression: Used with: { forge, clone, reset, share }


## String: delimiters

|Symbol| Description
|------|---------------------------------------------------------------
| `x`  | Single symbol max (UTF32)
| 'x'  | Limited capacity string:  UTF8 (max: 128 characters)
| "x"  | Variable capacity string: UTF8 (unlimited)

## String: concatenation

|Symbol| Description
|------|---------------------------------------------------------------------
|  `+` | Concatenate two strings after trimming first string
|  `&` | Concatenate one string with other string or or numeric type
|  `/` | Concatenate two strings with "/" separator and de-duplicate "//"   
|  `\` | Concatenate two strings with "\\" separator and de-duplicate "\\\\"   
|  `.` | Concatenate two strings with "\\" or "/" depending on the: $platform

## Numeric operators

|Symbol | Description
|-------|----------------------------------------------------------------
| `*`   | Numeric multiplication \| Scalar operator
| `/`   | Numeric division
| `^`   | Power operator. Example: x^n is the x to the power of n.
| `%`   | Reminder operator \| Scalar operator
| `+`   | Numeric addition \| String concatenation \| Set union
| `-`   | Numeric subtraction \| String concatenation \| Set difference


## Relation Operators

EVE use two symbols to create a additional operators.

|Symbol | Description
|-------|--------------------------------------------------------------------------
| `=`   | Equal \| deep comparison  \| (equal values & attributes)
| `<>`  | Different \| deep comparison \| (different value & attributes) 
| `==`  | Shallow comparison \| (same objects or data types)
| `!=`  | Shallow comparison \| (different objects or data types)
| `> `  | Greater than value
| `< `  | Less than value
| `>=`  | Greater than or equal to values
| `<=`  | Less than or equal to values


**Notes:**   
* For different value use: not (a = b)  or (a <> b)
* For different location:  not (a == b) or (a != b)
 
## Collection operators

In following table: `A, B, C` are collections and `x` is a member:

|Operator   | Result  | Description
|-----------|---------|-------------------------------------------------------------------
| A `|`  B  | set     | Union A with B: ∪     use like C := A |  B (return a new set)
| A `&`  B  | set     | Intersect A with B: ∩ use like C := A &  B (return a new set)
| A `-`  B  | set     | Simple difference,    use like C := A -  B (return a new set)
| A `--` B  | set     | Symmetric difference, use like C := A -- B (return a new set)
| A `++` B  | list    | Concatenate two lists use like L := A ++ B (return a new list)
| A `<=` B  | logic   | verify if A is subset of B: In math: ⊂
| A `>=` B  | logic   | verify if B is subset of A: In math: ⊃
| C `<+` x  | list    | append element x to C at the end    
| C `+>` x  | list    | append element x to C at the beginning
| C `-?` x  | remove  | find and remove first element == x from C  
| C `-*` x  | remove  | find and remove all elements  == x from C  
        
## Logical operators

These operators are expected logical values T = true, F = false

| Symbol | Description
|--------|----------------------------------------------------------------
|  if    | conditional operator
|  is    | check element is of Type
|  is not| check element is not of Type
|  in    | logic belong to: instead of "∈"
|  not in| logic not belong to: instead of "!∈"
|  not   | logic NOT (negation) 
|  and   | logic AND (intersection) 
|  or    | logic OR  (union)
|  xor   | logic Exclusive OR


Table of truth for logical operators: 

 A     | B     | A and B| A or B| A xor B
-------|-------|--------|-------|-------
 True  | True  | True   | True  | False    
 True  | False | False  | True  | True   
 False | True  | False  | True  | True
 False | False | False  | False | False

Unary operator not:

* not False = True
* not True  = False

## Bitwise operators

These operators are working for natural numbers ≥ 0

 symbol  | description
---------|------------------------------
  ` ~. ` | bitwise NOT (unary)
  `.&. ` | bitwise AND
  `.\|.` | bitwise OR
  `.+. ` | bitwise XOR
  `.<. ` | shift bits to left  
  `.>. ` | shift bits to right

**Binary operators**

 A    | B   | `A.&.B`|`A.\|.B`| `A.+.B`
------|-----|--------|--------|---------
 00   | 00  | 00     | 00     |  00    
 01   | 00  | 00     | 01     |  01    
 11   | 01  | 01     | 11     |  10    
 10   | 11  | 10     | 11     |  01    
 11   | 11  | 11     | 11     |  00    

**Unary operators**

 A    | `~.A`| `A.<.1` | `A.>.1` 
------|------|---------|---------
 0000 | 1111 | 0000    | 0000    
 1111 | 0000 | 1110    | 0111    
 0111 | 1000 | 1110    | 0011    
 0110 | 1001 | 1100    | 0011    

**See also:** [Wikipedia Bitwise Operation](https://en.wikipedia.org/wiki/Bitwise_operation)

**Read next:** [overview](overview.md)