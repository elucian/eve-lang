## Data Types

EVE is data oriented language. There are four kind of data types:

* [Basic Types](#basic-types)
* [Composite Types](#composite-types)
* [Collection Types)(#collections)
* [User Defined](#user-defined)

**concepts**
* [Numeric Types](#numeric-types)
* [Data Coercion](#data-coercion)
* [Type inference](#type-inference)
* [Gradual typing](#gradual-typing)
* [String type](#string-type)
* [Calendar date](#calendar-date)
* [Time Duration](#time-duration)

## Basic Types

Basic types are abstract wrappers to native types. 

| type     | description
|----------|-------------------------------------------------------
| Char     | integer on 8  bit (unsigned)
| Logic    | Is a Ordinal type having values:  False = 0, True = 1
| Symbol   | integer on 32 bit (unsigned)
| Integer  | integer on 64 bit (signed)
| Natural  | integer on 64 bit (unsigned)
| Real     | double precision number on 8 bit (signed) 


## Composite Types

Composite data types are unions of data elements of heterogeneous types.
 
| type     | description
|----------|----------------------------------------------------
| Ordinal  | Enumeration of ideas, cases or terms
| Record   | Heterogeneous collection of elements in a database
| String   | Limited capacity string: ('single quoted')
| Text     | Unlimited capacity string: ("double quoted")
| Null     | is a reference type that represents Null reference


## Collections
Collections are groups of data elements of same type.

| type     | description
|----------|----------------------------------------------------------------
| List     | Dynamic unsorted enumeration of values or objects
| Hash     | Enumeration of (key:value) pairs unique sorted by key
| Set      | Enumeration of unique elements of the same type sorted by value

**Note:** Composite data types are references

## User Defined

A data type can be _defined_ using symbol "<:" and keyword: "type".

**Syntax:**
```
define
  type: type_name <: super_type (parameters)
```
**Notes:**

* Users can define new types as subset or group of basic types;
* A script can _import_ defined types or from other Scripts;
* A data type is declared in a _define_ region;

**Example:**
```
define
  type: Point <: Record (Integer: a, b )

method: main()
  Point: p1, p2      ** implicit constructor
  Point: p3 := {1,1} ** initial value for Point
process
  ** modification using constants
  p1.a := 1
  p1.b := 2  
  
  ** modification using literal
  p2 := {2, 2}
  
  print ("p1 = (a:#n, b:#n)" <+ (p1.a,p1.b))
  print ("p2 = (a:#n, b:#n)" <+ (p2.a,p2.b))  
return;
```
output:
```
p1 = (a:1, b:1)      
p2 = (a:2, b:2)
```

## Numeric Types

In EVE we can have two categories of numbers:

 Category     | EVE Types
--------------|-------------------------
 Discrete:    | Integer, Natural
 Continuous:  | Real

### Discrete numbers:

|type    |Chars  |Bytes|min |max   |maximum number	
|--------|-------|-----|----|------|-------------------------
|Integer |20     |8    |-2⁶³|2⁶³-1 |≤ 9,223,372,036,854,775,807
|Natural |20     |8    |0   |2⁶⁴-1 |≤ 18,446,744,073,709,551,615
 
For conversion into characters:

* The number of characters required for integer numbers is 20. (19+sign)
 
### Real numbers

The type _Real_ is represented using floating precision numbers.   
Floating decimal numbers are most simply described by 3 integers:

* s: a sign (0 or 1)  
* c: a coefficient  
* n: an exponent   

The numerical value of a finite number is −1ˢ × c × 2ⁿ
Using this formula EVE define one single type: Real.

Real: is double-precision 64-bit IEEE 754:  
sign has 1bit, exponent has 11 bits and coefficient has 52 bits;

|type     |Digits |Bytes|maximum number	
|---------|-------|-----|----------------------------------
|Real     |15     |8    |≤ 1.8 × 10³⁰⁸

Precision Real: numbers is variable depending on the size of the number. The number of digits represents the largest number that can be converted from string format into a Real: and back without loosing any digit. Think of it like a digital display from a packet calculator.

**See also:** [scientific notation](https://en.wikipedia.org/wiki/Scientific_notation#Other_bases)

### Numeric literals

   Example     | Description
---------------|-------------------------------------------------------------------------
0              | integer zero
1234567890     | integer number using symbols: {0,1,2,3,4,5,6,7,8,9}
0.5            | real number use symbols: {.,0,1,2,3,4,5,6,7,8,9}
0.0            | real number

**example**

```
method: main()
  ** declare variable
  Integer: i 
  Natural: n
  Real: r
process  
  ** modify variables
  i := 9223372036854775807
  n := 18446744073709551615
  r := 0.25  
return;
```

## Polymorphic operators
In mathematics there are very few operators: {+, -, ÷ , ⋅} that can operate with any kind of numbers: negative, positive, rational or real. So the numeric operators are not very specific. This property of operators is called _"polymorphic"_ and is a problem for computer science.

Some languages define different operators for integers and floating decimal numbers. For example in OCaml the operator "/" can divide integers while "/." can divide floating numbers. This is unexpected for a mathematician. Therefore some other languages are introducing polymorphic operators.

## Data Coercion
In computer science coercion is used to implicitly or explicitly change  an entity of one data type into another of different type. This is ready to take advantage of type hierarchies and type representations. 
If not designed properly the coercion can be a fatal mistake. EVE is a safe language so we do only safe coercion.

## Implicit coercion
In EVE the arithmetic operators are polymorphic. Numeric operators can do implicit data conversion 
to accommodate the data types and return an accurate result.  Automatic conversion is possible only when there is no risk of loosing data precision. If there is a loss of precision we can end-up with a _run-time error_. To prevent this EVE will implement a safe compile-time check.

Implicit conversion is possible and _safe_ in this direction:

Integer -> Natural -> Real -> String.

Explicit conversion is possible but _unsafe_ in this direction:

String -> Real ->  Natural:-> Integer 

```
given
  Integer: a := 2
  Real:    b := 1.5 
begin
  b := a ** this implicit cast is possible b = 2.0
  b := a + 3.5 ** add 3.5 then assign result to b = 5.5
  a := b       ** error: can not assign Real: to Integer
  a := 1.5     ** error: can not assign Real: to Integer
ready;
```

## Explicit coercion
Explicit coercion is a _forced conversion_. Can be used to convert backwards from higher data range to lower data range or from continuous numbers to discrete numbers. This however can cause a data or precision loss. Explicit coercion is using a function.

Examples of explicit coercion:   
```
given
  Integer: a := 0
  Real:    b := 1.5
begin
  ** explicit coercion lose (0.5)
  a := floor(b)
  print(a) ** will print: 1
 
  ** explicit coercion add (0.5)
  a := ceiling(b) 
  print(a) ** will print: 2

  ** explicit coercion rounding:  
  a := round(b) 
  print(a) ** will print: 2
ready;
```

**Number to a string**

```
given
  String: s 
  Integer: v := 1000
begin  
  s := format(v) ** explicit coercion s:="1000"
ready  
```

**String: to a number**

This can be ready using the casting function parse(), only if the string contains a number. Otherwise the conversion fail and will rise and exception. 

```
given
  Integer: v 
  Real:    b
  String:  s := '1000'
  String:  r := '200.02'
begin
  v := parse(s) ** make v = 1000
  v := parse(r) ** make v = 200 and decimal .02 is lost
  b := parse(r) ** make b = 200.02 and decimal .02 is preserved
ready;
```

**Note:** 
 Build-in functions that are located in EVE "default" script:
 
 { parse(), format(), ceiling(), floor() round()}
 
 This script is one of the standard Scripts that are automatically included in any EVE program. 


## Type inference

This is a logical deduction of variable type from literal or constructor using ":=" operator.

**Example:**

```
** Define a list of 10 elements using type inference:
given
  List: ls := (0,1,2,3,4,5,6,7,8,9)
begin
  print(ls.type()) 
  ** expect: List[Integer]
ready  
```

## Default types
Literals are representations of specific particular data type in source code.

**Basic types**
Next notation use "9" to show any digit in range [0..9].

Literal      | Type
-------------|-----------------
 9           | Integer
-9           | Integer
0x9ABCDEF    | Hexadecimal -> Natural
0b1010101    | Binary -> Natural
9.9          | Real
U+0001       | Unicode symbol code

**Zero literals**

Literal    | Type
-----------|---------------
[]         | Array
{}         | Set/Hash
()         | List
""         | Text
''         | String
0          | Integer
0.0        | Real
           
**Collection literals**

Literal      | Type
-------------|-----------------
('a','b','c')| List[String]
(1,2,3)      | List[Integer]
[1,2,...]    | Array[Integer]
{1,2,...}    | Set[Integer]
{a,b,c}      | Ordinal
(x:'b',y:'d')| Record
{1:'a',2:'b'}| Hash

       
### Type verification
Type inference is welcome when type is difficult to create.

Examples of type inference:

```
given
  Record: r := (name:"test", age:"24") 
  Hash:   m := {('key1':"value1"),('ley2':"value2")} 
begin
  ** check variable types using introspection
  print("name  is of type " + type(v.name))
  print("key   is of type " + type(m.key))
  print("value is of type " + type(m.value))
ready;
```
run test  
```
name is of type Test
key is of type String
value is of type Text  
```

## Check type

In EVE the type is first class value. For type introspection we can use:

1. built-in type() function
2. operator _is_

```
given
  Real: i := 1.5
  Type: it
begin
  when i is Real do
    print("Yes i is Real")
  else
    print("No i is not Real")
  ready;
  it := type(i)
  print("type of i is #t" <+ it)
ready;
```

## Partial Inference

Sometimes the type is partially specified to improve type declaration.

```
define
  ** member type is inferred from literal 
  Array[](10) a := 0
```
## Logic type

In Latin the "falsus" and "verum" are translated to false and true.

* falsus := ⊥ defined by ⊥ := ¬ ⊤  and  ( P ∧ ¬P )
* verum  := ⊤ defined by ⊤ := ¬ ⊥  and  ( P ∨ ¬P )

name     |    value      | binary 
---------|---------------|------------------------------
False    | Logic.False   | 00000000 00000000 
True     | Logic.True    | 00000000 00000001

**syntax**
```
define
 Logic: variable_name ** default False
```


**internal design**

Probably best to define Logic type is Ordinal:
```
define
  type: Logic <: Ordinal { .False , .True }
```

**Relation Operators**

Logic values can be compared using relation operators:    

{ =, >, <, <=, >=}.  

**Logic Operators**
Logical operators are expecting logical operands. 

Symbol  | Description
--------|-------------------------------------------
  !     | logical NOT
  &     | logical AND
  \|    | logical OR
  ~     | logical XOR

Table of truth for logical operators: 

 A    | B   | !A | A & B | A \|B | A ~ B
------|-----|----|-------|-------|-------
 T    | T   | F  | T     | T     | F    
 T    | F   | F  | F     | T     | T   
 F    | T   | T  | F     | T     | T
 F    | F   | T  | F     | F     | F

**Logical expressions**

A logical expression is a demonstration or logical deduction having result T or F. The order of operations can be controlled using operator precedence and parentheses (). 

Operator precedence:` {!, &, |, ~} `

Result of logical expressions can be used into a conditional statement to make a decision. 
Also results of logical expressions can be stored in logical variables to be used later in other conditions.

## Gradual typing

Gradual typing is a type system in which some variables may be giventypes and the correctness of the typing is checked at compile-time (which is static typing) and some variables may be left un-typed and eventual type errors are reported at run-time (which is dynamic typing). To declare gradual types we use a polymorphic type called "Variant".

**Variant Types**

A Variant is a polymorphic variable that can have multiple types but only one at a time:

**Syntax:**
```
define
  type: variant_name <: Variant (type_name | type_name | ... )

global  
  variant_type: v
```

## Variant Properties

* Variant data type is a reference;
* Variant data type is assigned at runtime;
* One variant can have a single value at a time;
* One variant is a "union" of several types

## Making a null-able type

For this we need Null type. 

* The Null type is usually String: and is a curious type.
* It can have only one value: Null and is not printable.

**Examples:**
```
define
  Type: Number <: Variant (Integer | Real | Null)

global
  Number: x := Null
  
```

**Usability**

A variant can change its data type at runtime:

```
given
  Real | Integer: v, x ,t 
begin
  ** positive example
  v := 1     ** v is Integer
  x := 1.5   ** x is Real:    
  t := 1 / 2 ** make t Real
  
  ** safe conversion
  t := 12 ** t is Real
  
  ** negative examples
  v := x  ** ERROR: v is Integer 
ready;
```

A variant is a way to create a generic method.

```
method: switch(Integer | Real @ x, y)
  Integer | Real @ i
process  
  assert type(x) = type(y)  
  
  i :: x ** intermediate reference
  x :: y ** first  switch
  y :: x ** second switch
return;

method: main()
  Integer: x, y
  Real: a, b
process  
  ** invert two Integer: numbers
  x := 10
  y := 20  
  switch(x, y)
  
  ** invert two Real: numbers
  a := 1.5
  b := 2.5
  switch(a, b)
return;
```

## Single symbol

Symbols are Unicode UTF32. That is using 32 bit integer code points. EVE has two literal notations for symbols: 

* Single-quoted string like: 'α'
* U+HHHH   from: U+0000   to U+FFFF
* U-HHHHHH from: U+000000 to U+FFFFFF

A symbol can be used to create Array of symbols that have direct access by index. Array of symbols have a capacity and can be more or less full. In array one or more symbols can have value NUL = U+0000. This is also the default value used for string initialization.

## String type

In EVE There are two types of strings. Single quoted and double quoted strings. They are using different internal representation but same encoding: UTF8. Single quoted strings are immutable and can store single line of text. Double quoted strings are complex data structured stored as rope or radix tree. 

* Single quoted string, has default capacity 1024 bytes;
* Double quote strings have unrestricted capacity;

### String: declaration
String can be initialized with a constant using single quotes or double quotes. 
By default value of string is "" or '' is equivalent to Null; 

```
global
  String(24): short_string := '' ** this string can hold 24 symbols, 24*4 = 96 bytes
  String: string_name      := '' ** default capacity 1024 can hold 256 ASCII symbols
  Text:   text_name        := "" ** variable capacity string can hold many rows
```

### String: mutability
In EVE strings are mutable. If you use `:=` new memory is allocated. If you use a modifier: `+=` the string is fill too capacity. If the capacity is over the limit you will get an error: "capacity overflow".

**Example:**
```
method: test_string()
  String : str := 'First value'  
  String : ref := 'Second value' 
process  
  expect (str <> ref) ** different value
  expect (str != ref) ** different locations  
  
  ref :: str  ** borrow reference
  expect (str =  ref) ** same value
  expect (str == ref) ** same location  
  print (ref)  ** 'First value'
  
  ** if we modify str, ref will not be modified
  str := 'Third value' ** new string location
  expect (str != ref)  ** different locations  
  ** ref remain unmodified
  print (ref)  ** 'First value'
return;
```

**Note:** You can create garbage in EVE if you loose reference to strings.

### String: comparison

* Two strings are compared using relation operators: { =, <>, <, >, >=, <= }; 
* Two strings that have identical characters are equivalent regardless of quotation;
* The length of the string is the number of represented characters: '' is counting 0; 

**Example:**

```
print ('this' = 'this')    ** True (same value)
print ("this" = 'this')    ** True (same value)
print (' this' <> 'this')  ** True (not same value)
print ('this ' <> 'this')  ** True (not same value)
```

### Null strings

We can test if a string is null using "is Null" expression.

```
given 
  String: str := ""
begin 
  expect (str is Null)
  expect (str = '')
  expect (str = "")
ready 
```

## Calendar date

In EVE we represent calendar date.

**Date storage**

* Date type is internally stored as number on 4 bytes;
* First byte store the day, second byte store the month;
* Last 2 bytes store the year; 

**Date literals**

When can create a date literal using 3 reversible functions:

* YDM => "YYYY/DD/MM"
* DMY => "DD/MM/YYYY"
* MDY => "MM/DD/YYYY"

**Note:** A reversible function is overloaded.

```
given
  Date: date
begin
  date := "2019/01/30" -> YDM
  date := "30/01/2019" -> DMY
  date := "01/30/2019" -> MDY
ready  
```

**Date printing**

Date representation can be changed with each print by using date format.
```
   print(date.YDM())
   print(date.DMI())
   print(date.MDI())   
```

## Time Duration

Time data type can be used to represent duration.

* EVE duration can represent minimum 1 millisecond.
* EVE duration can represent maximum 4294967296 hours.

**Representation**
Time is represented as a number on 8 bytes.

* First 2 bytes are the milliseconds.
* Next  2 bytes are representing seconds and minutes.
* Last  4 bytes represents hours.

**Conversion**

Time format is created using two reversible functions: T12() and T24()

*  T12 accept format ("hhhh:mm:ss,9999ms") 
*  T24 accept format ("hhhh:mm:ssxx, 9999ms" )

ss: can be 0..60 seconds  
xx: can be: (am/pm)

**default zero time**
```
given
  Time: time ** '00:00' 
```

**Example**

```
given
  Time: time1, time2, time3 
begin
  time1 := "23:63" -> T24   
  time2 := "23:63:59,99" -> T24   
  time3 := "11:63:59pm,99ms" -> T12   
ready;
```
**Read next:** [Composite Types](composite.md)