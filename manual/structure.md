## ΞVΞ Structure

EVE is modular language. Scripts are files with extension *.eve stored on a server in project folders. The main folder contains one or more master modules. Each represents an application entry point and can be executed in a separated session. 

**Bookmarks:**

Next bookmarks will lead you to the main concepts required to understand EVE program structure.

* [Modules](#modules)
* [Regions](#regions)
* [Classes](#classes)
* [methods](#methods)
* [Conditionals](#conditionals)
* [Control flow](#control)
* [Functions](#functions)
* [Expressions](#λ-expressions)
* [Recursion](#Recursion)
* [Dispatch](#dispatch)
* [Server](#server)

## Modules

Modules are source code files having extension: *.eve. Module names starts with lowercase letter can contain underscore and digits but no special characters. Longer names that use several words will separate with underscore. The module name can be 64 characters long.

## Regions
Each module is divided into regions. Each region is identified by one of these keywords:

{import, define, global, class, method} 

**members**
Members of each region are indented two spaces from left side. A region terminate with region name follow by semi column. Regions can be repeated but can not be nested.

**syntax**
```
************************************************
**   First line of a module can be a comment  **
************************************************
#module_directive
...
$ystem_variable
...
import
  import_region

## head comment
define
  ** types
  ** constants
  ** variables
  
class: name
  ** class_definition
finish;

method: main(params)   
  ** method_definition
finish;

function: main(params) => type
  ** function_definition
finish.
/****************************************************
  Usually after finish we use ";" to continue
  Last "finish" is terminated with "." to end module 
****************************************************/ 
```

## Declaration order
Order of regions is important. You can not use members before they are defined. Module directives are usually on top follow by globals then other regions can be interlaced.

## System variables
System variable start with prefix "$" and are global variables. System variables are defined in EVE core library. Programmers can use system variables to find modules. Before define and import keyword there is a region where user can define new system variables. 

## Import region
Is used to include one or several modules separated by comma. Import region contains also _"from"_ clause. This is used to indicate what members we will use without the qualifier. If we do not specify than all members can be accessed only by dot notation: alias.member;

**syntax**
```
import 
  alias name := $PATH_VARIABLE.relative_path.module_name; 
  ...
  from  alias_name | module_name  use all | use member_name,...;
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

## methods

A method is a subroutine that can receive input/output parameters and have side-effects.

```
method: name(parameters)
  ** declaration region
start
  ** executable region
  ...
finish;
```

## Method name
A method is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The methods are doing something, therefore the best names for methods are verbs.

## Main method
If the module is executable using "run" command, it must contain a "main" method. This method is executed first. If main method is missing then the module is a library module and can be imported in other modules but can not be executed.

## Parameters
Parameters are defined in round brackets () separated by comma. Each parameter must have a name and a type. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

```
 param_name ::= type : name := value; ** input parameter
 param_name ::= type @ name; ** output parameter
```
1. One method can receive one or more parameters;
1. Parameters having initial values are optional;
1. We can pass arguments by position, or by name;
1. Input parameters are pass by value;
1. Output parameters are pass by reference;

## Variadic parameters

One method can receive multiple arguments of the same type separated by comma into one parameter.

* The variadic parameter name start with "*" prefix. 
* The surplus of arguments are captured into last parameter named: "*args". 
* We can use any name instead of "args" but this is the default name. 

**example**
```
method: main(Array[String]() * args)
  print(args)
finish;
```

## Method scope

Every method can define local variables, constants or functions. This is called local scope. Members defined in local scope are short leaving and are removed once the method is resolved. In this scope a method can implement attributes using "@" prefix. Attributes are factor properties of the method. 

## Method Execution
To execute an method you use keyword "solve" then method name followed by arguments. Arguments are enclosed in round parentheses separated by comma.  If an method do not have parameters or it have one single parameter the empty list () after the method name is not required.

**method call**
```
  method_name () 
  method_name (argument_list)
```

## Method termination
A method end with keyword finish or exit. When method is terminated, program execution will continue with the next statement after the method call. Keyword "exit" or "panic" can terminate a method early. Exit from the "main" method will stop the program execution early. 

**Example:**
```
method: test(Integer: a)
start
  print (a);
finish;

method: main(List[String]: *args)
  ** number of arguments received:
  Integer: c := args.count();
start  
  ** verify condition and exit
  exit if c = 0;
  
  test(c); ** method call
finish;
```

## Side Effects
* The method can have access to system variables;
* A method can open and write into a file;
* A method can print a message or accept input from console;
* If we modify external variables, this is a side-effect;
* A good practice is to use parameters and no side-effects;

**using side-effects**

Program heaving a private method add_numbers: 

```
** global variables
global
  Integer: $result;

static
  Integer: p1, p2;

method: add_numbers()
start
  $result := p1 + p2 **side effect  
  print($result);
finish;

method: main()
start
  p1 := 10;
  p2 := 20;
  add_numbers;   
  expect $result = 30;  
finish;
```

**using output parameters**

To avoid system and global variables use output parameters:

```
method: add(integer p1,p2, Integer: @out)
start
  @out := p1+p2;
finish;

method: main()
  Integer: result;
start  
  ** reference argument require a variable
  add(1,2, @out:result);
  print (result); ** expected value 3
  ** negative test
  add(1,2,4); ** error, "out" parameter require variable argument
finish;
```

Notes: 
* Output parameters are usually the last parameters;
* Output arguments must be specified by name;

## Single dispatch

Dispatch is a form of selection specific to methods and functions. This is a way to identify one _overloaded_ method or function by its signature.

Wikipedia: [name mangling](https://en.wikipedia.org/wiki/Name_mangling)

## Multiple dispatch

In multiple dispatch many parameters can be used to identify a method. A method signature include method name and parameter types: both input and output parameters are included in method signature.

**method Restrictions**
* A method call is a statement, can not be used in expressions;
* We can not create methods, data types or classes inside a over
* We can not create references to methods:


## Classes
Classes are composite data types. Once class can be used to create objects.

```
class: name(parameters) <: base_class
  ** definition_region
start
  ** constructor region
scrap
  ** release region
finish;
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
function: name(parameters) => (result_type: result, ...)
  ** declaration
start
  ** statements
  ...
  result := expression;
finish;
```

**Function call**
The call for a function is using name of the function and round brackets () for arguments. The brackets are mandatory even if there are no arguments, otherwise the function is not executed. 

**syntax**
``` 
  ** call with no arguments:
  <result> := <function_name>();  
  
  ** call with arguments mapped by position
  <result> := <function_name>(<value>, <value> ...); 
  
  ** call using parameter names for mapping
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
** function declaration
function: sum(Integer: a, b) => (Integer: result)
start
  result := a + b;
finish;
  
method: main()
  Integer: r
start  
  r := sum(10,20)  -- function call
  print(r)         -- this will print 30
finish;
```

## Conditionals

A condition is using an expression that can have values T or F.   
**syntax**
```
  statement if (condition);
```

**example**
```
print "True"  if  T;  ** this will print True
print "False" if !F;  ** this will print False

```

**restriction:** 
* can not be used in conjunction with block statements
* can not be used in conjunction with region keywords
* can not be used in conjunction with declarations

## λ expression

An λ expression can have multiple conditionals named nodes. 

**syntax:**
```
  identifier := (value:condition,...default_value);
```

**nodes**
* each node is evaluated until one return a value
* each node can return one single value
* the last node do not use a condition

**example**
```
method: main()
  Integer: p1, p2, x
start  
  p1 := 2
  p2 := 1
  ** using λ expression  
  x:= ( 0 : p1 = 0, 0 : p2 = 0, p1+p2)
  print(x); ** 3 
finish;
```

**example**
```
given
  Logic:   b := F;
  Integer: v := 0;   
begin
  v := (1 : b, 2);   
  print v; ** 2
ready  
```

## Server

EVE program is hosted using a virtual machine named Merlin. This is a program capable of running multiple EVE sessions in parallel. Each session represents one application.

You can run same application in two different sessions. The sessions are independent and encapsulated. That means sessions can not communicate two each other.

**Read next**: [Control Flow](control.md)