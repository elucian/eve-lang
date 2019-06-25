## Data Types

EVE is a gradual typed language. Next I will describe basic types:

**bookmarks**

* [Scalar](#scalar-types)
* [Basic](#basic-types)
* [Composite](#composite-types)
* [Collections](#collections)
* [Physical](#physical-types)
* [Alias](#Alias)
* [Data coercion](#data-coercion)
* [Type inference](#type-inference)
* [Default types](default-types) 
* [Ordinal type](ordinal-type)
* [Logical type](logical-type)
* [Gradual typing](#gradual-typing)
* [Calendar date](#calendar-date)
* [Time duration](#time-duration)

## Scalar Types

Scalar types are fixed size data types mapped to native OS types. 

| reference|native|description
|----------|------|------------------------------------------------------
| @byte    | u8   |Unsigned on 8  bit 
| @word    | u16  |Unsigned on 16 bit 
| @binary  | u32  |Unsigned on 32 bit 
| @natural | u64  |Unsigned on 64 bit 
| @short   | i16  |Signed on 16 bit 
| @integer | i32  |Signed on 32 bit
| @long    | i64  |Signed on 64 bit 
| @single  | f32  |Float precision number on 4 byte
| @double  | f64  |Float precision number on 8 byte

## Basic Types

| reference| description
|----------|---------------------------------------------------------------
| @ordinal | Enumeration of symbols, ideas or terms
| @object  | Base class for creation of plain simple objects
| @null    | Null data type. Have one constant value: Null
| @date    | Calendar date     
| @time    | Calendar time
| @logic   | Is a @ordinal subtype having values:  false = 0, true = 1

## Composite Types

Composite data types are unions of data elements.
 
| type      | description
|-----------|---------------------------------------------------------------
| @numeric  | Numeric variant that can be Null
| @symbol   | Single Unicode symbol UTF-32
| @string   | Limited capacity string:   ('single quoted')
| @text     | Unlimited capacity string: ("double quoted")
| @list     | Dynamic unsorted enumeration of values or objects of same type
| @hash     | Enumeration of (key:value) pairs unique sorted by key
| @set      | Enumeration of unique elements of the same type sorted by value
| @exception| Composite type derived from @object base class

**note:** 
* In the future we will cover a complete set of physical types
* Physical types include measurement unit and transformation methods 

## Numeric Types

In EVE we can have two categories of numbers:

 Category     | EVE Types
--------------|------------------------------------------------------------
 Discrete:    | @byte, @word, @binary, @integer, @natural
 Continuous:  | @single, @double, 

### Discrete numbers:

|type     |Chars  |Bytes|min |max   |maximum number	
|---------|-------|-----|----|------|-------------------------
|@integer |20     |8    |-2⁶³|2⁶³-1 |≤ 9,223,372,036,854,775,807
|@natural |20     |8    |0   |2⁶⁴-1 |≤ 18,446,744,073,709,551,615
 
For conversion into characters:

* The number of characters required for @integer numbers is 20. (19+sign)
* For @double numbers, conversion into characters is controled by #precision directive
 
### Double numbers

The type _Double_ is represented using floating precision numbers.   
Floating decimal numbers are most simply described by 3  Integers:

* s: a sign (0 or 1)  
* c: a coefficient  
* n: an exponent   

The numerical value of a finite number is −1ˢ × c × 2ⁿ
Using this formula EVE define two floating point types.

@single: is single-precision 32-bit IEEE 754:  
@double: is double-precision 64-bit IEEE 754:  

|type     |Digits |Bytes|maximum number	
|---------|-------|-----|----------------------------------
|@single  |7      |4    |≤ 3.4 × 10³⁸
|@double  |16     |8    |≤ 1.8 × 10³⁰⁸

Precision is variable depending on the size of the number. The number of digits represents the largest number that can be converted from string format into a @double: and back without loosing any digit. Think of it like a digital display from a packet calculator.

**Numeric literals**

Example | Description
--------|-------------------------------------------------------------------------
0       | @integer zero
123     | @integer number using symbols: {0,1,2,3,4,5,6,7,8,9}
1/2     | @single  number use symbols: {.,0,1,2,3,4,5,6,7,8,9}
0.5     | @double  number use symbols: {.,0,1,2,3,4,5,6,7,8,9}

**example**

```
routine main:
  @integer: i; 
  @natural: n;
  @double : r;
process  
  alter i := 9223372036854775807; //  maximum
  alter n := 18446744073709551615; //  maximum
  alter r := 1/2; //  0.5
return;
```

**See also:** [scientific notation](https://en.wikipedia.org/wiki/Scientific_notation#Other_bases)

## Alias

User types can be _defined_ using symbol ":=" and keyword: "alias".

**Syntax:**
```
alias @alias_name := Generic_Class {parameters}
```
**Notes:**

* Users can define constrained sub-types or group of basic types;
* A module can _import_ public types defined in other modules;
* A data type can be declared only in module global context;

**Example:**
```
class Point(@double: x,y) <: @object:
  @double: .x, .y;
create
  alter .x := x;
  alter .y := y;
return;

routine main:
  @point: p1, p2;      //  use implicit constructor
  @point: p3 := {1,1}; //  initial value for Point
process
**modification using constant literals
  alter p1.a := 1;
  alter p1.b := 2; 
  
**reset Point using a literal
  alter p2 := {2, 2};
  
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

**Implicit coercion**
In EVE the arithmetic operators are polymorphic. Numeric operators can do implicit data conversion to accommodate the data types and return an accurate result.  Automatic conversion is possible only when there is no risk of loosing data precision. If there is a loss of precision we can end-up with a _run-time error_. To prevent this EVE will implement a safe compile-time check.

Implicit conversion is possible and _safe_ in this direction:

@byte as @word as @binary as @natural as @integer as @single as @double.

Explicit conversion is possible but _unsafe_ in this direction:

@double as  @single as @integer as @natural as @binary as @word as @byte

```
given
  @integer: a := 2;
  @double:  b := 1.5; 
do
  alter b := a;       //  this implicit cast is possible b = 2.0
  alter b := a + 3.5; //  add 3.5 then assign result to b = 5.5
  alter a := b;       //  error: can not assign @double: to  @integer
  alter a := 1.5;     //  error: can not assign @double: to  @integer
done;
```

**Explicit coercion**
Explicit coercion is a _forced conversion_. Can be used to convert backwards from higher data range to lower data range or from continuous numbers to discrete numbers. This however can cause a data or precision loss. Explicit coercion is using a function.

Examples of explicit coercion:   
```
given
  @integer: a := 0;
  @double : b := 1.5;
do

**explicit coercion lose (0.5)
  alter  a := floor(b);
  print (a); //  will print: 1
 
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
  @string : s; 
  @integer : v := 1000;
do  
  alter s := format(v); //  explicit coercion s = '1000'
done;
```

**string: to a number**

This can be ready using the casting function parse(), only if the string contains a number. Otherwise the conversion fail and will rise and exception. 

```
given
  @integer : v; 
  @double  : b;
  @string  : s := '1000';
  @string  : r := '200.02';
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
  @list: ls := [0,1,2,3,4,5,6,7,8,9]; //  initialized list of @integer
do
  print  ls.type(); //  @list[@integer]
  expect ls is @list[@integer];
done 
```

## Default types
Literals are representations of specific particular data type in source code.

**Basic types**
Next notation use "9" to show any digit in range [0..9].

Literal      | @type
-------------|-----------------
 9           | @integer
-9           | @integer
0x9ABCDEF    | @natural
0b1010101    | @binary
9.9          | @double
U+0001       | @word
U-FFFFFFFF   | @binary

**Zero literals**

Literal    | @type
-----------|---------------
[]         | @list
{}         | @set/@hash
()         | @list
""         | @text
''         | @string
0          | @integer
0.0        | @double
           
**Collection literals**

Literal      | @type
-------------|-----------------
{a:0, b, c}  | @ordinal
{x:'b',y:'d'}| @object
[1, 2, 3]    | @list{@byte}
['a','b','c']| @list{@symbol}
["a","b","c"]| @list{@text}

### Type Inference

Sometimes the type is partially specified to simplify type declaration:

```
variable
  ** member type is inferred later from first member
  @list: a := [];
```
       
### Type verification

We can verify the type using "is" operator:

```
given
  @object: r := {name:"test", age:"24"}; 
  @hash:   t := {('key1':"value1"),('ley2':"value2")};
do
  ** check variable types using introspection
  expect r.name  is @text;
  expect r.age   is @text;
  expect t.key   is @string;
  expect t.value is @text;
done;
```

## Printing type()

For type introspection we can use type() built-in function:

```
given
  @double: i := 1.5;
do
  expect i is @double;
  print "type of i is \s" <+ type(i);
done;
```

## Polymorphic operators

In mathematics there are very few operators: {+, -, ÷ , ⋅} that can operate with any kind of numbers: negative, positive, rational or @double. So the numeric operators are not very specific. This property of operators is called _"polymorphic"_ and is a problem for computer science.

Some languages define different operators for  Integers and floating decimal numbers. For example in OCaml the operator "/" can divide  Integers while "/." can divide floating numbers. This is unexpected for a mathematician. Therefore EVE languages is using polymorphic operators.

Operators are mapped to functions. To design polymorphic operators we overload the function signature using type dispatch. The dispatch is happening by left side operand first, this is the leading operand. For unary operators there is only right side operand so this becomes the leading operand.

## Ordinal type

Ordinal type is an ordered list of identifiers that can represent things, ideas, concepts, keywords. Each item has an identifier name that can be uppercase, lowercase or mixed . To each item we associate a value that is two byte number starting from 0 to N. Maxim number of items is 65535.

**Syntax:**
Ordinal type is usually a finite set that can be enumerated using a literal. In mathematics a set of items is represented using round brackets () separated by comma. In the next example we define the days of the week in EVE:

```
alias Name := {identifier:value, ... } <: @ordinal;
```

**Usage**

Ordinal type is suitable for creation of options that can be used for switch statement. 

* Value of first element can be specified. If is not specified it starts from: 1.    
* Values of next elements can not be specified. That is next element is previous element +1.   
* Elements declared in a @ordinal type are public is we use "." prefix

**Example:**
```
alias @day := {.Sunday:1, .Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday} <: @ordinal;

routine main:
  @string: message;
process  
  given
    @day: today := today();
  quest today:
    match (Friday, Saturday, Sunday) do
      alter message:='weekend';
    match (Monday) do
      alter message:='first workday';
    match (Friday) do
      alter message:='last workday';
  other
    alter message:='middle of the week';
  done;
  print ('Is', message);
return;
```

**Domain:**
We can use @ordinal to create a domain:
```
when today in (Monday..Friday) do
   print ("Have a nice day!");
else
   print ("Have a happy weekend!");
done;
```

**Operators**
@ordinal is a discrete numeral type so it has support for relation operators: { =, <, >, <=, >= }. It can be incremented and decremented using += and -=. We can perform addition, subtraction, multiplication.

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
  @logic: variable_name; //  default false
```

**internal design**

Probably best to define Logic type is @ordinal:
```
alias Logic := { .False , .True } <: @ordinal;
```

**Logical expressions**

A logical expression is a demonstration or logical deduction having result T or F. The order of operations can be controlled using operator precedence and parentheses (). 

Operator precedence:` {not, and, or, xor} `

Result of logical expressions can be used into a conditional statement to make a decision. 
Also results of logical expressions can be stored in logical variables to be used later in other conditions.

## Gradual typing

Gradual typing is a type system in which some variables may be given types and the correctness of the typing is checked at compile-time (which is static typing) and some variables may be left un-typed and eventual type errors are reported at run-time (which is dynamic typing). To declare gradual types we use a polymorphic type called "@variant".

**Variant Types**

A @variant is a polymorphic variable that can have multiple types but only one at a time:

**Syntax:**
```
alias @name := {@type | @type | ... } <: @variant;

variable 
  name: v; //  declare single variable
```

## Variant Properties

* @variant data type is assigned at runtime;
* One variant can have a single value at a time;
* One variant is a "union" of several types

## Making a null-able type

For this we use a special type Null 

* The Null type is a curious type;
* It can have only one value = Null;

**Examples:**
```
alias @number: {@integer | @double | @null} <: @variant;

variable
  @number: x := Null;  
```

**Usability**

A variant can establish its data type at runtime:

**example:**
```
given
  @double | @integer: v, x ,t;
do
  ** positive example
  alter v := 1;     //  v is  @integer
  alter x := 1.5;   //  x is @double:    
  alter t := 1 / 2; //  make t @double
  
  ** safe conversion
  alter t := 12; //  t is @double
  
  ** negative examples
  alter v := x;  //  ERROR: v is  @integer 
done;
```

A variant is a way to create a generic routine.

```
routine swap(@integer | @double: x, y):
  @integer | @double: i
process  
  expect type(x) = type(y);
  
  alter i := x; //  intermediate reference
  alter x := y; //  first  swap
  alter y := x; //  second swap
return;

routine main:
  @integer: y;
  @double: a, b;
process  
  ** invert two  @integer: numbers
  alter  x := 10;
  alter  y := 20;  
  swap(x, y);
  expect (x = 20) and (y = 10);
  ** invert two @double: numbers
  alter a := 1.5;
  alter b := 2.5;
  swap(a, b);
  expect (a = 2.5) and (b = 1.5);
return;
```

## Single symbol

Symbols are Unicode UTF32. That is using 32 bit  @integer:

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
  @date: date := "2019/01/30" -> ydm;
do
  print date -> ydm; //  2019/01/30
  print date -> dmy; //  30/01/2019
  print date -> mdy; //  01/30/2019
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

*  t12 accept format ("hhhh:mm:ss,9999ms") 
*  t24 accept format ("hhhh:mm:ssxx, 9999ms" )

ss: can be 0..60 seconds  
xx: can be: (am/pm)

**Example:**

```
given
  @time: time1, time2, time3; //  '00:00' 
do
  alter time1 := "23:63" -> t24;
  alter time2 := "23:63:59,99" -> t24;
  alter time3 := "11:63:59pm,99ms" -> t12;
done;
```
**Read next:** [Composite Types](composite.md)