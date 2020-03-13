## ΞVΞ Language

ΞVΞ is a virtual machine for test automation and data transformation. 

## ΞVΞ Functions

ΞVΞ stands for: Extract Validate Export:

| # | Goal Summary  |  Details
|---|---------------|--------------------------------------------------------------------------
| 1 | Extract       | Enable data extraction from multiple databases
| 2 | Validate      | Enable automatic data verification and validation 
| 3 | Export        | Can create external files in different data formats

## ΞVΞ script

Eve is an aspect oriented scripting language.

* Eve scripts have extension *.eve, 
* Eve scripts represents one aspect of a problem,
* Eve is a descriptive language,
* Eve is specialized in data manipulation using SQL.

# Program Example

```
+--------------------------------------------------------
|   This is a simple program example written in EVE     |
+-------------------------------------------------------+
driver main.eve

import
  con := $lib.console:(*); // external library
  
** declare a function
function
  Integer: add(Integer: p1, p2) => (p1+p2);

** declare a method
method main(Integer: param1, param2):
  Integer: v_var; // local variable
process
  con.print ("param1:#n, param2:#n" ? (param1, param2));
  alter v_var := add(param1, param2);
  con.print ("result:",v_var);
return;
```

**Syntax Attributes**
In previous example you can observe following attributes:

* Eve is using American ASCII symbols, 
* Keywords are using lowercase letters,
* Data types start with one capital letter,
* Variable type is specified before identifier,
* Support nested statements indented at two spaces;
* Every statement is ending with mandatory ";"
* Single line comments are using two stars   "**"
* End of line comments are using two slashes "//"

## Compared to Java

* EVE is a declarative language unlike Java that is object oriented. In EVE you can use objects, methods, routines, functions, expressions and statements. You can create new classes if you need to, but most of the time you don't. 
* In EVE symbol equal "=" is performing a deep value comparison while "==" perform an shallow comparison. In Java there is no deep comparison operator, only shallow comparison. 
* In EVE assign operator is ":=" inherited from Ada. Operator "=" can be used for initialize constants, variables or parameters. In logical expressions "=" will create a logical response. Do not confound the two.
* In Java you must use "New" keyword to initialize an object. But this must be used after "=" and is not a function. Its design is inconsistent with imperative pattern. Most beginners will forget to use this keyword because its inconsistent design. EVE use keyword "forge" to create new objects and this is an imperative keyword.
* In Java you can have one single public class in a file. We believe this is an arbitrary restriction. One EVE module can have as many public classes as you want. In fact this is a feature of EVE language to enable larger modules related to a particular domain.
* In Java you can declare a variable anywhere. EVE is more organized, you can declare variables only in declaration regions. However, you can define a local context to define variables only when you need them. You can not use a variable that is undefined.
* In Java you can use _"try"_ block to handle exceptions. EVE do not have exception blocks. Any method can have an exception handling region using keyword: _recover_ and a finalization region using keyword: _release_.

**Read next:** [User Manual](https://github.com/sage-code/eve/blob/master/manual/readme.md)
