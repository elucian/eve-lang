## Data Types

EVE is a gradual typed language. Next I will describe basic types:

**bookmarks**

* [Scalar](#scalar-types)
* [Primitive](#primitive-types)
* [Composite](#composite-types)
* [Collections](#collections)
* [Physical](#physical-types)
* [Alias](#Alias)
* [Data coercion](#data-coercion)
* [Type inference](#type-inference)
* [Default types](default-types) 
* [Ordinal type](Ordinal-type)
* [Logical type](logical-type)
* [Gradual typing](#gradual-typing)
* [Calendar date](#calendar-date)
* [Time duration](#time-duration)

## Scalar Types

Scalar types are fixed size data types mapped to native OS types. 

| reference|native|description
|----------|------|------------------------------------------------------
| Byte     | u8   |Unsigned on 8  bit 
| Word     | u16  |Unsigned on 16 bit 
| Binary   | u32  |Unsigned on 32 bit 
| Natural  | u64  |Unsigned on 64 bit 
| Short    | i16  |Signed on 16 bit 
| Integer  | i32  |Signed on 32 bit
| Long     | i64  |Signed on 64 bit 
| Single   | f32  |Float precision number on 4 byte
| Double   | f64  |Float precision number on 8 byte

## Primitive Types

| reference| description
|----------|---------------------------------------------------------------
| Numeric  | Numeric variant that can be Null = ""
| Symbol   | Single Unicode symbol UTF-32
| Ordinal  | Enumeration of symbols, ideas or terms
| Date     | Calendar date     
| Time     | Calendar time
| Logic    | Is a Ordinal subtype having values:  False = 0, True = 1
| Domain   | Domain data type (x..y:ratio) 

## Composite Types

Composite data types are unions of data elements.
 
| type     | description
|----------|---------------------------------------------------------------
| String   | Limited capacity string:   ('single quoted')
| Text     | Unlimited capacity string: ("double quoted")
| List     | Dynamic unsorted enumeration of values or objects of same type
| Hash     | Enumeration of (key:value) pairs unique sorted by key
| Set      | Enumeration of unique elements of the same type sorted by value
| Object   | Base class for creation of plain simple objects
| Exception| Composite type derived from Object base class

**note:** 
* In the future we will cover a complete set of physical types
* Physical types include measurement unit and transformation methods 

## Numeric Types

In EVE we can have two categories of numbers:

 Category     | EVE Types
--------------|------------------------------------------------------------
 Discrete     | Byte, Word, Binary, Integer, Natural
 Continuous   | Single, Double, 

### Discrete numbers:

|type     |Chars  |Bytes|min |max   |maximum number	
|---------|-------|-----|----|------|-------------------------
|Integer  |20     |8    |-2⁶³|2⁶³-1 |≤ 9,223,372,036,854,775,807
|Natural  |20     |8    |0   |2⁶⁴-1 |≤ 18,446,744,073,709,551,615
 
For conversion into characters:

* The number of characters required for Integer numbers is 20. (19+sign)
* For Double numbers, conversion into characters is controled by #precision directive
 
### Double numbers

The type _Double_ is represented using floating precision numbers.   
Floating decimal numbers are most simply described by 3  Integers:

* s: a sign (0 or 1)  
* c: a coefficient  
* n: an exponent   

The numerical value of a finite number is −1ˢ × c × 2ⁿ
Using this formula EVE define two floating point types.

Single: is single-precision 32-bit IEEE 754:  
Double: is double-precision 64-bit IEEE 754:  

|type     |Digits |Bytes|maximum number	
|---------|-------|-----|----------------------------------
|Single   |7      |4    |≤ 3.4 × 10³⁸
|Double   |16     |8    |≤ 1.8 × 10³⁰⁸

Precision is variable depending on the size of the number. The number of digits represents the largest number that can be converted from string format into a Double: and back without loosing any digit. Think of it like a digital display from a packet calculator.

**Numeric literals**

Example | Description
--------|-------------------------------------------------------------------------
0       | Integer zero
123     | Integer number using symbols: {0,1,2,3,4,5,6,7,8,9}
1/2     | Single  number use symbols: {.,0,1,2,3,4,5,6,7,8,9}
0.5     | Double  number use symbols: {.,0,1,2,3,4,5,6,7,8,9}

**example**

```
routine main():
  Integer: i; // Initial value = 0
  Natural: n; // Initial value = 0
  Double : r; // Initial value = 0
process  
  alter i := 9223372036854775807;  //  maximum
  alter n := 18446744073709551615; //  maximum
  alter r := 1/2; //  0.5
return;
```

**See also:** [scientific notation](https://en.wikipedia.org/wiki/Scientific_notation#Other_bases)

## User types

User types can be _defined_ using symbols ":", "<:" and keyword: "type".

**Syntax:**
```
type type_name: Generic_Class {parameters}

```
**Notes:**

* Users can define constrained sub-types or group of basic types;
* A module can _import_ public types defined in other modules;
* A data type can be declared only in module global context;

## Data Coercion
In computer science coercion is used to implicitly or explicitly change  an entity of one data type into another of different type. This is ready to take advantage of type hierarchies and type representations. 
If not designed properly the coercion can be a fatal mistake. EVE is a safe language so we do only safe coercion.

**Implicit coercion**
In EVE the arithmetic operators are polymorphic. Numeric operators can do implicit data conversion to accommodate the data types and return an accurate result.  Automatic conversion is possible only when there is no risk of loosing data precision. If there is a loss of precision we can end-up with a _run-time error_. To prevent this EVE will implement a safe compile-time check.

Implicit conversion is possible and _safe_ in this direction:

Byte as Word as Binary as Natural as Integer as Single as Double.

Explicit conversion is possible but _unsafe_ in this direction:

Double as  Single as Integer as Natural as Binary as Word as Byte

```
given
  Integer: a := 2;
  Double:  b := 1.5; 
do
  alter b := a;       //  this implicit cast is possible b = 2.0
  alter b := a + 3.5; //  add 3.5 then assign result to b = 5.5
  alter a := b;       //  error: can not assign Double: to  Integer
  alter a := 1.5;     //  error: can not assign Double: to  Integer
done;
```

**Explicit coercion**
Explicit coercion is a _forced conversion_. Can be used to convert backwards from higher data range to lower data range or from continuous numbers to discrete numbers. This however can cause a data or precision loss. Explicit coercion is using a function.

Examples of explicit coercion:   
```
given
  Integer: a := 0;
  Double : b := 1.5;
do

**explicit coercion lose (0.5)
  alter  a := floor(b);
  write  a; //  will print: 1
 
**explicit coercion add (0.5)
  alter  a := ceiling(b); 
  print (a); //  will print: 2

**explicit coercion rounding:  
  alter  a := round(b);
  print (a); //  will print: 2
done;
```

**Number to a string**

```
given
  String : s; 
  Integer : v := 1000;
do  
  alter s := format(v); //  explicit coercion s = '1000'
done;
```

**string: to a number**

This can be ready using the casting function parse(), only if the string contains a number. Otherwise the conversion fail and will rise and exception. 

```
given
  Integer : v; 
  Double  : b;
  String  : s := '1000';
  String  : r := '200.02';
do
  alter v := parse(s); //  make v = 1000
  alter v := parse(r); //  make v = 200 and decimal .02 is lost
  alter b := parse(r); //  make b = 200.02 and decimal .02 is preserved
done;
```

**Note:** 
 Build-in functions that are located in EVE _default_ library:
 
 { parse(), format(), ceiling(), floor() round()}
 
 This module is one of the standard modules that are automatically included in any EVE program. 

Details: [Numeric Format](processing.md#numeric-format)

## Type inference

This is a logical deduction of data type from constant literals.

**Example:**

```
** Define a list of 10 elements using type inference:
given
  List: ls := [0,1,2,3,4,5,6,7,8,9]; //  initialized list of Integer
do
  print  ls.type(); //  List[Integer]
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
0b1010101    | Binary
9.9          | Double
U+0001       | Word
U-FFFFFFFF   | Binary

**Zero literals**

Literal    | Type
-----------|---------------
[]         | List
{}         | Set/Hash
()         | List
""         | Text
''         | String
0          | Integer
0.0        | Double
           
**Collection literals**

Literal      | Type
-------------|-----------------
{a:0, b, c}  | Ordinal
{x:'b',y:'d'}| Object
[1, 2, 3]    | List{Byte}
['a','b','c']| List{Symbol}
["a","b","c"]| List{Text}

### Type Inference

Sometimes the type is partially specified to simplify type declaration:

```
variable
  ** member type is inferred later from first member
  List: a := [];
```
       
### Type verification

We can verify the type using "is" operator:

```
given
  Object: r := {name:"test", age:"24"}; 
  Hash:   t := {('key1':"value1"),('ley2':"value2")};
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
  Double: i := 1.5;
do
  expect i is Double;
  write "type of i is \s" ? type(i);
done;
```

## Polymorphic operators

In mathematics there are very few operators: {+, -, / , * } that can operate with any kind of numbers: negative, positive, rational or real. Operators are not bound to specific data types. Therefore these operators are called _"polymorphic"_.

Some languages define different operators for  Integers and Floating decimal numbers. For example in OCaml the operator "/" can divide  Integers while "/." can divide Floating point decimal numbers. This is unexpected for a mathematician who is expecting to use one single operator for division. 

In EVE, operators are mapped to functions. To design polymorphic operators we overload the function signature using type dispatch. The dispatch is using left side operand first, this is the leading operand. For unary operators there is only right side operand so this becomes the leading operand.

## Ordinal type

Ordinal type is an ordered list of identifiers that can represent things, ideas, concepts, keywords. Each item has an identifier name that can be uppercase, lowercase or mixed . To each item we associate a value that is two byte number starting from 0 to N. Maxim number of items is 65535.

**Syntax:**
Ordinal type is usually a finite set that can be enumerated using a literal. In mathematics a set of items is represented using round brackets () separated by comma. In the next example we define the days of the week in EVE:

```
type Name := {identifier:value, ... } <: Ordinal;
```

**Usage**

Ordinal type is suitable for creation of options that can be used for switch statement. 

* Value of first element can be specified. If is not specified it starts from: 1.    
* Values of next elements can not be specified. That is next element is previous element +1.   
* Elements declared in a Ordinal type are public is we use "." prefix

**Example:**
```
type Day := {.Sunday:1, .Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday} <: Ordinal;

routine main():
  String: message;
process  
  given
    Day: today = today();
  check today:
    match (Friday, Saturday, Sunday) do
      alter message:='weekend';
    match (Monday) do
      alter message:='first workday';
    match (Friday) do
      alter message:='last workday';
  else
    alter message:='middle of the week';
  done;
  print ('Is', message);
return;
```

**Domain:**
You can use Ordinal to create a domain:
```
when today in (Monday..Friday) do
   print ("Have a nice day!");
else
   print ("Have a happy weekend!");
done;
```

**Operators**
Ordinal is a discrete numeral type so it has support for relation operators: { =, <, >, <=, >= }. It can be incremented and decremented using += and -=. On ordinals you can perform addition, subtraction, multiplication.

```
** using type Day declared before
given
  @day v  := Friday;
do
  alter  v := v + 1; 
  expect v = Saturday;
done;
```

## Logical type

In Latin the "falsus" and "verum" are translated in English to "false" and "true".

* falsus := ⊥ defined by ⊥ := ¬ ⊤  and  ( P ∧ ¬P )
* verum  := ⊤ defined by ⊤ := ¬ ⊥  and  ( P ∨ ¬P )

|name     |    value      | binary 
|---------|---------------|------------------------------
|False    | Logic.False   | 00000000 00000000 
|True     | Logic.True    | 00000000 00000001

**syntax**
```
variable
  Logic: variable_name; //  default False
```

**internal design**

Probably best to define Logic type is Ordinal:
```
type Logic := { .False , .True } <: Ordinal;
```

**Logical expressions**

A logical expression is a demonstration or logical deduction having result T or F. The order of operations can be controlled using operator precedence and parentheses (). 

Operator precedence:` {not, and, or, xor} `

Result of logical expressions can be used into a conditional statement to make a decision. 
Also results of logical expressions can be stored in logical variables to be used later in other conditions.

## Gradual typing

Gradual typing is a type system in which some variables may be given types and the correctness of the typing is checked at compile-time (which is static typing) and some variables may be left un-typed and eventual type errors are reported at run-time (which is dynamic typing). To declare gradual types we use a polymorphic type called "@variant".

**Variant Types**

A Variant is a polymorphic variable that can have multiple types but only one at a time:

**Syntax:**
```
type Name := {Type | Type | ... } <: Variant;

variable 
  Name: v; //  declare single variable
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
type Number: {Integer | Double | Null} <: Variant;

variable
  Number: x := Null;  
```

**Usability**

A variant can establish its data type at runtime:

**example:**
```
given
  Double | Integer: v, x ,t;
do
  ** positive example
  alter v := 1;     //  v is  Integer
  alter x := 1.5;   //  x is Double:    
  alter t := 1 / 2; //  make t Double
  
  ** safe conversion
  alter t := 12; //  t is Double
  
  ** negative examples
  alter v := x;  //  ERROR: v is  Integer 
done;
```

A variant is a way to create a generic routine.

```
routine swap(Integer | Double: x, y):
  Integer | Double: i
process  
  expect type(x) = type(y);
  
  alter i := x; //  intermediate reference
  alter x := y; //  first  swap
  alter y := x; //  second swap
return;

routine main():
  Integer: y;
  Double: a, b;
process  
  ** invert two  Integer: numbers
  alter x := 10;
  alter y := 20;  
  apply swap(x, y);
  expect (x = 20) and (y = 10);
  ** invert two Double: numbers
  alter a := 1.5;
  alter b := 2.5;
  apply swap(a, b);
  expect (a = 2.5) and (b = 1.5);
return;
```

## Single symbol

Symbols are Unicode UTF32. That is using 32 bit  Integer:

* Single-quoted strings like: 'α'
* U+HHHH   from: U+0000   to U+FFFF
* U-HHHHHH from: U+000000 to U+FFFFFF

Value NUL = U+0000. This is also the default value.

## Calendar date

In EVE we represent calendar date.

**Date storage**

* Date type is internally stored as number on 4 bytes;
* First byte store the day, second byte store the month;
* Last 2 bytes store the year; 

**Date literals**

When can create a date literal using 3 format functions:

* ydm() format: "YYYY/DD/MM"
* dmy() format: "DD/MM/YYYY"
* ydm() format: "MM/DD/YYYY"

**Note:** A reversible function is overloaded.

```
given
  Date: date := "2019/01/30" as YDM
do
  print date as YDM; //  2019/01/30
  print date as DMY; //  30/01/2019
  print date as MDY; //  01/30/2019
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

Time format is created using two reversible functions: t12() and t24()

*  T12 accept format ("hhhh:mm:ss,9999ms") 
*  T24 accept format ("hhhh:mm:ssxx, 9999ms" )

ss: can be 0..60 seconds  
xx: can be: (am/pm)

**Example:**

```
given
  Time: time1, time2, time3; //  '00:00' 
do
  alter time1 := "23:63" as T24;
  alter time2 := "23:63:59,99" as T24;
  alter time3 := "11:63:59pm,99ms" as T12;
done;
```
**Read next:** [Composite Types](composite.md)