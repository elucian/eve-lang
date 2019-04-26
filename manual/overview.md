# ΞVΞ Concepts

ΞVΞ is a free form language inspired from Java and Ruby. 

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
* [statements](#statements)

## Punctuation

* EVE is using infix expressions like other popular languages;
* Multiple expressions can be separated with comma and enclosed in parenthesis;
* Each statement start with a lowercase keyword and is ending at end of line; 
* Native data types, variables, labels and methods use lowercase letters and numbers;
* Composite data types and classes start with capital letters;
* System variables use prefix "$". User can define new system variables;

## Comments

* Eve title of comments starting with "##"
* Eve single line comments starting with "**"
* Eve has multi line comments between {* ... *}

**examples**
```
## Title comment
  ** indented comment

** Single line comment

{*
  Multiple line comments
*}
print ** end of line comment is enabled  
```

**Notes:**

* One single character "#" is a compiler directive;
* One single character "*" is multiplication operator;
* Nested comments are supported for multi-line comments;

## Directives
Directives are script properties that are communicated to the compiler. Directives represent script meta-data. One script can have multiple directives usually at beginning of the script. Directives start with "#" and are used by the compiler to establish different behaviors. 

**examples**
```
#trace:on
#debug:on
#break:point
#print:variable
```

## Scripts

EVE is a modular system based on Scripts. Every script is a script that can be parsed in memory. After this script methods can be executed. User can decide what script will be parsed and executed first by using configuration files or console commands. 

**properties**

* a script can be imported in other Scripts using "import";
* a script can call methods and use other members from other Scripts;
* a script that do not contain method main() is called library;

A _library_ is a reusable component. It contains mostly public members: 

{constants, types, classes, methods, functions}

* after first load a library remain resident in memory
* a library is loaded only once even if is imported multiple times
* circular import is possible but we protect against infinite recursion
* a library usually do not import itself, this is an error

A _script_ is a executable script. It contains mostly private members:

* main method from a script is usually public;
* public methods are exported using "export" region;
* export region is last region in a script;

## Keywords

Keywords are English words familiar to programmers used in logical semantic structures easy to grasp. We prefer English since the computer was invented in England so they deserve this honor.

* [Keywords](keywords.md) 

## Operators:

EVE has ASCII and Unicode operators. Unicode operators require one space before and one after. ASCII operators do not require space separator. Unicode and ASCII operators usually are independent used and not combined.

* [Operators](operators.md) 

## Data types
A data type is an abstract concept that describe data representation. 

There are 3 kind of data types in EVE

* basic types 
* composite types 
* class of object

**syntax:**

A composite data type is declared like this:
```
type Type_Name <+ Type_descriptor
```

## Variables
A variable is represented by an identifier, and is associated to a type. Variables can be changed during the execution of the program using modifier operators { :=, +=, *=, /= ...}. Conceptual variables are native types or references to composite types.

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
When a variable is specified, and the initializer ":=" is missing the variable takes default zero value. This value is different for each data type. For example zero value for Real: numbers is 0.0 and for strings is "". 

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

**These are valid identifiers**  
```
 x, y, z
 a₁,a₂,aₙ  
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

**Naming variables**
We advise for variables to use a prefix.

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

## Statements

One statement can be declarative or imperative. 

* A statement is usually a line of code source terminated with new line
* Sometimes a statement extend on several lines
* Sometimes multiple statements are in the same line, separated by ";"
* A group of several statements is called a block of code
* A block of code usually is terminated by one final keyword and ";"
* The final keyword is different for different statements;

**examples**

The most simple block statement start with "begin" and end with "done;"
```
given
  ** integer numbers
  Integer: a := 0 ; Real: b := 1.5 
begin  
  print  (a, b)  
  expect (a = 0, b = 1.5)
done;
```

**Note:** last statement in a program is ending with "." instead of ";"

## Multiple lines

One expression can span multiple lines. 

* The expression may be enclosed in parenthesis or quotation marks. 
* Arithmetic expressions can terminate with operator and continue on next line. 
* EVE do not use the "continuation" operator like Python: "\\"

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
done;
```

**Read next:** [Structure.md](structure.md)