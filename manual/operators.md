## Single Symbols

In the syntax description "..." represent content and ",,," represents a sequence of elements. In descriptions vertical bar "|" represents second alternative. Some operators can have multiple purposes depending on the context and data types.


## Delimiters

|Symbol     | Description
|-----------|--------------------------------------------------------------
| {`*_*`}   | Block comments \| Nested comments
| \|`*_*`\| | Inside expression comments
| (`_,_,_`) | Expression \| List literal \| Data record
| [`_,_,_`] | Range \| Index \| Array literals \| Parameterize types
| {`_,_,_`} | Ordinal type \| Set of values \| Hash map


## Single symbols

|Symbol | Description
|-------|--------------------------------------------------------------
| \#    | Directive or macro \| Template placeholder
| $     | System variable prefix \| Global variable
| @     | Require reference \| Input/Output parameter
| ;     | Statement separator \| Forward declaration
| :     | Define name \| Pair-up operator
| .     | Decimal separator \| Public member \| Member of ,,,
| ,     | Enumeration for elements \| complex expression 
| \*    | Multiplication \| Variable arguments

## Double symbols

Eve use two symbols to create a additional operators.

|Symbol| Description
|------|---------------------------------------------------------------
|\#\#  | Single line comment for heading comments
|\*\*  | Single line comment \| end of line comment
|..    | Range representation or slice [n..m] 
|::    | Receive output argument from method I/O parameter
|=+    | Outer join operator used in data "select" statement
|<:    | Declare user define type / sub-type 
|<+    | Injector \| Unpack  \| Template \| Data source
|+>    | Fetch or select into: collection \| Destination

## String: delimiters

|Symbol| Description
|------|---------------------------------------------------------------
|\`x\` | Single  UTF32 character (4 bytes)
|'x'   | Limited capacity literal: UTF32 (max: 128 characters)
|"x"   | Unicode string literalS UTF8

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

EVE use two symbols to create a additional operators.

|Symbol| Description
|------|-----------------------------------------------------------------------
|  =   | Equal: deep comparison \| Same type & value 
|  >   | Greater than 
|  <   | Less than    
|  <>  | Not equal: deep comparison, equivalent to !(a = b)
|  >=  | Greater than or equal to
|  <=  | Less than or equal to
|  ==  | Reference comparison  \| Same reference
|  !=  | Reference comparison  \| Different references
   
 
## Collection operators

In following table A, B, C are collections and x is a member: numeric, string or record

|Operator | Result  | Description
|---------|---------|-------------------------------------------------------------------
| x ! A   | logic   | verify if x is a not member of collection A
| x ? A   | logic   | verify if x is a member of collection A
| A &  B  | new     | Intersect A with B, use with : like C := A & B (return a new set)
| A \| B  | new     | Union A with B, use with : like C := A | B (return a new set)
| A <  B  | logic   | verify is A is subset of B
| A >  B  | logic   | verify is A is superset of B
| C += x  | append  | append element x in C
| C += B  | append  | append collection B to C
        
## Logical operators

These operators are expected logical values T := True, F := False

| Symbol | Description
|--------|-----------------------------------------------
|  !     | logic NOT (negation) 
|  &     | logic AND (intersection) 
|  \|    | logic OR  (union)
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