## EVE Structure

Next bookmarks will lead you to the main concepts required to understand EVE projects.

**Bookmarks:**

* [Modules](#modules)
* [Library](#library)
* [Regions](#regions)
* [Globals](#globals)
* [Classes](#classes)
* [Methods](#methods)
* [Functions](#functions)
* [Expressions](#expressions)
* [Parameters](#parameters)
* [Dispatch](#dispatch)
* [Test cases](#test-cases)
* [Execution](#execution)

## Modules

Modules are source files having extension: *.eve. Module names are using lowercase letters, can also contain underscore or digits but no special characters and no Unicode strings. Longer names that use several words can be separate with underscore. The module name can be 30 characters long.

**members**

* public member identifier start with "." prefix;
* one module can use public members from other modules;
* one module can have public member used in other modules;
* member identifier names can be 30 characters long;

## Main module

Any module that contains method main() is the application main module and can lead a run-time session. A main module can have associated one or more configuration files. The configuration file contain parameter:value pairs used to setup: _global constants_.

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

A module file is divided into regions using keywords: {import, define, global, class, method} 

**module syntax**
```
*****************************************
** Header comments: module purpose
*****************************************

** global region
$constant := "value";
&variable := {1,2,3};
...

** import region
import
  from $path/library_name use (*);

** primitive class declaration
alias 
  Name := library_name.class_name;
  Name := class_name{generic_parameters};
  ...

** shared constants
constant
  @type: NAME := value; ** constant
  
** shared variables
variable
  @type: x;          ** default value
  @type: y := value; ** specify value
  @type: z :: y;     ** copy value
  ...
  
** function declaration
function 
  @type: name(params) => (expression);
  ...

** advanced class declaration
class name(params) <: superclass:
  ...
return;

** method declaration
method name(params):
  ...
return;
```

## Declaration order

Order of regions by default is: {globals, import, type, constant, variable, function, class, method}. Methods and classes can alternate. You can define multiple regions of the same type when members depend on each other. 

## Globals

Globals are declared in first module region, with zero space indentation: 

**declare**

* global constants  ::=  $identifier := value;
* global variables  ::=  #identifier := value;

Global members are visible in application with no prefix. 

## Global constants

Global constants start with prefix "$". Usually are loaded from a configuration file (*.cfg) and do not need to be declared explicit in a _constant_ region. They are known by EVE runtime and can be used in all modules. 

**Note:** 
* Global constants can be defined in a configuration file
* Global constants can be defined in a library.

Several global constants are provided by EVE environment:

* $eve_home  :eve runtime
* $pro_home  :project home
* $eve_lib   :eve lib folder
* $pro_lib   :project lib folder

## Global variables

Global variables are defined in standard library.

**examples**
```
#error  ** contains last error message
#stack  ** contains debug information about current call stack
#trace  ** contains reporting information about executed statements
#level  ** contains how deep is the current call stack
```

**notes:** 
* User can create new global variables specific to one application;
* Prefix "#" is used to avoid scope qualifier and improve code readability;

## Import region

Is used to include members from several other modules into current module: 

**syntax**
```
-- define global constant
$user_path := $root_path/relative_path

import 
  from $user_path use (member_name,...);  ** specific members
  from $user_path use (*);                ** all public members
  ...
```

**note:** 
* $user_path is any path defined by the user;
* spaces in file-names are not supported you must use: "_" instead;
* member alias can rename any member type: {constant, variable, function, method};
* class aliases are final instances of generic classes;

## Shared constants

Shared constants are declared in _constant_ region:

**example**
```
constant
  @double: .PI := 3.14; ** local constant
```

**note:** 
* Constants are immutable entities;
* Constant identifiers are using uppercase letters;
* Public constants are using dot prefix: "."
* Constants are using operator ":=" for initialization;
* Constant type is implicit defined using type inference;

## Shared variables

Shared variables are declared in _variable_ region:

**example**
```
variable
  @double: pi := 3.14; ** shared variable
```

**note:** 
* Shared variables are static;
* Variable names are using lowercase letters;
* Variable data type is specified before the identifier;

## Methods

A method is a named block of code that can be executed multiple times.

* start with keyword _method_;
* has a name identifier followed by a list of parameters;
* after parameter list () use ":"
* can have local variables defined after ":"
* early transfer can be done using keyword _exit_;
* is ending with _return_ statement, that is mandatory;

**prototype**
```
method name(parameters):
  ** declaration region
process
  ** executable region
  exit if (condition);
  ...
return;
```

**Notes:**

* empty list () it is not required when there are no parameters defined only ":" is mandatory;
* unlike a function, a method can have side-effects but do not return a result.

**Method name**
A method is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The methods are doing something, therefore the best names for methods are verbs.

**Main method**
If a module is executable using "run" command, it must contain a "main" method. This method is executed first. If main method is missing then the module is a library and can be imported in other modules but can not be executed using run command.

**Parameters**
Formal parameters are defined in round brackets () separated by comma. Each parameter must have type and name. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

**mandatory**
```
 ** mandatory parameters do not have initial value
 parameter ::= Class_Name : parameter_name ** input parameter
 parameter ::= Class_Name @ parameter_name ** output parameter
```

**optional**
```
 ** optional parameters have explicit initial value
 parameter ::= Class_Name : parameter_name := value ** input parameter
 parameter ::= Class_Name @ parameter_name := value ** output parameter
```

1. One method can receive one or more parameters;
1. Parameters having initial values are optional;
1. Values used for parameters are called arguments;
1. You can assign arguments using name:value pairs or by position;

**Variadic parameters**

One method can receive multiple arguments of the same type separated by comma into one list.

* First arguments can be captured using normal parameters;
* The surplus of arguments are captured into last parameter named: "args";
* A method can have one single variadic parameter;
* The variadic parameter name is declared using "*" instead of ":" or "@". 
* We can use any name instead of "args" but this is the usual name.

**example**
```
method test(@list{@string} * args):
  print(args);
return;
```

**Method context**

Every method has a local context. Members defined in local context are private. In this context a method can implement static attributes using "." prefix. These attributes are properties of the method and can be accessed from current module using dot notation. 

**Method call**
Methods can be used like statements. A method call can be done using method name followed by argument list, enclosed in round parentheses separated by comma. For one single argument, or no arguments parentheses are not required.

```
  method_name;                  ** call method without arguments
  method_name argument_value;   ** call method with single argument
  method_name (argument_list);  ** call method with a list of arguments
```

**Method termination**
A method end with keyword return. When method is terminated, program execution will continue with the next statement after the method call. Keyword _exit_ can terminate a method early and no error is signaled. To signal an error you must use _raise_ keyword. You can terminate a method using _quit_ but this will also terminate the main module,

**Example:**
```
method test(@integer: a):
process
  ** print is a system method
  print a; 
return;

method main(@list[@string]: *args):
  ** number of arguments received:
  @integer: c := args.count();
process  
  ** verify condition and exit
  exit if c = 0;  
  test c; ** method call
return;
```

## Side Effects

A method can have side-effects: 

* modify a shared variable;
* open and write into a file;
* print a message or accept input from console;

**using side-effects**

Next method: "add_numbers" has 2 side effects: 

```
** local variables
variable
  @integer: test; 
  @integer: p1;   
  @integer: p2;   

method add_numbers:
process
  **side effects  
  test := p1 + p2; ** first side-effect
  print (test);    ** second side-effect
return;

method main:
process
  p1 := 10; ** side effect
  p2 := 20; ** side effect
  add_numbers;
  expect result = 30;
return;
```

**using output parameters**

To avoid shared variables you can use input/output parameters:

```
method add(@@integer: p1 = 0, p2 = 1,  @@integer + out):
process
  out := p1 + p2;
return;

method main:
  @integer: result;
process  
  ** reference argument require a variable
  add(1,2, result);
  print (result); ** expected value 3
  ** negative test
  add (1,2,4); ** error, "out" parameter require a variable
return;
```

**Notes:**

* Output parameters are usually the last parameters;
* A method call is a statement, can not be used in expressions;
* You can not create nested members in methods;
* You can not create references to methods;

## Functions

Functions are declared in a region that start with keyword: "function".

```
function 
  @type: name(parameters) => (expression);
```

* A function can have parameters; 
* A function can have a single result;
* Result type is declared before function name. 

**Function call**
The call for a function is using name of the function and round brackets () for arguments. The brackets are mandatory even if there are no arguments, otherwise the function is not executed. 

**pattern:**
``` 
function
  @type: function_name() => (expression);
  
given 
  @type: result;
do  
  ** call with no arguments:
  result := function_name();
  
  ** call with arguments mapped by position
  result := function_name(value, ...);
  
  ** call using parameter names and pair-up operator ":"
  result := function_name(parameter:value ...);
done;  
```

**note:**
value ::= constant | variable | expression | function call

**formal parameters**

* Parameters are declared in parenthesis () after the function name, 
* Each parameter has name and type and can have one default value, 
* When a function is called each parameter receive a value that is called argument. 

**call arguments**

There is a difference between the parameter and the argument. The parameter is a local variable in the function scope while arguments are values assigned to these parameters in the function call. Arguments can be literals, constants or variables. 

**Example:**
```
** function declaration
function @integer: sum(@integer: a, b) =>  (a + b);
  
method main:
  @integer: r;
process  
  r := sum(10,20);  ** function call
  print(r);         ** this will print 30
return;
```

## Expressions

A ternary operator is "if". Can be used with conditional expressions to return one value or other.   
**syntax**
```
  a := (value if (condition) | value)
```

**example**
```
print "true" if True;
```

## λ expressions

An λ expression we can use multiple conditionals nodes separated by comma:

**syntax:**
```
  identifier := (value if condition,...| default_value)
```

**nodes**
* each node is evaluated until one is true
* each node can return one single value
* the last node do not use a condition but "|"

**example**
```
method main:
  @integer: p1, p2, x;
process
  p1 := 2;
  p2 := 1;
  ** using λ expression  
  x  := ( 0 if p1 = 0, 0 if p2 = 0 | p1+p2);
  print x; ** expect: 3 
return;
```

**example**
```
given
  @logic:   b := false;
  @integer: v := 0;   
do
  v := (1 if b : 2);   
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

## Test cases 

A method can be organized as a work-flow of multiple steps that can pass or fail depending on conditions.

```
method main:
  ** local context
process
  ** initialization
  ...
  step c1("description") do
    ...
    exit if (condition);
  step c2("description") do
    ...
    pass if (condition);    
  step c3("description") do
    ...
    fail if (condition);    
  step c4("description") do    
    ...
recover  
  ** exception region
  ...
  resume if (condition);
  ...
closure
  ** finalization region
  ...    
return;
```

**New keywords:**

* exit,   will terminate the method early
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

eve:> run path/module_name -c file.cfg -m 2048GB


**using exit**

Using exit from _main_ will end module execution.

**Example:**
```
** using when prefix condition
when (condition) do
  exit;
done;

** using if postfix condition
exit if (condition);
```

**using quit**

This is a way to release all locked resources and stop the application session.

**Example:**
```
** using when prefix condition
when (condition) do
  quit;
done;

** using if postfix condition
quit if (condition);
```

**Read next**: [Syntax Overview](overview.md)