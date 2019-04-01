## ΞVΞ Structure

EVE is modular language. Scripts are files with extension *.eve stored on a server in project folders. The main folder contains one or more master modules. Each represents an application entry point and can be executed in a separated session. 

**Bookmarks:**

Next bookmarks will lead you to the main concepts required to understand EVE program structure.

* [Server](#server)
* [Modules](#modules)
* [Regions](#regions)
* [Classes](#classes)
* [Methods](#methods)
* [Conditionals](#conditionals)
* [Control flow](#control)
* [Functions](#functions)
* [Pattern match](#pattern-match)
* [Expressions](#expressions)
* [Recursion](#Recursion)
* [Dispatch](#dispatch)

## Server

EVE program is hosted using a virtual machine named Merlin. This is a program capable of running multiple EVE sessions in parallel. Each session represents one application.

You can run same application in two different sessions. The sessions are independent and encapsulated. That means sessions can not communicate two each other.

## Modules

Modules are source code files having extension: *.eve. Module names starts with lowercase letter can contain underscore and digits but no special characters. Longer names that use several words will separate with underscore. The module name can be 64 characters long.

## Regions
Each module is divided into regions. Each region is identified by one of these keywords:

{import, define, global, class, aspect} 

**members**
Members of each region are indented two spaces from left side. A region terminate with region name follow by semi column. Regions can be repeated but can not be nested.

**syntax**
```
+-----------------------------------------------
   First line of a module can be a comment
-----------------------------------------------+
#module_directive
...
$ystem_variable
...
import
  import_region

define
  -- types
  -- constants
  -- variables
  
class <name> is
  -- class_definition
class;  

aspect <name>(<params>) is
  -- asoect defubutuib
over;

+-----------------------------------------------
   Last line of a module can be a comment
-----------------------------------------------+
```

## Declaration order
Order of regions is important. You can not use members before they are defined. Module directives are usually on top follow by globals then other regions can be interlaced.

## System variables
System variable start with prefix "$" and are global variables. System variables are defined in EVE core library. Programmers can use system variables to find modules. Before define and import keyword there is a region where user can define new system variables. 

## Import region
Is used to include one or several modules separated by comma. Import region contains also _"from"_ clause. This is used to indicate what public members we will use without the qualifier. If we do not specify than all members can be accessed only by dot notation: <alias>.<member>;

**syntax**
```
import 
  alias <alias> := <$SYSTEM_VARIABLE>.<relative_path>.<module_name>; 
  ...
  from  <module_name> | <alias>  use all | <member_name>[,<member_name>]...;
  ...

```
**location**
The compiler search modules in local library first then in module folder then in EVE standard library then in path $LEV_PATH. Finally if file is not found the program fail to compile. We can specify the relative path before module name in the import region using "." to separate folder names.  


## Define Region
This region is for declaration of global "members". 

* constant  ::=  type : Identifier := value;
* variable  ::=  type : identifier := value;
* reference ::=  type @ identifier := value;

Global members are visible in current module and modules that imports it. 

## Methods

One aspect is a named region that can receive input/output parameters.

```
aspect name(parameters):
  -- executable region
  ...
recover:
  -- error handler
finalize:
  -- finalization region
over;
```

## aspect name
A aspect is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The aspect are doing something, therefore the best names for methods are verbs.

## Main aspect
If the module is executable using "run" command, it must contain a "main" aspect. This aspect is executed first. If main aspect is missing then the module is a library module and can be imported in other modules but can not be executed.

## Parameters
Parameters are defined in round brackets () separated by comma. Each parameter must have a name and a type. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

```
 param_name ::= type : name := value; -- input parameter
 param_name ::= type @ name; -- output parameter
```
1. One aspect can receive one or more parameters;
1. Parameters having initial values are optional;
1. We can pass arguments by position, or by name;
1. Input parameters are pass by value;
1. Output parameters are pass by reference;

## Variadic parameters

One aspect can receive multiple arguments of the same type separated by comma into one parameter.

* The variadic parameter name start with "*" prefix. 
* The surplus of arguments are captured into last parameter named: "*args". 
* We can use any name instead of "args" but this is the default name. 

**example**
```
aspect main(Array[String]() * args):
  print(args); 
over;
```

## Aspect scope

Every aspect can define local variables, constants or functions. This is called local scope. Members defined in local scope are short leaving and are removed once the aspect is resolved. In this scope a aspect can implement attributes using "@" prefix. Attributes are static properties of the aspect. 

## Aspect Execution
To execute an aspect mention name of the aspect and the arguments. Arguments are enclosed in round parentheses separated by comma.  If an aspect do not have parameters or it have one single parameter the empty list () after the aspect name is not required.

**aspect call**
```
  <method_name>;
  <method_name>  <one_argument>;  
  <method_name> (<argument_list>);
```

## Aspect termination
An aspect end at the last statement before the keyword over; Program execution will continue with the next statement after the aspect call. Keyword "exit" or "panic" can terminate a aspect early. Exit from main aspect will stop the program. 

**Example:**
```
aspect test(Integer: a):
  print(a);
over;

aspect main(List[String]: *args):
  -- number of arguments received:
  Integer: c := args.count();
  
  -- verify condition and exit
  exit if c ≡ 0;
  
  solve test(c); -- aspect call
over;
```

## Side Effects
* The aspect can have access to system variables;
* A aspect can open and write into a file;
* A aspect can print a message or accept input from console;
* If we modify external variables, this is a side-effect;
* A good practice is to use parameters and no side-effects;

**using side-effects**

Program heaving a private aspect add_numbers: 

```
-- global variables
global
  Integer $result;

local  
  Integer p1, p2;

aspect add_numbers() is
  $result := p1 + p2; --side effect
  print($result);
over;

aspect main() is
  p1 := 10;
  p2 := 20;
  add_numbers;   
  expect $result = 30;  
over;
```

**using output parameters**

To avoid system and global variables use output parameters:

```
aspect add(integer: p1,p2, Integer @ out):
  out := p1+p2;
over;

aspect main:
  Integer: result;
  -- reference argument require a variable
  solve add(1,2, out : result);
  print (result); -- expected value 3
  -- negative test
  solve add(1,2,4); -- error, "out" parameter require variable argument
over;
```

Notes: 
* Output parameters are usually the last parameters;
* Output arguments must be specified by name;

## Single dispatch

Dispatch is a form of selection specific to methods and functions. This is a way to identify one _overloaded_ aspect or function by its signature.

Wikipedia: [name mangling](https://en.wikipedia.org/wiki/Name_mangling)

## Multiple dispatch

In multiple dispatch many parameters can be used to identify a aspect. A aspect signature include aspect name and parameter types: both input and output parameters are included in aspect signature.

**aspect Restrictions**
* A aspect call is a statement, can not be used in expressions;
* A aspect with result can be used with assign operator ":=" or a modifier.
* We can not create methods, data types or classes inside a over;
* We can not create references to methods:


## Classes
Classes are composite data types. Once class can be used to create objects.

```
class name(parameters) <: base_class is
  -- definition_region
setup
  -- constructor region
clean
  -- release region
class;
```

***Read more:** [Classes](classes.md)

## Control 

EVE uses _control statements_ to describe a blocks of code that are controlled by conditional expressions. A control statement has a local scope defined with keyword "given". Usually in this scope we declare one or more control variables.


 statement | path/blocks | description
-----------|-------------|---------------------------
 when      | double-path | decision splitter
 quest     | multi-path  | value based selector 
 while     | repetitive  | conditional repetition
 trial     | nulti-block | trial / error multi case

**Read next:** [control.md](control.md)

## Functions

A function can have parameters and produce one or more results. 

```
function name(parameters) => (type :result, ...):
  -- statements
  ...
  result := expression;
recover:
  -- error handler
finalize:
  -- finalization region 
function;
```

**Function call**
The call for a function is using name of the function and round brackets () for arguments. The brackets are mandatory even if there are no arguments, otherwise the function is not executed. 

**syntax**
``` 
  -- call with no arguments:
  <result> := <function_name>();  
  
  -- call with arguments mapped by position
  <result> := <function_name>(<value>, <value> ...); 
  
  -- call using parameter names for mapping
  <result> := <function_name>(<param> := <value>, <param> := <value> ...);   
```

**Parameters**

* Parameters are declared in parenthesis () after the function name. 
* Each parameter has name and type and can have one default value. 
* When a function is called each parameter receive a value that is called argument. 

**Arguments**

There is a difference between the parameter and the argument. The parameter is a local variable in the function scope while arguments are values assigned to these parameters in the function call. Arguments can be literals, constants or variables. 

**Example:**
```
-- function declaration
function sum(Integer: a, b) => (Integer: r):
  r := a + b;
function;
  
aspect main() is
  Integer: r;  
  r := sum(10,20); -- function call
  print(r);        -- this will print 30
over;
```

## Rules

Rules are deterministic λ expressions similar to mathematical functions.

**Notes:** Rules are "first class" objects. 

* may be stored in data structures;
* can be passed as arguments;
* can be used in control structures;
* cab be created in functions or methods.

**pattern**
```
given
  rule rule_name(parameters) => type: (expression);
  type: x;
begin
  -- call rule with arguments
  x := rule_name(arguments);
ready;  
```

**restrictions...**

* rules are deterministic
* rules do not have secondary effects;
* rules do not have output parameters; 

## Conditionals

A condition is using an expression that can have values T or F.   
**syntax**
```
  <statement> if (<condition>);
```

**example**
```
print "True"  if   T;  -- this will print True
print "False" if ¬ F;  -- this will print False

```

**restriction:** 
* can not be used in conjunction with block statements
* can not be used in conjunction with region keywords
* can not be used in conjunction with declarations

## Pattern match

A rule can have multiple conditional expressions named nodes. 

**syntax:**
```
  identifier(parameters) := (value/xp if condition,...default_value) ∈ type;
```

**nodes**
* each node is evaluated until one return a value
* each node can return one single value
* the last node do not use a condition

**example**
```
aspect main:
  -- create a lambda expression
  xp(Integer: p1, p2) => Integer: ( 0 if p1 ≡ 0, 0 if p2 ≡ 0, p1+p2);    
  -- local x
  Integer: x; 
  -- use lambda expression  
  x := xp(0,1); print(x); -- 0 
  x := xp(1,0); print(x); -- 0
  x := xp(2,2); print(x); -- 4  
over;
```

**anonymous expressions**

Expressions can be anonymous. These can be used as arguments or in assign statement.

**syntax**
```
  x := (<result> if <condition>,...<default>); 
```

**example**
```
given
  Logic: b := F;
  Integer: v := 0;   
begin
  v := (1 if b , 2);   
  print v; --> 2
ready;  
```

## Rule as parameter

An aspect or function can receive one or more call-back rules. 

**Example:**
```
aspect test(Integer: f(Logic: x), Logic: p):
  -- call parameter function
  print f(p) --> 1;
over;

aspect main:  
  -- define foo as a rule
  rule foo(Logic: b) => Integer: (1 if b , 2);
  -- use foo as call-back argument  
  print test(foo,T);  -- expect 1
  print test(foo,F);  -- expect 2 
over;
```

## Recursive Rules
A rule that call itself is recursive;

**Example:**
```
aspect main(Integer: p):
  -- define a local recursive function 
  rule  factorial(Integer: n) => Integer: (1 if n ≡ 0 , n * factorial(n-1));
  -- result variable must be declared before use
  Integer: r;
  
  -- call recursive function
  r := factorial(p);   
  print("#n" <+ r);
over;
```

```
> run do_factorial(4)
> 24
```

**Read next**: [Control Flow](control.md)