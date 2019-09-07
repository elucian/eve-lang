## EVE Structure

Next bookmarks will lead you to the main concepts required to understand EVE projects.

**Bookmarks:**

* [Modules](#modules)
* [Library](#library)
* [Regions](#regions)
* [Globals](#globals)
* [Classes](#classes)
* [Routines](#routine)
* [Functions](#functions)
* [Expressions](#expressions)
* [Parameters](#parameters)
* [Dispatch](#dispatch)
* [Work-flow](#work-flow)
* [Execution](#execution)

## Modules

Modules are source files having extension: *.eve. Module names are using lowercase letters, can also contain underscore or digits but no special characters and no Unicode strings. Longer names that use several words can be separate with underscore. The module name can be 30 characters long.

**members**

* public member identifier start with "." prefix;
* one module can use public members from other modules;
* one module can have public member used in other modules;
* member identifier names can be 30 characters long;

### Drivers
A _driver_ is the main application module. It has the role to lead the application main thread. When _driver_ execution is over the application give control back to the operating system.

**notes:**

* A _driver_ is the application entry point,
* Any application must have one single _driver_,
* A _driver_ can read configuration files at startup,
* A driver can be terminated early using keywords: _halt_, or _fail_.


## Main module

Module that contains routine main() is the application main module. Main module can have associated one or more configuration files. The configuration file contain parameter:value pairs used to setup: _system constants_.

**properties**

* main module is independent, can not be imported in other modules or suites;
* main module receive parameters as constants from a configuration file;
* main module do not have public methods and do not have output variables;

## Library

A _library_ is a shared folder containing reusable modules.

* library contain generic functionality and can be shared between multiple projects;
* using import several modules can be loaded from a folder at once;
* circular import is possible: run-time environment has a protection against infinite recursion;
* after import you can call public members of a library using _dot notation_;

## Regions

A module file is divided into regions using keywords: {import, define, global, class, routine} 

**module syntax**
```
+-----------------------------------------
|   Header comments: module purpose      |
+----------------------------------------+
module main:

** global region 
$sys_con := "value"; // system constant
@sys_var := {1,2,3}; // system variable
...

** import region
import
  from $path/library_name use (*);

** qualifier suppression
alias 
  ClassName = library_name.class_name;
  ClassName = class_name{generic_parameters};
  ...

** shared constants
constant
  TypeName: NAME = value; //  constant (UPPERCASE NAMES)
  
** shared variables
variable
  TypeName: x;         // default value = 0
  TypeName: y = value; // specify value ≠ 0
  ...
  
** function declaration
function 
  TypeName: name(params) => (expression);
  ...

** advanced class declaration
class ClassName(params) <: Superclass:
  ...
return;

** routine declaration
routine name(params):
  ...
return;

** rogue statements
given
  ...
do  
  ...
done;

module. // end module main
```

### Rogue statement

A _driver_ or _aspect_ can contain statements that do not belong to any rule. These are called _rogue_ statements and are driving the program execution. Rogue statements are executed top down until to last keyword that is usually _over_.


## Declaration order

Order of regions by default is: {globals, import, type, constant, variable, function, class, routine}. Routines and classes can alternate. You can define multiple regions of the same type when members depend on each other. 

## Globals

Globals are declared in first module region, with zero space indentation: 

**declare**

* system constants  ::=  $identifier := value;
* system variabless ::=  @identifier := value;

Global members are visible in application with no prefix. 

## System constants

System constants start with prefix "$". Usually are loaded from a configuration file (*.cfg) and do not need to be declared explicit in a _constant_ region. They are known by EVE runtime and can be used in all modules. 

**Note:** 
* System constants can be defined in a configuration file
* System constants can be defined in a library.

Several system constants are provided by EVE environment:

* $eve_home  :eve runtime
* $pro_home  :project home
* $eve_lib   :eve lib folder
* $pro_lib   :project lib folder

## System variables

System variables are starting with prefix "@" and are defined in standard library.

* @error  :contains last error message
* @stack  :contains debug information about current call stack
* @trace  :contains reporting information about executed statements
* @level  :contains how deep is the current call stack


**notes:** 
* User can create new system variables specific to one application;
* Prefix "@" is used to avoid scope qualifier and improve code readability;

## Import region

Is used to include members from several other modules into current module: 

**syntax**
```
** define global constant
$user_path := $root_path/relative_path

import 
  from $user_path use (member_name,...);  // specific members
  from $user_path use (*);                // all public members
  ...
```

**note:** 
* $user_path is any path defined by the user;
* spaces in file-names are not supported you must use: "_" instead;
* member alias can rename any member TypeName: {constant, variable, function, routine};
* class aliases are final instances of generic classes;

## Shared constants

Shared constants are declared in _constant_ region, with "." prefix.

**example**
```
constant
  Double:.PI = 3.14; // shared constant
```

**note:** 
* Constants are immutable entities, they can not be altered,
* Constant identifiers are starting with one uppercase letter,
* Public constants are using dot prefix: ".",
* Private constants are using underscore prefix "_",
* Constants are using operator "=" for initialization,

## Shared variables

Shared variables are declared in _variable_ region:

**example**
```
variable
  Double :pi = 3.14; //  shared variable
```

**note:** 
* Shared variables are static;
* Identifiers are using lowercase letters;
* Data type is specified before the identifier;

## Routines

A routine is a named block of code that can be executed multiple times.

* start with keyword _routine_;
* has a name identifier followed by a list of parameters;
* after parameter list () use ":"
* can have local variables defined after ":"
* early transfer can be done using keyword _exit_;
* is ending with _return_ statement, that is mandatory;

**prototype**

Routine with result:
```
routine name(Type:parameter, Type<result...):
  ** declaration region
  ...
process
  ** executable region
  exit if condition;
  ...
  result := value; //result parameter
return;
```


**Notes:**

* empty list () is required even if there are no parameters defined;
* output parameters are declared with symbol "<" instead of ":";
* unlike a function, a routine can have side-effects but do not return a result.

**Routine name**
A routine is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The methods are doing something, therefore the best names for methods are verbs.

**Main routine**
If a module is executable using "run" command, it must contain a "main" routine. This routine is executed first. If main routine is missing then the module is a library and can be imported in other modules but can not be executed using run command.

**Parameters**
Formal parameters are defined in round brackets () separated by comma. Each parameter must have type and name. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

**mandatory**
```
 ** mandatory parameters do not have initial value
 parameter ::= ClassName > parameter_name [= value] // input only parameter   (by copy)
 parameter ::= ClassName < parameter_name [= value] // force output parameter (by reference)
 parameter ::= ClassName : parameter_name [= value] // input & output parameter
```

1. One routine can receive one or more parameters,
1. Parameters having initial values are optional,
1. Values used for parameters in routine call are named arguments,
1. You can assign arguments using name:value pairs or by position;

**Variable list of arguments**

One routine can receive multiple arguments of the same type separated by comma into a list.

* First arguments can be captured using normal parameters,
* The surplus of arguments are captured into last parameter named: "*args",
* A routine can have one single parameter for variable list of arguments,
* The list parameter name is declared using "*" instead of { ":", "<", ">"},
* We can use any name instead of "*args" but this is the usual name.

**example**
```
routine test(List{String} *args):
  write args;
return;

** call routine with variable number of arguments
test ("a","b","c"); // use 3 arguments
test ("a","b");     // use 2 arguments

** you can use operator "*" to _spread_ collection elements
given
  Set{Integer} argument;
do
  forge argument := {1, 2, 3};
  test (*argument);  // spread collection elements
done;  
```

**Routine context**

Every routine has a local context. In this context a routine can implement variables with no prefix. These variables are can not be accessed from outside of the routine. 

**Routine call**
Routines can be used like statements. A routine call can be done using routine name followed by argument list. For one single argument, or no arguments parentheses are not required.

```
  routine_name;                  //  call routine without arguments
  routine_name argument_value;   //  call routine with single argument
  routine_name (argument_list);  //  call routine with a list of arguments
```

argument_value ::= constant literal, expression or variable
argument_list  := agument_name:argument_value, ...


**Routine termination**
A routine end with keyword return. When routine is terminated, program execution will continue with the next statement after the routine call. Keyword _exit_ can terminate a routine early and no error is signaled. To signal an error you must use _raise_ keyword. You can terminate a routine using _quit_ but this will also terminate the main module,

**Example:**
```
routine test(Integer: a):
process
  ** print is a system routine
  print a; 
return;

routine main(List{String}: *args):
  ** number of arguments received:
  Integer: c = args.length;
process
  ** verify condition and exit
  exit if c = 0;  
  test c; //  routine call
return;
```

## Side Effects

A routine can have side-effects: 

* modify a shared variable;
* open and write into a file;
* print a message or accept input from console;

**using side-effects**

Next routine: "add_numbers" has 2 side effects: 

```
** local variables
variable
  Integer: test; 
  Integer: p1;   
  Integer: p2;   

routine add_numbers:
process
  **side effects  
  reset test := p1 + p2; //  first side-effect
  print test;            //  second side-effect
return;

routine main():
process
  alter p1 := 10; //  side effect
  alter p2 := 20; //  side effect
  add_numbers;    //  call routine add_numbers;
  expect result = 30;
return;
```

**using output parameters**

To avoid shared variables you can use input/output parameters:

```
routine add(Integer: p1 = 0, p2 = 1,  Integer < out):
process
  alter out := p1 + p2;
return;

routine main():
  Integer: result;
process  
  ** reference argument require a variable
  add(1,2, result);
  print result; //  expected value 3
  ** negative test
  add(1,2,4);    //  error, "out" parameter require a variable
return;
```

**Notes:**

* Output parameters are usually the last parameters;
* Routine calls are statements, not expressions;
* Routines can have local variables, constants and functions;
* You can not create nested routines;
* You can not create references to routines;

## Functions

Functions are declared in a region that start with keyword: "function".

```
function 
  TypeName: name(parameters) => (expression);
```

* A function can have only input parameters, 
* A function can have a one single result,
* A function can have a single expression,
* A function can be created by a routine,
* A routine can receive parameters of type function,
* Result type is declared before function name,
* You can declare more than one function in same region.

**Function call**
The call for a function is using name of the function and round brackets () for arguments. The brackets are mandatory even if there are no arguments, otherwise the function is not executed. 

**pattern:**
``` 
function
  TypeName: function_name(Type : param = value,...) => (expression);
  
given 
  TypeName: result;
do  
  ** call with no arguments:
  alter result := function_name();
  
  ** call with arguments mapped by position
  alter result := function_name(value, ...);
  
  ** call using parameter names and pair-up operator ":"
  alter result := function_name(parameter:value ...);
done;  
```

**note:**
Argument value can be anything that translate to a value of expected type:

* value ::= constant | variable 
* value ::= expression | other function call

**formal parameters**

* Parameters are declared in parenthesis () after the function name, 
* Each parameter has name and type and can have one default value, 
* When a function is called each parameter receive a value that is called argument. 

**call arguments**

There is a difference between the parameter and the argument. The parameter is a local variable in the function scope while arguments are values assigned to these parameters with a function call. Arguments can be literals, constants or variables. 

**Example:**
```
** main routine  
routine main():
  Integer: sum(Integer: a, b) => (a + b); // local function
process  
  print sum(1,2);  // 3
  print sum(2,4);  // 6
return;
```

## Expressions

A ternary operator is "if". Can be used with conditional expressions to return one value or other.   
**syntax**
```
alter a := (value if condition, value)
```

**example**
```
write ("true" if True, "false"); // true
```

### λ expressions

An λ expression we can use multiple conditionals nodes separated by comma:

**syntax:**
```
  identifier := (value if condition,...,default_value)
```

**nodes**
* each node is evaluated until one is true,
* each node can return one single value,
* the last node do not use a condition but ","

**example**
```
routine main():
  Integer: p1, p2, x;
process
  p1 := 2;
  p2 := 1;
  ** using λ expression  
  x  := ( 0 if p1 = 0, 0 if p2 = 0, p1+p2);
  print x; // expect: 3 
return;
```

**example**
```
given
  Logic:   b := false;
  Integer: v := 0;   
do
  alter v := (1 if b, 2);   
  expect v = 2;  
  print v;   
done; 
```

## Dispatch

Dispatch is a form of subroutine selection by signature. It makes possible multiple subroutines with the same and different parameters. These kind of subroutines are _overloaded_. Subroutine signature include name, parameter types and result types.

**Wikipedia:** [name mangling](https://en.wikipedia.org/wiki/Name_mangling)

## Classes
Classes are composite data types. We use a classes to create multiple objects with same structure. Each object is a reference to a location in memory were the object is stored. An object is also called instance of a class.

```
class name(parameters) <: base_class:
  ** definition region
create
  ** constructor region
remove
  ** release region
return;
```
**Read more:** [Classes](classes.md)

## Work-flow

A routine can be organized as a work-flow with multiple steps that can _pass_ or _fail_ depending on conditions.

```
routine main():
  ** local context
process
  ** initialization
  ...
  step c1("description") do
    ...
    exit if condition;
  step c2("description") do
    ...
    pass if condition;    
  step c3("description") do
    ...
    fail if condition;    
  step c4("description") do    
    ...
recover  
  ** exception region
  ...
  resume if condition;
  ...
release
  ** finalization region
  ...    
return;
```

**New keywords:**

* exit,   will terminate the routine early
* solve,  will continue with a forward case
* retry,  will continue with a previous case
* resume, will continue with next case after the one that failed

## Execution

EVE modules are executed using a virtual machine. You can start the virtual machine as a service or as console application. In console mode you can _run_ only a one module. In service mode you can _run_ multiple sessions with different startup parameters. Each session is independent and can _run_ one single module. 

Service mode is using a general configuration file: eve.cfg. This file contains information about all application locations and configuration files for each session. After the service starts this file is parsed and each applications start automatically. The service will create a log file for each application.

**memory**
Server is in charge of allocating memory for one session before the application starts. There is no shared memory between sessions. That is a session is dedicated for a single application. After application is terminated the memory is released.
 
To start an application there are 2 methods:

1. Using the command line with parameters
2. Using console command line with commands

```
eve:> run path/module_name -c file.cfg -m 2048GB
```

**driver:**

When a program is executed the driver is located and executed first. If a program do not have a "driver", it can not be executed nor compiled. The driver is the program main entry point. It is executed only once. 

**aspect:**

One aspect is executed from driver or from another aspect. When executed rogue statements of an aspect are executed top down in sequential order. You can not run an aspect from itself. Recursive aspects are not supported.

**module:**

The driver or aspect can load numerous modules. After loading, all public elements can be executed on demand. Before execution the driver can interact with the user to ask for input. After executing it can print feedback and reuse or 


**using exit**

Using exit from _main_ will end module execution.

**Example:**
```
** using when prefix condition
when condition do
  exit;
done;

** using if postfix condition
exit if condition;
```

**using quit**

This is a way to release all locked resources and stop the application session.

**Example:**
```
** using when prefix condition
when condition do
  quit;
done;

** using if postfix condition
quit if condition;
```

**Read next**: [Syntax Overview](overview.md)