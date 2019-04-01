## Data Types

EVE is data oriented language. There are two kind of data types:

* Basic Types
* Composite Types

## Basic Types

Basic types are abstract wrappers to native types. 

| type     | description
|----------|----------------------------------------------------
| Integer  | integer on 64 bits (signed)
| Natural  | integer on 64 bits (unsigned)
| Real     | double precision number (signed)
| Rational | fixed precision number (signed)
| Null     | Is a reference type that represents Null reference


## Composite Types
Composite data types are unions of data elements of heterogeneous types.
 
| type     | description
|----------|----------------------------------------------------
| Ordinal  | Enumeration of ideas, cases or terms
| Record   | Heterogeneous collection of elements in a database
| String   | Create an ASCII string ('delimited using single quotes')
| Unicode  | reserved but not used in level1 ("delimited with double quotes")
| Logic    | Is a Ordinal type having values {⊥, ⊤}


## Collections
Collections are groups of data elements of same type.

| type     | description
|----------|----------------------------------------------------------------
| List     | Dynamic unsorted enumeration of values or objects
| Table    | Enumeration of (key:value) pairs unique sorted by key
| Cluster  | Enumeration of unique elements of the same type sorted by value

## User Defined

A data type can be _defined_ using symbol "<:".

**Syntax:**
```
define
  type <type_name> <: <super_type> ( parameters );
```
**Notes:**

* Users can define new types as subset or group of basic types;
* A module can _import_ defined types or from other modules;
* A data type is declared in a _define_ region;

**Example:**
```
define
  type Point <: Record ( a, b ∈ Integer);

aspect main() is
  p1, p2 ∈ Point;      -- implicit constructor
  p3 := {1,1} ∈ Point; -- initial value for Point
  begin
  -- modification using constants
    p1.a := 1;
    p1.b := 2;  
    
    -- modification using literal
    p2 := {2, 2};
  ready; 
  print ("p1 = (a:#n, b:#n)" <+ (p1.a,p1.b));
  print ("p2 = (a:#n, b:#n)" <+ (p2.a,p2.b));  
over;
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
 Discrete:    | Integer, Natural;
 Continuous:  | Real, Rational, Complex;

### Discrete numbers:

|type    |Chars  |Bytes|min |max   |maximum number	
|--------|-------|-----|----|------|-------------------------
|Integer |20     |8    |-2⁶³|2⁶³-1 |≤ 9,223,372,036,854,775,807
|Natural |20     |8    |0   |2⁶⁴-1 |≤ 18,446,744,073,709,551,615
 
For conversion into characters:

* The number of characters required for integer numbers is 20. (19+sign);
 
### Real numbers

The type _Real_ is represented using floating precision numbers.   
Floating decimal numbers are most simply described by 3 integers:

* s: a sign (0 or 1)  
* c: a coefficient  
* n: an exponent   

The numerical value of a finite number is −1ˢ × c × 2ⁿ
Using this formula EVE define one single type: Real.

Real is double-precision 64-bit IEEE 754:  
sign has 1bit, exponent has 11 bits and coefficient has 52 bits;

|type     |Digits |Bytes|maximum number	
|---------|-------|-----|----------------------------------
|Real     |15     |8    |≤ 1.8 × 10³⁰⁸

Precision Real numbers is variable depending on the size of the number. The number of digits represents the largest number that can be converted from string format into a Real and back without loosing any digit. Think of it like a digital display from a packet calculator.

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
aspect main()
  -- declare variable
  i ∈ Integer; 
  n ∈ Natural;
  r ∈ Real;
  -- modify variables
  i := 9223372036854775807;
  n := 18446744073709551615;
  r := 0.25;  
over;
```

### Complex number
A complex number is a number that can be expressed in the form (a + bj), where a and b are _real_ numbers and j is the imaginary unit, that satisfies the equation j^2 := −1. In this expression, a is the real part and b is the imaginary part of the complex number.

   Example     | Description
---------------|-------------------------------------------------------------------------
  (1+2.56j)    | Complex number. (a+bj). When b is 0 the number is compatibe with a real number.
  (-3.5-2j)    | Complex number. (-a-bj). Both a and b can be positive or negative real numbers.

### Rational number
A rational number is a fraction between two numbers Q := Z/N where Q is the rational number, Z is Integer and N is Natural number. So Q number is using 8 + 8 := 16 bytes. The division is not executed but postponed until the number is used in an expression after simplification.

## Data Coercion
In computer science coercion is used to implicitly or explicitly change  an entity of one data type into another of different type. This is done to take advantage of type hierarchies and type representations. 
If not designed properly the coercion can be a fatal mistake. EVE is a safe language so we do only safe coercion.

## Polymorphic operators
In mathematics there are very few operators: {+, -, ÷ , ⋅} that can operate with many kind of numbers. So the numeric operators are not very specific to a number type. This property of operators is called _"polymorphic"_ and is a problem for computer science.

Some languages define different operators for integers and floating decimal numbers. For example in OCaml the operator "/" can divide integers while "/." can divide floating numbers. This is unexpected for a mathematician or engineer. Therefore some other languages are introducing polymorphic operators.

## Implicit data conversion
In EVE the arithmetic operators are polymorphic. Numeric operators can do implicit data conversion 
to accommodate the data types and return an accurate result.  Automatic conversion is possible only when there is no risk of loosing data precision. If there is a loss of data the program will generate a _run-time error_.

Implicit conversion is possible and _safe_ in this direction:

Integer -> Natural -> Real -> Complex.

Explicit conversion is possible but _unsafe_ in this direction:

Complex -> Real ->  Natural -> Integer. 

```
given:
  a := 2 ∈ Integer;
  b := 1.5 ∈ Real;
begin:
  b := a; -- this implicit cast is possible b ≡ 2.0
  b := a + 3.5; -- add 3.5 then assign result to b ≡ 5.5
  a := b;       -- error: can not assign Real to Integer
  a := 1.5;      -- error: can not assign Real to Integer
ready;
```

## Explicit coercion
Explicit coercion is a _forced conversion_. Can be used to convert backwards from higher data range to lower data range or from continuous numbers to discrete numbers. This however can cause a data or precision loss. Explicit coercion is using a functions. The function apply to an expression or variable that need coercion and return a result of a new data type.

Examples of explicit coercion:   
```
given:
  a := 0 ∈ Integer;
  b := 1.5 ∈ Real;
begin:
  -- explicit coercion lose (0.5)
  a := floor(b); 
  print(a); -- will print: 1
 
  -- explicit coercion add (0.5)
  a := ceiling(b); 
  print(a); -- will print: 2
ready;
```

**Number to a string**

```
given:
  s ∈ String;
  v := 1000 ∈ Integer;
begin:  
  s := format(v); -- explicit coercion s:="1000"
begin:  
```

**String to a number**

This can be done using the casting function parse(), only if the string contains a number. Otherwise the conversion fail and will rise and exception. 

```
given:
  v ∈ Integer;
  b ∈ Real;
  s := "1000" ∈ String;
  r := "200.02" ∈ String;
begin:
  v := parse(s); -- make v ≡ 1000
  v := parse(r); -- make v ≡ 200 and decimal .02 is lost
  b := parse(r); -- make b ≡ 200.02 and decimal .02 is preserved
ready;
```

**Note:** 
 Build-in functions that are located in EVE "default" module:
 
 { parse(), format(), ceiling(), floor() }
 
 This module is one of the standard modules that are automatically included in any EVE program. 


## Type inference

This is a logical deduction of variable type from literal or constructor using ":=" operator.

**Example:**

```
-- Define a list of 10 elements using type inference:
given:
  ls := (0,1,2,3,4,5,6,7,8,9);
begin:
  print(ls.type()); --> List
ready;  
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
9.9          | Real
1E2          | Real
1e2          | Real
1/123        | Rational

**Zero literals**

Literal    | Type
-----------|---------------
[]         | Array
{}         | Cluster/Hash
()         | List
""         | Text
''         | String
0          | Integer
0.0        | Real
           
**Collection literals**

Literal      | Type
-------------|-----------------
('a','b','c')| List    of  String
(1,2,3)      | List    of  Integer
[1,2,...]    | Array   of  Integer
{1,2,...}    | Cluster of  Integer
{a,b,c}      | Ordinal
(x:'b',y:'d')| Record
{1:'a',2:'b'}| Hash

       
### Type verification
Type inference is welcome when type is difficult to create.

Examples of type inference:

```
given:
  v := T;
  r := (name:"test", age:"24"); 
  m := {"key1":"value1","ley2":"value2"}; 
begin:
  -- check variable types using introspection
  print("v is of type " + type(v));
  print("r is of type " + type(r));
  print("m is of type " + type(m));
ready;
```
run test  
```
v is of type Logic
r is of type Record  
m is of type Hash  
```

## Check type

In EVE the type is first class value. For type introspection we can use:

1. built-in type() function
2. operator "is"

```
given:
  i  := 1.5 ∈ Real;
  it ∈ Type;
begin:
  when i ∈ Real then
    print("Yes i is Real");
  else:
    print("No i is not Real");
  ready;
  it := type(i);
  print("type of i is #t" <+ it)
ready;
```

## Partial Inference

Sometimes the type is partially specified to improve type declaration.

```
define
  -- member type is inferred from literal 
  a := 0 ∈ Array[](10);
```
## Logic type

In Latin the "falsus" and "verum" are translated to false and true.

* falsus := ⊥ defined by ⊥ := ¬ ⊤  and  ( P ∧ ¬P )
* verum  := ⊤ defined by ⊤ := ¬ ⊥  and  ( P ∨ ¬P )

name     |    value      | binary 
---------|---------------|------------------------------
False    | Logic.F       | 00000000 00000000 
True     | Logic.T       | 00000000 00000001

**syntax**
```
define
 <variable_name> ∈ Logic; --> default F
```


**internal design**

Probably best to define Logic type is Ordinal:
```
define
  Logic <: Ordinal { .T , .F };
```

**Relation Operators**

Logic values can be compared using relation operators:    

{↔, >, <, ≤, ≥}.  

**Logic Operators**
Logical operators are expecting logical operands. 

Symbol  | Description
--------|-------------------------------------------
  ∨     | logical OR
  ∧     | logical AND
  ¬     | logical NOT


Table of truth for logical operators: 

 A    | B   |! A | A & B | A \| B | A ~ B
------|-----|----|-------|--------|-------
 T    |T    | F  | T     | T      | F    
 T    |F    | F  | F     | T      | T   
 F    |T    | T  | F     | T      | T
 F    |F    | T  | F     | F      | F

**Logical expressions**

A logical expression is a demonstration or logical deduction having result T or F. The order of operations can be controlled using operator precedence and parentheses (). 

Operator precedence: {¬, ∧, ∨, ~}

Result of logical expressions can be used into a conditional statement to make a decision. 
Also results of logical expressions can be stored in logical variables to be used later in other conditions.

## Ordinal Type

A ordinal is an enumeration of terms. It is an ordered list of identifiers that can represent things, ideas, concepts, keywords. Each item has an identifier name that can be uppercase, lowercase or mixed . To each item we associate a value that is two Byte number that starts from 0 to N. Maxim number of items is 65535.

**Syntax:**
Ordinal type is usually a finite set that can be enumerated using a literal. In mathematics a set of items is represented using curly brackets {} separated by comma. In the next example we define the days of the week in EVE:

```
define
  <name> <: Ordinal {symbol := <value>, ... };

```

## Usage
Ordinal type is suitable for creation of options that can be used for switch statement. 

* Value of first element can be specified. If is not specified it starts from: 1.    
* Values of next elements can not be specified. That is next element is previous element +1.   
* Elements declared in a Ordinal type are public is we use "." prefix

**Example:**
```
define
  Day <: Ordinal {.Sunday:1, .Monday, .Tuesday, .Wednesday, 
        .Thursday, .Friday, .Saturday};  

aspect main() is  
  message ∈ String;
  given:
    today := today() ∈ Day;  
  split
    when today ∈ (Friday, Saturday, Sunday) do
      message:='weekend';
      ...
    when today = Monday do
      message:='first workday';
    when today = Friday do
      message:='last workday';
  other
    message:='middle of the week';
  split;
  print('Is', message);  
over;
```
**Note** For private enumerations you can use a record type.

**Range**
We can use Ordinal to create a range of values:
```
when if today ∈ [Monday..Friday] do
   print ("Have a nice day!");
else:
   print ("Have a happy weekend!");  
when;
```

**Operators**
Ordinal is a set of Natural numbers. The Ordinal type is ordered, therefore is suitable for relation operators: { <, >, ≤, ≥ }. It can be incremented and decremented using += and -=. We can perform addition, subtraction, multiplication with ordinal values.

```
given:
  v := Friday ∈ Day;
begin:
  v += 1; 
  expect v ≡ Saturday;
ready;  
```

## Gradual typing

Gradual typing is a type system in which some variables may be given:types and the correctness of the typing is checked at compile-time (which is static typing) and some variables may be left un-typed and eventual type errors are reported at run-time (which is dynamic typing). To declare gradual types we use a polymorphic type called "Variant".

**Variant Types**

A Variant is a polymorphic variable that can have multiple types but only one at a time:

**Syntax:**
```
define
  <variant_name> <: Variant  of (<Type> | <Type> | ... );

global  
  v ∈ <variant_type>;
```

## Variant Properties

* Variant data type is a reference;
* Variant data type is assigned at runtime;
* One variant can have a single value at a time;
* One variant is a "union" of several types

## Making a null-able type

For this we need Null type. 

* The Null type is usually String and is a curious type.
* It can have only one value: Null and is not printable.

**Examples:**
```
define
  Number <: Variant of (Integer | Real | Null) ;

global
  x := Null ∈ Number;
  
```

## Usability

A variant can change its data type at runtime:

```
given:
  v,x,t ∈ Real | Integer;
begin:
  -- positive example
  v := 1;   -- v is Integer
  x := 1.5; -- x is Real    
  t := 1/2; -- make t Real
  
  -- safe conversion
  t := 120; -- safe conversion
  
  -- negative examples
  v := x;  -- ERROR: v is Integer
ready;
```

## Reference

A variant is a way to create a generic aspect.

```
aspect invert(x, y ∈ (Integer | Real)):
  i  ∈ (Integer | Real); 
  assert !(type(x) = type(y));  
  
  i := x; -- intermediate value
  y := x; -- first  switch
  x := i; -- second switch
over;

aspect main:
  x,y ∈ Integer;
  a,b ∈ Real;
  
  -- invert two Integer numbers
  x := 10;
  y := 20;  
  invert(x,y);    
  
  --invert two Real numbers
  a := 1.5;
  b := 2.5;  
  invert(a,b);  
over;
```

## Strings 

There is one single type of string with two literal notations. 

* String, has limited capacity default 255 characters;
* Double quote constants are used for Text and Unicode;
* Single quote constants are limited to ASCII;
* Double quote is escaped using single quote two times: "''double quoted''"

**Note:** 
Single quoted character is similar to "char" data type from C language.

## String declaration
String can be initialized with a constant using single quotes or double quotes. 
By default value of string is "", equivalent to empty symbol: ∅; 

```
define
  <string_name> := '"'  ∈ String; -- limited 255 capacity string
  <string_name> := "''" ∈ Text;   -- unlimited Unicode string
```

## Mutability
In EVE strings are immutable. If we use a modifier ":=" new memory is allocated.

**Example:**
```
aspect test_string:
  str, ref ∈ String; -- initial "" 
  begin
    str := 'First value';  -- new reference
    ref :=  str;           -- borrow reference
    str := 'First value';  -- new reference
  ready;
  expect  (str ≡ ref); -- equivalent value
  expect !(str = ref); -- different references
over;
```

## String comparison

* Two strings are compared using relation operators: { ≡, <, >, ≥, ≤ }. 
* Two strings that have identical characters are equivalent regardless of quotation. 
* The length of the string is the number of represented characters: '' is counting 1 

**Example:**
```
'this'  ≡ 'this';   --> ⊤
'this ' ≡ 'this';   --> ⊥
' this' ≡ 'this';   --> ⊥
```

## Null strings

We can test if a string is null using "is Null" expression.

```
 str ∈ String; 
 print("str is null") if str is Null; 
```

## Calendar

In EVE we represent calendar date.

**Date storage**

* Date type is internally stored as number on 4 bytes.
* First byte store the day, second byte store the month.
* Last 2 bytes store the year. 

**Date literals**

When can create a date literal using 3 reversible functions:

* YDM => "YYYYDDMM";
* DMY => "DD/MM/YYYY";
* MDY => "MM/DD/YYYY";

**Note:** A reversible function is overloaded.

```
given:
  date ∈ Date;
begin:
  date := "2019/01/30" -> YDM;
  date := "30/01/2019" -> DMY;
  date := "01/30/2019" -> MDY;
ready;  
```

**Date printing**

Date representation can be changed with each print by using date format.
```
   print(date.YDM());
   print(date.DMI());
   print(date.MDI());   
```

## Duration

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

*  T12 accept format ("hhhh:mm:ss,9999ms"); 
*  T24 accept format ("hhhh:mm:ssxx, 9999ms" );

ss: can be 0..60 seconds  
xx: can be: (am/pm)

**default zero time**
```
given:
  time ∈ Time; --> '00:00' 
```

**Example**

```
given:
  time1, time2, time3 ∈ Time; 
begin:
  time1 := "23:63" -> T24;   
  time2 := "23:63:59,99" -> T24;   
  time3 := "11:63:59pm,99ms" -> T12;   
ready;
```
**Read next:** [Composite Types](composite.md)