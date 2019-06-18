## Single Symbols

In the syntax description "..." represent content and ",,," represents a sequence of elements. In descriptions vertical bar "|" represents second alternative. Some operators can have multiple purposes depending on the context and data types.

## Delimiters

|Symbol       | Description
|-------------|--------------------------------------------------------------
|`\|\*...*\|` | Outline block comments \| Expression comments
| `(_,_,_)`   | Expression \| @list literal
| `[_,_,_]`   | Range \| Index \| @list literals 
| `{_,_,_}`   | @ordinal type \| @set of values \| @hash type \| Generic types


## Single symbols

|Symbol | Description
|-------|--------------------------------------------------------------
| `&`   | System variable prefix
| `$`   | System constant prefix
| `@`   | Reference type prefix \| Class name prefix
| `#`   | Single line comment
| `;`   | Statement separator \| End of statement
| `:`   | Define constant   \| Pair-up operator (a:b)
| `.`   | Decimal separator \| Public member \| Member of ,,,
| `,`   | Enumeration for elements \| complex expression 
| `*`   | Variable arguments \| Multiplication
| `|`   | Used in set builders and hash map builders

## Double symbols

Eve use two symbols to create supplementary operators.

|Symbol| Description
|------|---------------------------------------------------------------
|`\*\*`| Single line comment | End of line comment 
| `..` | Domain (n..m) or slice [n..m] 
| `=+` | Outer join operator used in data "select" statement
| `as` | Pipeline operator (usual data casting)
| `<:` | Declare sub-type for a class
| `:>` | Declare visitor in scan statement
| `<+` | Template injector \| Data source provider
| `+>` | Result collector \| Visitor element


## String: delimiters

|Symbol| Description
|------|---------------------------------------------------------------
|\`x\` | @single  UTF32 character (4 bytes)
| 'x'  | Limited capacity string: UTF8 (max: 128 characters)
| "x"  | Variable capacity string: UTF8 (unlimited)

## String: concatenation

|Symbol| Description
|------|---------------------------------------------------------------------
|  `-` | Concatenate two strings after trimming first string
|  `+` | Concatenate two strings as they are. No trim is performed!
|  `/` | Concatenate two strings with "/" separator and de-duplicate "//"   
|  `\` | Concatenate two strings with "\\" separator and de-duplicate "\\\\"   
|  `.` | Concatenate two strings with "\\" or "/" depending on the: $platform

## Numeric operators

|Symbol | Description
|-------|----------------------------------------------------------------
| `/`   | @double division \| Fraction literal
| `*`   | Numeric multiplication \| Scalar operator
| `^`   | Power operator. Example: x^n is the x to the power of n.
| `%`   | Reminder operator \| Scalar operator
| `+`   | Numeric addition \| @string concatenation \| @set union
| `-`   | Subtraction \| @string concatenation \| @set difference

## Modifiers 

Modifiers are in-place operators. They change value of the left operand with value of the right operand. Each modifier is created using one operator symbol follow by equal symbol "=" with no space between.

|Symbol| Description
|------|--------------------------------------------------------------------
|`::`  | assign by copy  \| explicit cloning
|`:=`  | assign by share \| reset reference \| borrowing
|`+=`  | addition \| scalar addition
|`-=`  | subtraction  \| scalar subtraction
|`/=`  | division  \| scalar division
|`*=`  | multiplication \| scalar multiplication
|`%=`  | reminder \| scalar reminder
|`^=`  | power \| scalar power

## Relation Operators

EVE use two symbols to create a additional operators.

|Symbol | Description
|-------|-----------------------------------------------------------------------
| `==`  | Equivalent \| Deep comparison
| `<>`  | Different  \| Deep comparison
| `?=`  | Same objects      \| Shallow comparison
| `!=`  | Divergent objects \| Shallow comparison
| `> `  | Greater than 
| `< `  | Less than    
| `>=`  | Greater than or equal to
| `<=`  | Less than or equal to


**Notes:**   
* For divergence use:     not (a = b)  or (a != b)
* For different location: not (a == b) or (a <> b)
 
## Collection operators

In following table: `A, B, C` are collections and `x` is a member:

|Operator   | Result  | Description
|-----------|---------|-------------------------------------------------------------------
| A `++` B  | new     | Union A with B: ∪     use like C := A ++ B (return a new set)
| A `||` B  | new     | Intersect A with B: ∩ use like C := A || B (return a new set)
| A `- ` B  | new     | Simple difference,    use like C := A -  B (return a new set)
| A `--` B  | new     | Symmetric difference, use like C := A -- B (return a new set)
| A `<:` B  | logic   | verify if A is subset of B: In math: ⊂
| A `:>` B  | logic   | verify if B is subset of A: In math: ⊃
| C `+:` x  | append  | append a copy of element x to C    
| C `+=` x  | append  | append a reference of element x to C
| C `-=` x  | remove  | remove element == x from C  
| C `-:` x  | remove  | find and remove first element = x from C  
| C `-*` x  | remove  | find and remove all elements  = x from C  
        
## Logical operators

These operators are expected logical values T := true, F := false

| Symbol | Description
|--------|----------------------------------------------------------------
|  is    | check type: is @type or is Null, is not Null
|  in    | logic belong to: instead of "∈"
|  not   | logic NOT (negation) 
|  and   | logic AND (intersection) 
|  or    | logic OR  (union)
|  xor   | logic Exclusive OR


Table of truth for logical operators: 

 A     | B     | not A | A and B| A or B| A xor B
-------|-------|-------|--------|-------|-------
 True  | True  | False | True   | True  | False    
 True  | False | False | False  | True  | True   
 False | True  | True  | False  | True  | True
 False | False | True  | False  | False | False


## Bitwise operators

These operators are working for natural numbers ≥ 0

 symbol | description
--------|----------------------------------
  not.  | bitwise NOT (unary)
 .and.  | bitwise AND
 .or.   | bitwise OR
 .xor.  | bitwise XOR
 .shl.  | shift bits to left  
 .shr.  | shift bits to right

**Binary operators**

 A    | B   |A.and.B| A.or.B| A.xor.B
------|-----|-------|-------|--------
 00   | 00  | 00    | 00    |  00    
 01   | 00  | 00    | 01    |  01    
 11   | 01  | 01    | 11    |  10    
 10   | 11  | 10    | 11    |  01    
 11   | 11  | 11    | 11    |  00    

**Unary operators**

 A    |A.shl.1  | A.shr.1 | not.A
------|---------|---------|-------
 0000 | 0000    | 0000    | 1111
 1111 | 1110    | 0011    | 0000
 0111 | 1110    | 0001    | 1000
 0110 | 1100    | 0001    | 1001

**See also:** [Wikipedia Bitwise Operation](https://en.wikipedia.org/wiki/Bitwise_operation)

**Read next:** [overview](overview.md)