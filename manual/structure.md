## ΞVΞ Structure

Next bookmarks will lead you to the main concepts required to understand EVE program structure.

**Bookmarks:**

* [Modules](#modules)
* [Suites](#suites)
* [Library](#library)
* [Regions](#regions)
* [Classes](#classes)
* [Methods](#methods)
* [Functions](#functions)
* [Expressions](#expressions)
* [Parameters](#parameters)
* [Dispatch](#dispatch)
* [Test cases](#test-cases)
* [Execution](#execution)

## Modules

Modules are source files having extension: *.eve. Module names are using lowercase letters, can also contain underscore or digits but no special characters and no Unicode strings. Longer names that use several words can be separate with underscore. The module name can be 64 characters long.

**properties**

* one module can use public members from other modules;
* one module can have public member used in other modules;

## Main module
Any module that contains method main() is a main module and can lead a run-time session. A module can have associated one or more configuration files. The configuration file contain parameter/value pairs used to generate the: _system variables_.

**properties**

* main module is independent, can not be imported in other modules or suites;
* main module can receive values for system variables using a configuration file;
* main module do not have public methods and do not have output variables;

## Library

A _library_ is a shared folder containing reusable modules.

* library contain generic functionality and can be shared between multiple projects;
* using import several modules can be loaded from a folder at once;
* circular import is possible: we protect against infinite recursion;
* after import you can call public members of a library using dot notation;

## Regions
A module file is divided into regions using keywords: {import, define, global, class, method} 

**module syntax**
```
*****************************************
** Header comments: module purpose
*****************************************
module
  .name        := 'module name'; 
  .description := 'short description';
  .echo        := 'off';
  .debug       := 'off';
  .trace       := 'off';   
...
** import region
import
  library_name

** type declaration
type 
  name[parameters]: type_descriptor;
  ...

** public constants and variables
global
  $x  := 0 :Integer; -- constant
  #y  := 0 :Integer; -- variable
  @z  := 0 :Integer; -- reference
  ...

** local constants and variables
local
  v : type_name; 
  
** function declaration
function 
  name(params): Type := (expression);
  ...

** class declaration
class name(params): superclass
  ...
return;

** method declaration
method name(params) => (result: Type, ...)
  ...
return;
```

## Declaration order
Order of regions by default is: {module, import, type, global, function, class, method}. Method and class declarations can be alternated. You can define multiple regions of the same type. 

## System variables
System variable start with prefix "$". Before import user can define module attributes. These are system variables using zero space indentation. System variables are usually loaded from a configuration file (*.cfg) and do not need to be declared explicit. They are just known by EVE runtime and can be used in all modules. 

**Note:** System variables are immutable!

## Import region

Is used to include members from several other modules into current module: 

**syntax**
```
import 
  $user_path/relative_path/*.eve:(*); 
  $user_path/relative_path/script_name.eve:(*);
  $user_path/relative_path/script_name.eve:(member_name,...);

** member alias
alias
  name := script_name;
  name := script_name.member_name;
  ...
```

**note:** 
* $user_path is any path defined by the user
* member alias can be any member: type, class, function, method
* using :(*) will import all members in current context
* using :(member_name,...) will import specified members in current context

**user_path**

Several system variables are provided by EVE environment:

* $eve_home  :eve runtime
* $pro_home  :project home
* $eve_lib   :eve lib folder
* $pro_lib   :project lib folder

## Global region

Global region is for declarations of:

* constant  ::=  Type : identifier := value;
* variable  ::=  Type : identifier := value;
* reference ::=  Type : identifier :: value;

Global members are visible in current module with no prefix. 

**public**

Global public members must start with a dot prefix:

**example**
```
global
  con .PI := 3.14; -- global & public constant
  var  pi := 3.14; -- global & private variable
```

**note:** constant is using capital letters

## Methods

A method is a named block of code that can be executed multiple times.

* it can define input/output parameters;
* can have local defined variables;
* can have one or more results;
* is terminated with statement return;

**prototype**
```
method name(parameters) => (results)
  ** declaration region
process
  ** executable region
  ...
return;
```

**Notes:**

* parameters are optional but empty list () is required if there are no parameters,
* results are optional but symbols => and empty list () is required if there are no results.

**Method name**
A method is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The methods are doing something, therefore the best names for methods are verbs.

**Main method**
If a module is executable using "run" command, it must contain a "main" method. This method is executed first. If main method is missing then the module is a library and can be imported in other modules but can not be executed using run command.

**Parameters**
Parameters are defined in round brackets () separated by comma. Each parameter must have type and name. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

```
 parameter ::= Type : name := value ** input parameter
 parameter ::= Type @ name ** output parameter
```

1. One method can receive one or more parameters;
1. Parameters having initial values are optional;
1. We can pass arguments by position, or by name;
1. Input parameters are pass by value;
1. Output parameters are pass by reference;

**Variadic parameters**

One method can receive multiple arguments of the same type separated by comma into one parameter.

* The variadic parameter name are declared using "*" instead of ":" or "@". 
* The surplus of arguments are captured into last parameter named: "args". 
* We can use any name instead of "args" but this is the usual name.

**example**
```
method main(Array[String]() * args) => ()
  print(args);
return;
```

**Method context**

Every method has a local context. Members defined in local context are private. In this context a method can implement static attributes using "." prefix. These attributes are properties of the method and can be accessed from current module using dot notation. 

**Method results**

A method can have results defined after operator "=>" in a list: (results). The result values can be computed in method context. Results can be captured using symbol "+>" or can be ignored. Symbol "+>" is called "colector operator".


**Method call**
Methods can be used like statements. A method call can be done using method name followed by argument list, enclosed in round parentheses separated by comma. For one single argument, or no argument paratheses are optional.

```
  method_name;
  method_name argument_value;
  method_name (argument_list);
  method_name (argument_list) +> (result_arguments);
```

**Method termination**
A method end with keyword return. When method is terminated, program execution will continue with the next statement after the method call. Keyword _exit_ can terminate a method early and no error is signaled. To signal an error you must use _raise_ keyword. You can terminate a method using _quit_ but this will also terminate the main suite,

**Example:**
```
method test(Integer: a) => ()
process
  ** print is a system method
  print a; 
return;

method main(List[String]: *args) => ()
  ** number of arguments received:
  Integer: c := args.count();
process  
  ** verify condition and exit
  exit if c = 0;
  
  test c; ** method call
return;
```

## Side Effects

A method can have side-effects: 

* modify a global variable;
* open and write into a file;
* print a message or accept input from console;

**using side-effects**

Next method add numbers and has 2 side effects: 

```
** global variables
global
  test :Integer; 
  p1   :Integer; 
  p2   :Integer; 

method add_numbers():Integer 
process
  **side effects  
  test := p1 + p2 ;
  print (test);
return;

method main()
process
  p1 := 10;
  p2 := 20;
  add_numbers();
  expect result = 30;
return;
```

**using output parameters**

To avoid system and global variables you can use output parameters:

```
method add(p1,p2: Integer out @ Integer) => ()
process
  out := p1+p2;
return;

method main() => ()
  Integer: result;
process  
  ** reference argument require a variable
  add(1,2, out: result);
  print (result); ** expected value 3
  ** negative test
  add (1,2,4); ** error, "out" parameter require variable argument
return;
```

**Notes:**

* Output parameters are usually the last parameters;
* Output arguments must be specified by name;
* A method call is a statement, can not be used in expressions;
* We can not create methods, data types or classes inside a method;
* We can not create references to methods;

## Functions

A function can have parameters and produce one single result. 

```
function: name(parameters) => Type: (expression);
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
  <result> := <function_name>(param:value ...)   
```

**Parameters**

* Parameters are declared in parenthesis () after the function name, 
* Each parameter has name and type and can have one default value, 
* When a function is called each parameter receive a value that is called argument. 

**Arguments**

There is a difference between the parameter and the argument. The parameter is a local variable in the function scope while arguments are values assigned to these parameters in the function call. Arguments can be literals, constants or variables. 

**Example:**
```
** function declaration
function sum(Integer: a, b) => Integer: (a + b);
  
method main() => ()
  Integer: r;
process  
  r := sum(10,20);  -- function call
  print(r);         -- this will print 30
return;
```

## Expressions

A ternary operator is "?". Can be used with conditional expressions to return one value or other.   
**syntax**
```
  value ? (condition) : value
```

**example**
```
print ("True" ? True);
```

## λ expressions

An λ expression we can use multiple conditionals nodes separated by comma:

**syntax:**
```
  identifier := (value ? condition,...:default_value)
```

**nodes**
* each node is evaluated until one is true
* each node can return one single value
* the last node do not use a condition but ":"

**example**
```
method main() => ()
  Integer: p1, p2, x;
process
  p1 := 2;
  p2 := 1;
  ** using λ expression  
  x  := ( 0 ? p1 = 0, 0 ? p2 = 0: p1+p2);
  print x; ** expect: 3 
return;
```

**example**
```
given
  Logic:   b := False;
  Integer: v := 0;   
do
  v := (1 ? b : 2);   
  expect v = 2;  
  print v;   
done; 
```

## Dispatch

Dispatch is a form of subroutine selection by signature. It makes possible multiple subroutines with the same and different parameters. These kind of subroutines are _overloaded_. Subroutine signature include name, parameter types and result types.

**Wikipedia:** [name mangling](https://en.wikipedia.org/wiki/Name_mangling)

## Classes
Classes are composite smart data types. We use a class to create objects.

```
class: name(parameters) <: base_class
  ** definition_region
create
  ** constructor region
remove
  ** release region
return;
```

**Read more:** [Classes](classes.md)

## Test case 

A method can be organized as a workflow of multiple test-cases that can fail.

```
method main() => ()
process
  ** initialization
  case c1("description") do
    ...
    exit if (condition);
  case c2("description") do
    ...
    solve s4 if (condition);    
  case c3("description") do
    ...
    retry s1 if (condition);    
  case c4("description") do    
    ...
recover  
  ** exception region
  ...
  resume if (condition)
closure
  ** finalization region
  ...    
return;
```

New keywords:

* exit,  will terminate the method early
* solve, will continue with a forward case
* retry, will continue with a previous case

## Execution

EVE suites are executed using a virtual machine. This is capable of running one single suite at a time. You can run same suite in different sessions with different startup parameters. Each session is independent. 

**memory**
Server is in charge of allocating memory for one session before the application starts. There is no shared memory between sessions. That is a session is dedicated for a single application. After application is terminated the memory is released.
 
To start an application there are 2 methods:

1. Using the command line with parameters
2. Using console command line with commands

eve:> run path/suite_name -c file.cfg -m 2048GB

**syncron:**
```
#suite:test("module run test")

import 
  $pro_mod/module_name
   
** you can run a module with arguments
method main() => ()
process
  run module_name.main(arguments) +> (results);
return;
```

**parallel:**
```
#suite:test("module run test")

import 
  $pro_mod/module_name

method main() => ()
process
  ** execute a module in parallel
  act module_name(arguments,channel);
  act module_name(arguments,channel); 
  ** whait for all modules to finish
  rest;
  ** print the results
  print (channel);
return;
```

**using exit**

Using exit in main() will end module execution.

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

This is a way to release all locked resources and stop the main suite.

**Example:**
```
** using when prefix condition
when (condition) do
  quit;
done;

** using if postfix condition
quit if (condition);
```

**Read next**: [Control Flow](control.md)