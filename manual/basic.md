## Data Types

EVE is a gradual typed language. Next I will describe basic types:

**bookmarks**

* [Basic](#basic-types)
* [Numeric](#numeric-types)
* [Composite](#composite-types)
* [Collections](#collections)
* [Physical](#physical-types)
* [User defined](#user-defined)
* [Data coercion](#data-coercion)
* [Type inference](#type-inference)
* [Default types](default-types) 
* [Ordinal type](ordinal-type)
* [Logical type](logical-type)
* [Gradual typing](#gradual-typing)
* [String type](#string-type)
* [Calendar date](#calendar-date)
* [Time duration](#time-duration)

## Basic Types

Basic types are fixed size native types. 

| type     | description
|----------|-------------------------------------------------------
| Char     | integer on 8  bit (unsigned) (ASCII)
| Symbol   | integer on 32 bit (unsigned) (UTF32)
| Integer  | integer on 64 bit (signed)
| Natural  | integer on 64 bit (unsigned)
| Real     | double precision number on 8 bit (signed) 
| Ordinal  | Enumeration of ideas, cases or terms
| Logic    | Is a Ordinal subtype having values:  False = 0, True = 1
| Date     | Calendar date     
| Time     | Calendar time

## Composite Types

Composite data types are unions of data elements.
 
| type     | description
|----------|---------------------------------------------------------------
| Null     | is a reference type = Null constant reference
| String   | Limited capacity string: ('single quoted')
| Text     | Unlimited capacity string: ("double quoted")
| List     | Dynamic unsorted enumeration of values or objects of same type
| Table    | Enumeration of (key:value) pairs unique sorted by key
| Set      | Enumeration of unique elements of the same type sorted by value
| Record   | Heterogeneous collection of elements with fix structure 


## Physical Types

EVE is going to use support physical measurement units:

| type      | description
|-----------|---------------------------------------------------------------
| Duration  | Delta time / duration hours/minutes/seconds
| Angle     | Degree angle between two lines
| Length    | Dimension of objects or distance
| Distance  | The travel distance between to points in space
...

See also: [UCUM](http://unitsofmeasure.org/ucum.html)

**note:** 
* In the future we will cover a complete set of physical types
* Physical types include measurement unit and transformation methods 

## Numeric Types

In EVE we can have two categories of numbers:

 Category     | EVE Types
--------------|------------------------------------------------------------
 Discrete:    | Integer, Natural
 Continuous:  | Real

### Discrete numbers:

|type    |Chars  |Bytes|min |max   |maximum number	
|--------|-------|-----|----|------|-------------------------
|Integer |20     |8    |-2⁶³|2⁶³-1 |≤ 9,223,372,036,854,775,807
|Natural |20     |8    |0   |2⁶⁴-1 |≤ 18,446,744,073,709,551,615
 
For conversion into characters:

* The number of characters required for integer numbers is 20. (19+sign)
* For Real numbers, conversion into characters is controled by #precision directive
 
### Real numbers

The type _Real_ is represented using floating precision numbers.   
Floating decimal numbers are most simply described by 3 integers:

* s: a sign (0 or 1)  
* c: a coefficient  
* n: an exponent   

The numerical value of a finite number is −1ˢ × c × 2ⁿ
Using this formula EVE define one single type Real.

Real: is double-precision 64-bit IEEE 754:  
sign has 1bit, exponent has 11 bits and coefficient has 52 bits;

|type     |Digits |Bytes|maximum number	
|---------|-------|-----|----------------------------------
|Real     |15     |8    |≤ 1.8 × 10³⁰⁸

Precision Real: numbers is variable depending on the size of the number. The number of digits represents the largest number that can be converted from string format into a Real: and back without loosing any digit. Think of it like a digital display from a packet calculator.

**Numeric literals**

   Example     | Description
---------------|-------------------------------------------------------------------------
0              | integer zero
1234567890     | integer number using symbols: {0,1,2,3,4,5,6,7,8,9}
0.5            | real number use symbols: {.,0,1,2,3,4,5,6,7,8,9}
0.0            | real number

**example**

```
method main():
**declare variables
  Integer: i; 
  Natural: n;
  Real: r;
process  
**modify variables
  i := 9223372036854775807;
  n := 18446744073709551615;
  r := 0.25;
return;
```

**See also:** [scientific notation](https://en.wikipedia.org/wiki/Scientific_notation#Other_bases)

## User Defined

User types can be _defined_ using symbol "<:" and keyword: "type".

**Syntax:**
```
type type_name <: type_descriptor (parameters)
```
**Notes:**

* Users can define constrained sub-types or group of basic types;
* A module can _import_ public types defined in other modules;
* A data type can be declared only in module global context;

**Example:**
```
type Point <: Record (Integer: a, b );

method main():
  Point: p1, p2;      -- use implicit constructor
  Point: p3 := {1,1}; -- initial value for Point
process
**modification using constants
  p1.a := 1;
  p1.b := 2; 
  
**reset Point using a literal
  p2 := {2, 2};
  
  print ("p1 = (a:#n, b:#n)" <+ (p1.a,p1.b));
  print ("p2 = (a:#n, b:#n)" <+ (p2.a,p2.b));  
return;
```
output:
```
p1 = (a:1, b:1)      
p2 = (a:2, b:2)
```

## Data Coercion
In computer science coercion is used to implicitly or explicitly change  an entity of one data type into another of different type. This is ready to take advantage of type hierarchies and type representations. 
If not designed properly the coercion can be a fatal mistake. EVE is a safe language so we do only safe coercion.

### Implicit coercion
In EVE the arithmetic operators are polymorphic. Numeric operators can do implicit data conversion to accommodate the data types and return an accurate result.  Automatic conversion is possible only when there is no risk of loosing data precision. If there is a loss of precision we can end-up with a _run-time error_. To prevent this EVE will implement a safe compile-time check.

Implicit conversion is possible and _safe_ in this direction:

Integer -> Natural -> Real -> String.

Explicit conversion is possible but _unsafe_ in this direction:

String -> Real ->  Natural:-> Integer 

```
given
  Integer: a := 2;
  Real:    b := 1.5; 
do
  b := a;       -- this implicit cast is possible b = 2.0
  b := a + 3.5; -- add 3.5 then assign result to b = 5.5
  a := b;       -- error: can not assign Real: to Integer
  a := 1.5;     -- error: can not assign Real: to Integer
done;
```

### Explicit coercion
Explicit coercion is a _forced conversion_. Can be used to convert backwards from higher data range to lower data range or from continuous numbers to discrete numbers. This however can cause a data or precision loss. Explicit coercion is using a function.

Examples of explicit coercion:   
```
given
  Integer: a := 0;
  Real:    b := 1.5;
do
  ** explicit coercion lose (0.5)
  a := floor(b);
  print (a); -- will print: 1
 
  ** explicit coercion add (0.5)
  a := ceiling(b); 
  print (a); -- will print: 2

  ** explicit coercion rounding:  
  a := round(b);
  print (a); -- will print: 2
done;
```

**Number to a string**

```
given
  String: s; 
  Integer: v := 1000;
do  
  s := format(v); -- explicit coercion s = '1000'
done;
```

**String: to a number**

This can be ready using the casting function parse(), only if the string contains a number. Otherwise the conversion fail and will rise and exception. 

```
given
  Integer: v; 
  Real:    b;
  String: s := '1000';
  String: r := '200.02';
do
  v := parse(s); -- make v = 1000
  v := parse(r); -- make v = 200 and decimal .02 is lost
  b := parse(r); -- make b = 200.02 and decimal .02 is preserved
done;
```

**Note:** 
 Build-in functions that are located in EVE _default_ library:
 
 { parse(), format(), ceiling(), floor() round()}
 
 This module is one of the standard modules that are automatically included in any EVE program. 

Details: [Numeric Format](processing.md#numeric-format)

## Type inference

This is a logical deduction of variable type from literal or constructor using ":=" operator.

**Example:**

```
** Define a list of 10 elements using type inference:
given
  List: ls := (0,1,2,3,4,5,6,7,8,9);
do
  print  ls.type(); -- List[Integer]
  expect ls is List[Integer];
done 
```

## Default types
Literals are representations of specific particular data type in source code.

**Basic types**
Next notation use "9" to show any digit in range [0..9].

Literal      | Type
-------------|-----------------
 9           | Integer
-9           | Integer
0x9ABCDEF    | Natural
0b1010101    | Natural
9.9          | Real
U+0001       | Symbol

**Zero literals**

Literal    | Type
-----------|---------------
[]         | Array
{}         | Set/Table
()         | List
""         | Text
''         | String
0          | Integer
0.0        | Real
           
**Collection literals**

Literal      | Type
-------------|-----------------
{a:0,b,c}    | Ordinal
(`a`,`b`,`c`)| List[Symbol]
('a','b','c')| List[Char]
("a","b","c")| List[Text]
(1,2,3)      | List[Integer]
[1,2,...]    | Array[Integer]
{1,2,...}    | Set[Integer]
(x:'b',y:'d')| Record
{1:'a',2:'b'}| Table


### Type Inference

Sometimes the type is partially specified to simplify type declarations:

```
define
  ** member type is inferred from literal: 0 = Integer
  Array[](10): a := 0;
```
       
### Type verification

We can verify the type using "is" operator:

```
given
  Record: r := (name:"test", age:"24"); 
  Table:  t := {('key1':"value1"),('ley2':"value2")};
do
  ** check variable types using introspection
  expect r.name  is Text;
  expect r.age   is Text;
  expect t.key   is String;
  expect t.value is Text;
done;
```

## Printing type()

For type introspection we can use type() built-in function:

```
given
  Real: i := 1.5;
do
  expect i is Real;
  print "type of i is \s" <+ type(i);
done;
```

## Polymorphic operators
In mathematics there are very few operators: {+, -, ÷ , ⋅} that can operate with any kind of numbers: negative, positive, rational or real. So the numeric operators are not very specific. This property of operators is called _"polymorphic"_ and is a problem for computer science.

Some languages define different operators for integers and floating decimal numbers. For example in OCaml the operator "/" can divide integers while "/." can divide floating numbers. This is unexpected for a mathematician. Therefore EVE languages is using polymorphic operators.

Operators are mapped to functions. To design polymorphic operators we overload the function signature using type dispatch. The dispatch is happening by left side operand first, this is the leading operand. For unary operators there is only right side operand so this becomes the leading operand.

## Ordinal type

Ordinal type is an ordered list of identifiers that can represent things, ideas, concepts, keywords. Each item has an identifier name that can be uppercase, lowercase or mixed . To each item we associate a value that is two byte number starting from 0 to N. Maxim number of items is 65535.

**Syntax:**
Ordinal type is usually a finite set that can be enumerated using a literal. In mathematics a set of items is represented using round brackets () separated by comma. In the next example we define the days of the week in EVE:

```
type <type_name> <: Ordinal (symbol:<value>, ... );

```

## Usage
Ordinal type is suitable for creation of options that can be used for switch statement. 

* Value of first element can be specified. If is not specified it starts from: 1.    
* Values of next elements can not be specified. That is next element is previous element +1.   
* Elements declared in a Ordinal type are public is we use "." prefix

**Example:**
```
type Day <: Ordinal (.Sunday:1, .Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday);

method main():
  String: message;
process  
  given
    Day: today := today();
  quest today:
    match (Friday, Saturday, Sunday) do
       message:='weekend';
      ...
    match (Monday) do
       message:='first workday';
    match (Friday) do
       message:='last workday';
  none
    message:='middle of the week';
  done;
  print('Is', message);
return;
```
**Note** For private enumerations you can use a record type.

**Range**
We can use Ordinal to create a range of values:
```
when (today <+ [Monday..Friday]) do
   print ("Have a nice day!");
else
   print ("Have a happy weekend!");
done;
```

**Operators**
Ordinal is a discrete numeral type so it has support for relation operators: { =, <, >, <=, >= }. It can be incremented and decremented using += and -=. We can perform addition, subtraction, multiplication.

```
** using type Day declared before
given
  Day v := Friday;
do
  v += 1; 
  expect v = Saturday;
done;
```

## Logical type

In Latin the "falsus" and "verum" are translated to false and true.

* falsus := ⊥ defined by ⊥ := ¬ ⊤  and  ( P ∧ ¬P )
* verum  := ⊤ defined by ⊤ := ¬ ⊥  and  ( P ∨ ¬P )

name     |    value      | binary 
---------|---------------|------------------------------
False    | Logic.False   | 00000000 00000000 
True     | Logic.True    | 00000000 00000001

**syntax**
```
variable
  Logic: variable_name; -- default False
```

**internal design**

Probably best to define Logic type is Ordinal:
```
type Logic <: Ordinal { .False , .True };
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

Gradual typing is a type system in which some variables may be given types and the correctness of the typing is checked at compile-time (which is static typing) and some variables may be left un-typed and eventual type errors are reported at run-time (which is dynamic typing). To declare gradual types we use a polymorphic type called "Variant".

**Variant Types**

A Variant is a polymorphic variable that can have multiple types but only one at a time:

**Syntax:**
```
type Variant_Name <: Variant (type_name | type_name | ... );

variable
  Variant_Name: v;
```

## Variant Properties

* Variant data type is assigned at runtime;
* One variant can have a single value at a time;
* One variant is a "union" of several types

## Making a null-able type

For this we use a special type Null 

* The Null type is a curious type;
* It can have only one value = Null;

**Examples:**
```
type Number <: Variant (Integer | Real | Null);

variable
  Number: x := Null;
  
```

**Usability**

A variant can establish its data type at runtime:

**example:**
```
given
  Real | Integer: v, x ,t;
do
  ** positive example
  v := 1;     -- v is Integer
  x := 1.5;   -- x is Real:    
  t := 1 / 2; -- make t Real
  
  ** safe conversion
  t := 12; -- t is Real
  
  ** negative examples
  v := x;  -- ERROR: v is Integer 
done;
```

A variant is a way to create a generic method.

```
method switch(Integer | Real: x, y):
  Integer | Real: i
process  
  expect type(x) = type(y);
  
  i := x; -- intermediate reference
  x := y; -- first  switch
  y := x; -- second switch
return;

method main():
  Integer: y;
  Real: a, b;
process  
  ** invert two Integer: numbers
  x := 10;
  y := 20;  
  switch(x, y);
  expect (x = 20) and (y = 10);
  ** invert two Real: numbers
  a := 1.5;
  b := 2.5;
  switch(a, b);
  expect (a = 2.5) and (b = 1.5);
return;
```

## Single symbol

Symbols are Unicode UTF32. That is using 32 bit integer:

* Single-quoted strings like: 'α'
* U+HHHH   from: U+0000   to U+FFFF
* U-HHHHHH from: U+000000 to U+FFFFFF

**usability**
A symbol can be used to create an Array of symbols that have direct access by index. Array of symbols have a capacity and can be more or less full. In array one or more symbols can have value NUL = U+0000. This is also the default value used for string initialization.


## Calendar date

In EVE we represent calendar date.

**Date storage**

* Date type is internally stored as number on 4 bytes;
* First byte store the day, second byte store the month;
* Last 2 bytes store the year; 

**Date literals**

When can create a date literal using 3 reversible functions:

* YDM = "YYYY/DD/MM"
* DMY = "DD/MM/YYYY"
* MDY = "MM/DD/YYYY"

**Note:** A reversible function is overloaded.

```
given
  Date: date;
do
  date := "2019/01/30" -> YDM;
  date := "30/01/2019" -> DMY;
  date := "01/30/2019" -> MDY;

  **printing**  
  print date.YDM();
  print date.DMI();
  print date.MDI();  
done;
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
  Time: time; -- '00:00' 
```

**Example:**

```
given
  Time: time1, time2, time3; 
do
  time1 := "23:63" -> T24;
  time2 := "23:63:59,99" -> T24;
  time3 := "11:63:59pm,99ms" -> T12;
done;
```
**Read next:** [Composite Types](composite.md)