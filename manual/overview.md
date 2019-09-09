## Syntax Overview

EVE is a free form language inspired from Ada, Java and Ruby. 

**bookmarks**

* [punctuation](#punctuation)
* [comments](#comments)
* [keywords](#keywords)
* [operators](#operators)
* [variables](#variables)
* [identifiers](#identifiers)
* [expressions](#expressions)
* [statements](#statements)

## Punctuation

* EVE is using infix expressions like Java and other popular languages,
* Multiple expressions can be separated with comma and enclosed in parenthesis,
* Each statement start with a keyword and is ending semicolon,
* System constants use prefix "$" and they are also public,
* System variables use prefix "@" and they are also public,
* Type identifiers and classes start with capital letters,
* Public variables and constants start with "." prefix,
* Statement regions and nested blocks use mandatory indentation;

## Comments

* Hash sign "#" is used for single-line header comment,
* Single line comment is using two start: `**` 
* Boxed comments are using notation: `+-...-+` 
* Expression comments are using notation: `/* ... */`

**examples**
```
# Title comment
+------------------------------------
|  Boxed comments for headers       |
|  it can span multiple lines       |
------------------------------------+
module test:

# Main routine: ( this is title)
routine main():
  Integer a;
process
  ** Expression comment /*...*/
  alter a := a + 1 /* *(a - 1) */ -1;  
return;  

module. // end of module
*************************************
**  Boxed comment for old printer  **
*************************************
```

**Notes:**
* Outline comments are supported inside expressions;
* A statement can continue after end of line comment;
* After module. you can add comments on many lines;

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
* @global_variable;

**notes:**
* Prefix is reducing collision between local and global name scope;
* In other languages this kind of prefix is called _sigil_
* A system variables can be an object with attribute.


## Operators

EVE us ASCII symbols for operators. One operator can be a single character or a combination of two or 3 characters. 

**Single symbol:**
```
{ : = ~ ? % ^ * - + / < > }
```

**Two symbols:**
```
{ := == != <> => >= <= <+ <: .. .! !. !! ~. += -= *= /= %= ^= &= |= }
```

**Three symbols:**
```
{ .<. .>. .|. .&.}
```

**Delimiters:**
```
, : . ; "_" '_' `_`
(...) [...] {...} #(...)
```

**Details:** [Operators](operators.md) 

## Variables

A variable is represented by an identifier, and is pair-up with a data type using ":". Variables are abstract concepts representing primitive values or references to memory locations. Variables can be altered during the program execution using keyword _alter_ and _modifiers_ like: { :=, ::, +=, -= ... }. 

**patterns:**
```
** define alias for a: 

** alias names have to start with uppercase letters.   
type Type_name := super_type {parameters};

** shared variables
variable
  ** use type to define a variable
  Type_name: var_name;
  ** with specific value and type
  Type_name: var_name := value;
  ** multiple variables in one assignment
  Type_name: var_name1, name2 ...:= value;
  ** multiple variables with diverse values
  Type_name: var_name1:=value1, var_name2 := value2;
```

**examples**
```
variable 
  ** two integer numbers
  Integer: a;
  Integer: b := 1;
  ** multiple Double numbers
  Double: d := 2.5; 
  Double: x,y,z := 0.0;
```

**zero value**
When a variable is specified, and the initializer ":=" is missing the variable takes default zero value. This value is different for each data type. For example zero value for Integers = 0 for Double = 0.0 and for String = ''. 

## Assign Value
 
Assign value can be done using operator: ":=". But this operator has a strange behavior that you must understand to avoid unintended side-effects. It transfer a value "by sharing". It transfers a memory location not the underline value:

**Syntax:**
```
alter identifier := variable_name;   //  share a reference to variable
alter identifier := function_name;   //  share a reference to function
alter identifier := literal;         //  mutate value / initialize
alter identifier := expression;      //  mutate value / initialize
alter identifier := function_name(); //  mutate value / reset value
```

**clone:**

To make a clone/copy underline value from a reference you must use symbol "::" (clone).

**Syntax:**
```
clone variable_name := reference_name; //  make a clone
```

## Expressions

Expressions are created using identifiers, operators, functions and constant literals. 

* can be combined to create more complex expressions;
* have a type that is calculated using type inference;
* can be assigned to variables using ":=" or "?" operators;
* can be printed to console using "print" or "write" methods;
* can use round parenthesis () to establish order of operations;

**Examples**
```
** simple expressions in print statement
print  10; 
write "this is a test";

** complex expressions can use ()  
print (10 + 10 + 15);      //  numeric expression
print (10 > 5) or (2 < 3); //  logical expression

** list of expressions are enclosed in ()
print (1, 2, 3);    //  expect: 1 2 3
print (10, 11, 12); //  expect: 10 11 12

** using write to: avoid new line and print
write (1,2);
write (3,4);  

** now create a new line and output the text
print; //  1234 
```

**Notes:** 
* print statement can receive multiple arguments in parenthesis ()
* print statement add new line by default, that can be suppress using eol = False
* print statement will separate different values using one space 
* write statement will output to console and do not add end of line

## Statements

One statement can be declarative or imperative. 

* A statement is usually a single line of code
* A statement can extend on several lines and finalize with ";"
* A group of several statements is called a code block,
* A block of code is finalized with a suggestive keyword and ";"

**examples**

The most simple block statement start with "do" and end with "done"
```
given
  ** Integer numbers
  Integer: a := 0;
  Double:  b := 1.5; 
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
  alter x := 1 + 2 +
             3 + 4 + 5;

  ** multi-row literal 
  alter a := { 
         (1:2),
         (3:4),
         (5:6)
        };
done;
```

**Read next:**  [Data Types](types.md)