## Single Symbols

In the syntax description "..." represent content and ",,," represents a sequence of elements. In descriptions vertical bar "|" represents second alternative. Some operators can have multiple purposes depending on the context and data types.


## Delimiters

|Symbol     | Description
|-----------|--------------------------------------------------------------
| (...)     | Complex expression \| Precedence of operations. 
| (,,,)     | List notation \| Ternary expressions
| [,,,]     | Array literal [1,2,3] \| Matrix [ [1,2],[3,4] ]
| {,,,}     | Data record \| Ordinal type \| Set of values
|\|\*..\*\| | Nested comments

## Single symbols

|Symbol | Description
|-------|--------------------------------------------------------------
| \#    | Directive or macro \| Template placeholder
| $     | System environment variable prefix
| @     | Require reference \| Input/Output parameter
| ;     | The end of any statement \| Statement separator
| .     | Decimal separator \| Member of {record, module, object}
| ,     | Enumeration for elements in a sequence
| <:    | Belong to set
| :     | Define name \| Pair-up operator
| \*    | Multiplication \| Variable arguments

## Double symbols

Level use two symbols to create a additional operators.

|Symbol| Description
|------|---------------------------------------------------------------
|\#\#  | Single line comment for heading comments
|\*\*  | Single line comment \| end of line comment
|..    | Range representation or slice [n..m] 
|:>    | Receive output argument from method I/O parameter
|+>    | Data pipeline fetch or select into: collection
|=+    | Outer join operator used in data "select" statement
|<:    | Declare user define type using a type descriptor
|<+    | Unpack operator |\ Template operator
|->    | Coercion operator
|<-    | Implication operator
|==    | Shallow comparison


## String: delimiters

|Symbol| Description
|------|---------------------------------------------------------------
|`x`   | Single ASCII character 
|'x'   | ASCII string literal
|"x"   | Unicode string literal

## String: concatenation

|Symbol| Description
|------|---------------------------------------------------------------
|  &   | Concatenate two strings as they are. No trim is performed!
|  /   | Concatenate two strings with "/" separator and de-duplicate "//"   
|  \\  | Concatenate two strings with "\\" separator and de-duplicate "\\"   

## Numeric operators

|Symbol |  Description
|-------|----------------------------------------------------------------
| /     | Real division
| *     | Numeric multiplication \| Scalar operator (alt+250) 
| ^     | Power operator. Example: x^n is the x to the power of n.
| %     | Reminder operator \| Scalar operator
| \+    | Numeric addition \| Concatenation \| Union
| \-    | Subtraction (dual operator)

## Modifiers 
Modifiers are in-place operators. They change value of the left operand with value of the right operand. Each modifier is created using one operator symbol follow by equal symbol "=" with no space between.

|Symbol| Description
|------|------------------------------------------------------------------
| :=   | new value \| replace existing value  
| +=   | addition \| scalar addition
| -=   | subtraction  \| scalar subtraction
| /=   | division  \| scalar division
| *=   | multiplication \| scalar multiplication
| %=   | reminder \| scalar reminder
| ^=   | power \| scalar power

## Relation Operators

Level use two symbols to create a additional operators.

|Symbol| Description
|------|-----------------------------------------------------------------------
|  =   | Equal: deep comparison \| Same type + Equal values \| Equal attributes 
|  >   | Greater than 
|  <   | Less than    
|  <>  | Not equal: deep comparison, equivalent to !(a = b)
|  >=  | Greater than or equal to
|  <=  | Less than or equal to
|  ==  | Reference comparison  \| Same reference
|  !=  | Reference comparison  \| Different references
        
## Collection operators

In following table A, B, C are sets and x is a member: numeric or string

|Operator | Result  | Description
|---------|---------|-------------------------------------------------------------------
| A |  B  | new set | Intersect A with B, use with : like C := A & B (return a new set)
| A &  B  | new set | Union A with B, use with : like C := A | B (return a new set)
| A <= B  | logic   | verify is A is subset of B
| x <: A  | logic   | verify if x is a member of collection
        
## Logical operators

These operators are expected logical values T := True, F := False

| Symbol | Description
|--------|-----------------------------------------------
|  !     | logic NOT (negation) 
|  &     | logic AND (intersection) 
|  |     | logic OR  (union)
|  ~     | logic Exclusive OR

## Bitwise operators

These operators are working for Natural:numbers ≥ 0

 symbol | description
--------|----------------------------------
  \<-   | shift bits to left  
  -\>   | shift bits to right
  !     | bitwise NOT (unary)
  &     | bitwise AND
  \|    | bitwise OR
  ~     | bitwise XOR

**Binary operators**

 A    | B   |A  &  B| A \| B| A ~ B
------|-----|-------|-------|--------
 00   | 00  |00     | 00    |  00    
 01   | 00  |00     | 01    |  01    
 11   | 01  |01     | 11    |  10    
 10   | 11  |10     | 11    |  01    
 11   | 11  |11     | 11    |  00    

**Unary operators**

 A    |A \<-  1 | A -\>2  | !A
------|---------|---------|-------
 0000 | 0000    | 0000    | 1111
 1111 | 1110    | 0011    | 0000
 0111 | 1110    | 0001    | 1000
 0110 | 1100    | 0001    | 1001

**See also:** [Wikipedia Bitwise Operation](https://en.wikipedia.org/wiki/Bitwise_operation)