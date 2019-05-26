# Syntax Overview

EVE is a free form language inspired from Java and Ruby. 

**bookmarks**

* [punctuation](#punctuation)
* [comments](#comments)
* [keywords](#keywords)
* [operators](#operators)
* [data type](#data-type)
* [variables](#variables)
* [identifiers](#identifiers)
* [expressions](#expressions)
* [statements](#statements)

## Punctuation

* EVE is using infix expressions like Java and other popular languages;
* Multiple expressions can be separated with comma and enclosed in parenthesis;
* Each statement start with a lowercase keyword and is ending semicolon; 
* Global constants use prefix "$" and they are also public;
* Global variables use prefix "#" and they are also public;
* Class identifier start with one capital letter;
* Scoping operator is "." unlike "::" that is used in C++ and Rust. 

## Comments

* Title comment is using ## two hashes like Wiki pages
* Sub-title comment and line separators are using: "**"
* End of line comment can be done using "--"
* Boxed comments are using notation "+-...-+"
* Outline comments are using pair "|* ... *|"

**examples**
```
*************************************
**  Boxed comments using: "**"     **
*************************************

## Title comment
  -- indented comment

** Single line comment
print; 
+------------------------------------
|  fancy boxed comments to explain  |
|  code, can span multiple lines    |
------------------------------------+

```

**Notes:**
* Nested comments are supported for out-line comments;
* End of line comments are ending after new line;

## Keywords

Keywords are English reserved words used in statements. Computer was invented in England during WW2 so, we prefer English words even though a computer language could be created using keywords from other spoken languages.

Summary: [Keywords](keywords.md) 

## Identifiers
The name of identifiers in EVE can have a length of 30 characters. A name starts with lowercase letters (a..z) or capital letters (A..Z) followed by one or more characters or numbers. No special characters or spaces are permitted in the name except underscore ("_"). A variable can contain underscore but can not start or with underscore. 

**These are valid identifiers**  
```
 x, y, z
 a1,a2,a3  
 thisIsOK
 this_is_ok  
```

**These are invalid identifiers**  
```
 1st
 \_not_valid  
 not_valid\_  
 \_not_valid\_  
```

**Prefix**
Global reference identifiers start with a reserved symbol:

* $global_constant;
* #global_variable;

**notes:**
* Prefix is reducing collision between local and global name scope;
* In other languages this kind of prefix is called _sigil_;
* A global variable can be an object with attribute.

**examples:**
```
#module.name := 'test';
#module.description :='It is just a test';
```

## Operators

EVE us ASCII symbols for operators. One operator can be a single character or a combination of two characters. 

Single characters:
```
{ = : ~ ! ? @ % ^ & * - + / < >}
```

Two characters:
```
{ := :+ != <> => >= <= +> <+ <: .. }
```

Delimiters:
```
, : . ; "" '' 
( ) [ ] { } 
```

Details: [Operators](operators.md) 

## Data type

Data type is an abstract concept that describe data representation. 

There are 3 kind of data types in EVE:

* [basic types](basic.md)
* [composite types](composite.md)
* [classes](classes.md)

## Variables
A variable is represented by an identifier, and is pair-up with a type using ":". Variables are abstract concepts representing memory locations or primitive values that can be moved around in different memory locations. Variables can be altered during the execution of the program using modifier operators: { :=, +=, *=, /= ...}. 

**patterns:**
```
** define alias for a data type
alias Class_Name := super_class {parameters};

** shared variables
variable
  ** use type to define a variable
  Class_Name: var_name;
  ** with specific value and type
  Class_Name: var_name := value;
  ** multiple variables in one assignment
  Class_Name: var_name1, name2 ...:= value;
  ** multiple variables with diverse values
  Class_Name: var_name1:=value1, var_name2 := value2;
```

**examples**
```
variable 
  ** two integer numbers
  Integer: a;
  Integer: b := 1;
  ** multiple real numbers
  Real: d := 2.5; 
  Real: x,y,z := 0.0;
```

**zero value**
When a variable is specified, and the initializer ":=" is missing the variable takes default zero value. This value is different for each data type. For example zero value for Integers = 0 for Real = 0.0 and for String = ''. 

## Assign Value 
Assign value can be done using operator: ":=". But this operator has a strange behavior that you must understand to avoid unintended side-effects. It transfer a value "by sharing". It transfers a memory location not the underline value:

**Syntax:**
```
  identifier := variable_name;  -- share a reference to variable
  identifier := function_name;   -- share a reference to function
  identifier := literal;         -- mutate value / initialize
  identifier := expression;      -- mutate value / initialize
  identifier := function_name(); -- mutate value / reset value
```

**clone:**

To make a clone/copy underline value from a reference you must use symbol "::" (dereference).

**Syntax:**
```
  variable_name :+ reference; -- make a clone
```

## Expressions

Expressions are created using identifiers, operators, functions and constant literals. 

* can be combined to create more complex expressions;
* have a type that is calculated using type inference;
* can be assigned to variables using ":=" or "<+" operators;
* can be printed to console using "print" or "write" methods;
* can use round paranthesis () to establish order of operations;

**Examples**
```
** simple expressions in print statement
print  10; 
print "this is a test";

** complex expressions can use ()  
print (10 + 10 + 15);       -- numeric expression
print ((10 > 5) | (2 < 3)); -- logical expression

** list of expressions are enclosed in ()
print (1, 2, 3);    -- expect: 1 2 3
print (10, 11, 12); -- expect: 10 11 12

** using write to: avoid new line and print
write (1,2);
write (3,4);  

** now create a new line
print; -- 1234 
```

**Notes:** 
* print statement can receive multiple arguments in parenthesis ()
* print statement add new line by default
* print statement will separate different values using one space 
* to avoid new line you can use "write" statement instead of "print"

## Statements

One statement can be declarative or imperative. 

* A statement is usually a line of code source terminated with new line
* Sometimes a statement extend on several lines
* Sometimes multiple statements are in the same line, separated by ";"
* A group of several statements is called a block of code
* A block of code usually is terminated by one final keyword and ";"
* The final keyword is different for different statements;

**examples**

The most simple block statement start with "do" and end with "done"
```
given
  **  Integer numbers
  Integer: a := 0;
  Real:    b := 1.5; 
do
  print  (a, b);
  expect (a = 0, b = 1.5);
done;
```

## Multiple lines

One expression can span multiple lines. 

* The expression may be enclosed in parenthesis or quotation marks; 
* Arithmetic expressions can use an operator to continue on next line;

**example**
```
given 
  Integer: x; 
  Hash   : a; 
do  
  ** multi-row expression
  x := 1 + 2 +
       3 + 4 + 5;

  ** ERROR: ↓ (missing ";") 
  x := 1 + 2 
     + 3 + 4 + 5;
       
  ** all 5 numbers are in 
  expect x = 15; 

  ** multi-row hash table
  a := { 
         (1:2),
         (3:4),
         (5:6)
       };
done;
```

**Read next:**  [Control Flow](control.md)