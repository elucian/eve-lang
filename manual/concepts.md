# ΞVΞ Concepts

These concepts are common to any computer language in Algol family. 

**bookmarks**

* [punctuation](#punctuation)
* [comments](#comments)
* [directives](#directives)
* [keywords](#keywords)
* [operators](#operators)
* [data types](#data-types)
* [variables](#variables)
* [identifiers](#identifiers)
* [expressions](#expressions)

## Punctuation

* EVE is using infix expressions like other popular languages;
* Multiple expressions can be separated with comma and enclosed in parenthesis;
* Each statement start with a lowercase keyword and is ending at end of line; 
* Native data types, variables, labels and methods use lowercase letters and numbers;
* Composite data types and classes start with capital letters;
* System variables use prefix "$". User can define new system variables;

## Comments

* Eve has single line comments starting with "**"
* Eve has end of line comments starting with "--"
* Eve has multi line comments between (* ... *)

**examples**
```
## Title comment
  ** indented comment

** Single line comment

(*
  Multiple line comments
*)
print ** end of line comment is enabled  
```

**Notes:**

* One single character "#" is a compiler directive;
* One single character "*" is multiplication operator;
* Nested comments are supported for multi-line comments;

## Directives
Any module need at least one directive. If directive is missing the compiler will not recognize the file category and will signal an error. The directive is very important part of EVE code.

The name of the file is enclosed in "" and is the first statement after initial comments. This name must match the file-name. If the file-name is renamed the source code will not be recognized and an error will be signaling the incorrect file name.

```
#driver  "name"
#module  "name"
#library "name"
```

**description**
* a _driver_ is the main module of the application
* a _module_ can be executed from driver or other module
* a _library_ is a repository file that can be imported in other modules

**properties**

* a library can not be executed but only imported
* a library do not contain method main()
* a module can not be imported but only executed
* a module must contain method main()

A _library_ is a reusable component. It contains mostly public members: 

{constants, types, classes, methods, functions}

* after first load a library remain resident in memory
* a library is loaded only once even if is imported multiple times
* circular import is possible but we protect against infinite loop
* a library usually do not import itself, but it is possible 

A _module_ is a executable script. It contains mostly private members:

* you can run a module once or many times
* module is not resident in memory once finished

## Keywords

Keywords are English words familiar to programmers used in logical semantic structures easy to grasp. We prefer English since the computer was invented in England so they deserve this honor.

* [Keywords](keywords.md) 

## Operators:

EVE has ASCII and Unicode operators. Unicode operators require one space before and one after. ASCII operators do not require space separator. Unicode and ASCII operators usually are independent used and not combined.

* [Operators](operators.md) 

## Data types
A data type is an abstract set or class that describe data representation. 

There are 3 kind of data in EVE

* basic type 
* composite type 
* class

**syntax:**

A composite data type is declared like this:
```
type Type_Name <: Type_descriptor
```

## Variables
A variable is represented by an identifier, and is associated to a type. Variable can be changed during the execution of the program using modifier operators { :=, +=, *=, /= ...}. 

**patterns:**
```
global
  ** use default value
  type_name: var_name                
  ** specific value and type
  type_name: var_name := value
  ** multiple variables in one assignment
  type_name: var_name1, name2 ...:= value 
  ** diverse values in one statement
  type_name: var_name1:=value1, var_name2 := value2 
```

**examples**
```
global  
  ** integer numbers
  Integer: a  
  Integer: b := 1 

  ** real numbers
  Real: d := 2.5
  Real: x,y,z := 0.0  
```

**default value**
When a variable is specified, and the initializer ":=" is missing the variable takes default zero value. This value is different for each data type. For example zero value for Real: numbers is 0.0 and for strings is "". Notice the "zero" value is not Null. 

## System variables
We define system variables using "$" name prefix. _Environment Variables_ from OS are created automatically along with other "implicit" variables required by EVE semantics. 

## Modify Value 
The assign operator ":=" is used to execute an expression and assign the result to a variable. 
The previous value of the variable is discarded if there is no other reference to it.

**Syntax:**
```
  variable_name := <expression 
```

## Identifiers
The name of identifiers in EVE can have a length of 64 characters. A name starts with lowercase letters (a..z) or capital letters (A..Z) followed by one or more characters or numbers. No special characters or spaces are permitted in the name except underscore ("_"). A variable can contain underscore but can not start or with underscore. 

The underscore is equivalent to space. So the identifiers that have space in a JSON or in a database can be mapped to internal variables that use underscore instead of a space. Variable names can not start with numbers. 


**These are valid identifiers**  
```
 x, y, z
 a₁,a₂,aₙ  
 thisIsOK
 this_is_ok  
```
**These are invalid identifiers**  
```
 1`st
 \_this  
 this\_  
 \_this\_  
```

**Naming variables**
Variables usually have a meaning or a purpose therefore variable must have a proper name.  
Variables can not have are the language reserved keywords. Therefore we advise for variables to use a prefix.

* "v_" is a good prefix for local  variables;
* "p_" is a good prefix for input  parameters;
* "o_" is a good prefix for output parameters;

## Expressions

Expressions are created using identifiers, operators, functions and constant literals. 

* can be combined to create more complex expressions;
* have type that is calculated using type inference;
* can be assigned to variables using ":=" or "<+" operators;
* can be printed to console using "print" or "write" methods;
* can use () to establish order of operations;

**Examples**
```
** simple expressions in print statement
print (10) ** print 10
print ("this is a test")

** complex expressions can use ()  
print (10 + 10 + 15)   ** math
print (10 > 5 | 2 < 3) ** logical

** print result for multiple expressions
print (1, 2, 3)       
print (10, 11, 12)   

** avoid new line and print
write (1,2)
write (3,4)  

** now create new line
print ** expect 1234 
```

**Notes:** 
* print statement can receive multiple parameters
* print statement add new line by default
* to avoid new line you can use "write" statement instead of "print"
* multiple expressions or arguments are separated by comma

## Multiple statements

You can have multiple statements on one line separated using ""

**examples**
```
given
  ** integer numbers
  Integer: a := 0 ; b := 1 
begin  
  print  (a, b)  
  expect (a = 0, b = 1)
ready

given  
  ** real numbers
  Real: d := 2.5 ; x,y,z := .0  
begin  
  print  (d, x, y, z) 
  expect (d = 2.5, x = .0, y = .0, z = .0)
ready  
```

## Multiple lines

One expression can span multiple lines. The expression may be enclosed in parenthesis or quotation marks. Arithmetic expressions can terminate with operator and continue on next line with operand. EVE do not use the "continuation" operator like Python: "\\"

**example
```
given 
  Integer: x 
  Matrix : a
begin  
  ** broken expression
  x := 1 + 2 +
       3 + 4 + 5
       
  ** all 5 numbers are in sum         
  expect x = 15 

  ** broken matrix
  a := [ 
         [1,2],
         [3,4],
         [5,6]
       ]       
ready  
```

**Read next:** [Structure.md](structure.md)