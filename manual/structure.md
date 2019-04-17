## ΞVΞ Structure

EVE is modular language. Scripts are files with extension *.eve stored on a server in project folders. The main folder contains one or more master modules. Each represents an application entry point and can be executed in a separated session. 

**Bookmarks:**

Next bookmarks will lead you to the main concepts required to understand EVE program structure.

* [Modules](#modules)
* [Regions](#regions)
* [Classes](#classes)
* [Methods](#methods)
* [Dispatch](#dispatch)
* [Parameters](#parameters)
* [Control flow](#control)
* [Functions](#functions)
* [Conditionals](#conditionals)
* [Expressions](#expressions)
* [Server](#server)
* [Execution](#drivers)
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
#directive
#directive
...
$ystem_variable
...
import
  import_region

## head comment
define
  ** static
  ** type
global
  ** public variables
  
class: name
  ** class_definition
return;

method: name(params)   
  ** method_definition
return;

function: name(params) => type
  ** function_definition
return;
******************************************************
**  Usually after return we use "" to continue        
**  Last "return" is terminated with "." to end module  
******************************************************* 
```

## Declaration order
Order of regions is important. You can not use members before they are defined. Directives are usually on top follow by globals then other regions can be interlaced.

## System variables
System variable start with prefix "$" and are global variables. System variables are defined in EVE core library. Programmers can use system variables to find modules. Before define and import keyword there is a region where user can define new system variables. 

## Import region
Is used to include one or several modules separated by comma. Import region contains also _"from"_ clause. This is used to indicate what members we will use without the qualifier. If we do not specify than all members can be accessed only by dot notation: alias.member;

**syntax**
```
import 
  alias: alias_name := $PATH_VARIABLE.relative_path.library_name 
  ...
  from alias_name use all 
  from alias_name use member_name,...
  ...

```
**location**
The compiler search modules in local library first then in module folder then in EVE standard library then in path $LEV_PATH. Finally if file is not found the program fail to compile. We can specify the relative path before module name in the import region using "." to separate folder names.  

**Note:** 

* Only a #library or #module can be imported not a #driver
* A #driver can be executed but can not be imported

## Define Region
This region is for declaration of global "members". 

* constant  ::=  type : Identifier := value;
* variable  ::=  type : identifier := value;
* reference ::=  type @ identifier := value;

Global members are visible in current module and modules that imports it. 

## Methods

A method is a subroutine that can receive input/output parameters and have side-effects.

```
method: name(parameters)
  ** declaration region
process
  ** executable region
  ...
return;
```

## Method name
A method is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The methods are doing something, therefore the best names for methods are verbs.

## Main method
If the module is executable using "run" command, it must contain a "main" method. This method is executed first. If main method is missing then the module is a library module and can be imported in other modules but can not be executed.

## Parameters
Parameters are defined in round brackets () separated by comma. Each parameter must have a name and a type. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

```
 param_name ::= type : name := value ** input parameter
 param_name ::= type @ name ** output parameter
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
return;
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
A method block end with keyword return. When method is terminated, program execution will continue with the next statement after the method call. Keyword "exit" or "panic" can terminate a method early. 

**Example:**
```
method: test(Integer: a)
process
  print (a)
return;

method: main(List[String]: *args)
  ** number of arguments received:
  Integer: c := args.count()
process  
  ** verify condition and exit
  exit if c = 0
  
  test(c) ** method call
return;
```

## Side Effects
* A method have access to global variables;
* A method can open and write into a file;
* A method can print a message or accept input from console;
* If we modify global variables, this is a side-effect;
* A good practice is to use parameters no side-effects;

**using side-effects**

Program heaving a private method add_numbers: 

```
** global variables

global
  Integer: test 
  Integer: p1, p2
  
method: add_numbers()
process
  **side effects  
  test := p1 + p2 
  print(test)
return;

method: main()
process
  p1 := 10
  p2 := 20
  add_numbers()   
  expect result = 30  
return;
```

**using output parameters**

To avoid system and global variables you use output parameters:

```
method: add(integer: p1,p2, Integer @ out)
process
  out := p1+p2
return;

method: main()
  Integer @ result
process  
  ** reference argument require a variable
  add(1,2, out :: result)
  print (result) ** expected value 3
  ** negative test
  add(1,2,4) ** error, "out" parameter require variable argument
return;
```

**Notes:**

* Output parameters are usually the last parameters;
* Output arguments must be specified by name;
* A method call is a statement, can not be used in expressions;
* We can not create methods, data types or classes inside a method;
* We can not create references to methods;

## Dispatch

Dispatch is a form of selection specific to methods and functions. This is a way to identify one _overloaded_ method or function by its signature. A method signature include method name and parameter types.


**Wikipedia:** [name mangling](https://en.wikipedia.org/wiki/Name_mangling)


## Classes
Classes are composite smart data types. We use a class to create objects.

```
class: name(parameters) <: base_class
  ** definition_region
create
  ** constructor region
scrap
  ** release region
return;
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
process
  ** statements
  ...
  result := expression
return;
```

**Function call**
The call for a function is using name of the function and round brackets () for arguments. The brackets are mandatory even if there are no arguments, otherwise the function is not executed. 

**syntax**
``` 
  ** call with no arguments:
  <result> := <function_name>()  
  
  ** call with arguments mapped by position
  <result> := <function_name>(value, ...) 
  
  ** call using parameter names for mapping
  <result> := <function_name>(param : value ...)   
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
process
  result := a + b
return;
  
method: main() 
  Integer: r
process  
  r := sum(10,20)  ** function call
  print(r)         ** this will print 30
return;
```

## Conditionals

A condition is using an expression that can have values T or F.   
**syntax**
```
  statement if (condition)
```

**example**
```
print "True"  if  True;  ** this will print True
print "False" if !False;  ** this will print False

```

**restriction:** 

* can not be used in conjunction with region keywords
* can not be used in conjunction with declarations

## Expressions

An λ expression can have multiple conditionals named nodes. 

**syntax:**
```
  identifier := (value if condition,...default_value)
```

**nodes**
* each node is evaluated until one return a value
* each node can return one single value
* the last node do not use a condition

**example**
```
method: main()
  Integer: p1, p2, x
process
  p1 := 2
  p2 := 1
  ** using λ expression  
  x  := ( 0 if p1 = 0, 0 if p2 = 0, p1+p2)
  print x ** expect: 3 
return;
```

**example**
```
given
  Logic:   b := F
  Integer: v := 0   
begin
  v := (1 if b, 2)   
  print v ** expect 2  
ready  
```

## Server

EVE program is hosted using a virtual machine. This is capable of running multiple sessions in parallel. Each session represents one independent application. You can run same application in different sessions. The sessions are independent and encapsulated. That means sessions can not communicate with each other.

Server is in charge of allocating memory for one session before the application starts. There is no shared memory. That is a session is dedicated for a single application. After application is terminated the memory is released.

This is the reason EVE do not use parallel programming. The server is handling all the parallel work. EVE applications are single threaded applications. This also simplify the interpreter. There is no possibility to have race conditions or unexpected results.

## Execution

To execute a program or application there are 2 methods:

1. Using the command line with parameters
2. Using console command line with commands

eve:> run driver_name

Only driver files and modules can be executed. Library files must be imported. You can executed a module from a driver or from another module. When you execute a module the _main_ method is executed. This is the only public method of a module. If a module do not have the _main_ method then it must be a #library.

**notes**

* You can use _alias_ to create an alias for module name before you run it. 
* You can use _from_  to import public members from a library and avoid dot notation.


**Example:**
```
#driver "test"

import 
   alias: my_lib    := $pro_lib/my_lib.eve
   alias: my_module := $pro_mod/my_module   
   
   from: my_lib use all

** you can run a module with arguments
method main()
process
  run my_module(arguments)
method
```

**Read next**: [Control Flow](control.md)