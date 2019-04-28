## ΞVΞ Structure

EVE is scripting language. Scripts are files with extension *.eve stored on a server in project folders. The main folder contains one or more master scripts. Each represents an application entry point and can be executed in a separated session.

**Bookmarks:**

Next bookmarks will lead you to the main concepts required to understand EVE program structure.

* [Scripts](#scripts)
* [Regions](#regions)
* [Classes](#classes)
* [Methods](#methods)
* [Functions](#functions)
* [Expressions](#expressions)
* [Parameters](#parameters)
* [Dispatch](#dispatch)
* [Test cases](#test-cases)
* [Program Execution](#program-execution)

## Scripts

Scripts are source code files having extension: *.eve. script names starts with lowercase letter can contain underscore and digits but no special characters. Longer names that use several words will separate with underscore. The script name can be 64 characters long.

## Regions
Each script is divided into regions. Each region is identified by one of these keywords:

{import, define, global, class, method} 

**members**
Members belonging to a region are indented two spaces from left side. A region terminate when other region starts or indentation is changed. Regions can be repeated but can not be nested.

**syntax**
```
************************************************
**   First line of a script can be a comment  **
************************************************
** system region has zero indentation
** system region contains directives and system variables
#directive
...

** system variables
$system_variable := value/expression
$system_constant := value/expression

import
  ** import_region

## head comment
define
  ** constant declarations 

## global variables
global
  ** variable declaration

## member declarations
function: name(params) => (expression)

class: name(params) <: superclass
  ** class_definition
return;

method: name(params) => (result_list)
  ** method_definition
return;

## footer comment
```

## Declaration order
Order of regions is important but it can be interleced with other declarations. You can not use members before they are defined. Directives are usually on top follow by system declarations then import and then global variable declarations. Last we declare in random order several: {functions, methods, classes}.


## System variables
System variable start with prefix "$". System variables are defined in EVE core library. Programmers can use system variables. Before define and import keyword there is a region where user can define new system variables. System declaration region use zero zpace indentation. 

## Import region
Is used to include one or several scripts one on each line. Import region contains also _"from"_ clause. This is used to indicate what members we will use without dot qualifier. If we do not specify than script members can be accessed only with qualifier;

**syntax**
```
import 
  qualifier := $PATH/relative_path/script_name.eve 
  ...
  from qualifier use all 
  from qualifier use member_name,...
  ...

```
**location**
The compiler search scripts in local library first then in script folder then in EVE standard library then in path $EVE_PATH. Finally if file is not found the program fail to compile. We can specify the relative path before script name in the import region using "/" to separate folder names.  

**Note:** 

* Only a #library or #script can be imported not a #driver
* A #driver can be executed but can not be imported

## Define Region
This region is for declaration of global "members". 

* constant  ::=  type : Identifier := value;
* variable  ::=  type : identifier := value;
* reference ::=  type @ identifier := value;

Global members are visible in current script and Scripts that imports it. 

## Methods

A method is a named block of code.

* it can define input/output parameters;
* can have local defined variables;
* is terminated with statement return;

**prototype**
```
method: name(parameters) => (results)
  ** declaration region
process
  ** executable region
  ...
return;
```

**Notes:**
* symbol ":" after method is mandatory, like for any other declaration, 
* parameters are optional but empty list () is required if there are no parameters,
* results are optional but => () is required if there are no results.

**Method name**
A method is extending the language with domain specific algorithms. It must have suggestive names so that other developers can understand its purpose. The methods are doing something, therefore the best names for methods are verbs.

**Main method**
If a script is executable using "run" command, it must contain a "main" method. This method is executed first. If main method is missing then the script is a library and can be imported in other scripts but can not be executed using run command.

**Parameters**
Parameters are defined in round brackets () separated by comma. Each parameter must have type and name. Using parameters require several conventions to resolve many requirements. General syntax for parameter name is:

```
 param_name ::= type : name := value ** input parameter
 param_name ::= type @ name ** output parameter
```

1. One method can receive one or more parameters;
1. Parameters having initial values are optional;
1. We can pass arguments by position, or by name;
1. Input parameters are pass by value;
1. Output parameters are pass by reference;

**Variadic parameters**

One method can receive multiple arguments of the same type separated by comma into one parameter.

* The variadic parameter name are declared using "*" instead of ":". 
* The surplus of arguments are captured into last parameter named: "args". 
* We can use any name instead of "args" but this is the usual name.

**example**
```
method: main(Array[String]() * args) => ()
  print(args)
return;
```

**Method context**

Every method has a local context. Members defined in local context belong to the method. In this context a method can implement attributes using "." prefix. Attributes are properties of the method and can be accessed before and after method execution. 

**Method results**

A method can have results defined after operator "=>" in a list: (results). The result values can be computed in method context. Results can be captured or ignored by a method call.


**Method call**
Methods can be used like statements. A method call can be done using method name followed by argument list, enclosed in round parentheses separated by comma. For one single argument, or no argument paratheses are optional.

```
  method_name;
  method_name argument_value;
  method_name (argument_list);
  method_name (argument_list) +> (result_arguments);
```

## Method termination
A method end with keyword return. When method is terminated, program execution will continue with the next statement after the method call. Keywords "exit", "fail" or "panic" can terminate a method early. 

**Example:**
```
method: test(Integer: a) => ()
process
  ** print is a system method
  print a 
return;

method: main(List[String]: *args) => ()
  ** number of arguments received:
  Integer: c := args.count()
process  
  ** verify condition and exit
  abort if c = 0
  
  test c ** method call
return;
```

## Side Effects

We have mention side-effects: that can be one of:

* modify a global variable;
* open and write into a file;
* print a message or accept input from console;

**using side-effects**

Next method add_numbers has 2 side effects: 

```
** global variables

global
  Integer: test 
  Integer: p1, p2
  
method: add_numbers() => ()
process
  **side effects  
  test := p1 + p2 
  print (test)
return;

method: main() => ()
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
method: add(integer: p1,p2, Integer @ out) => ()
process
  out := p1+p2
return;

method: main() => ()
  Integer @ result
process  
  ** reference argument require a variable
  add(1,2, out :: result)
  print (result) ** expected value 3
  ** negative test
  add (1,2,4) ** error, "out" parameter require variable argument
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
function: name(parameters) => type: (expression)
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

* Parameters are declared in parenthesis () after the function name, 
* Each parameter has name and type and can have one default value, 
* When a function is called each parameter receive a value that is called argument. 

**Arguments**

There is a difference between the parameter and the argument. The parameter is a local variable in the function scope while arguments are values assigned to these parameters in the function call. Arguments can be literals, constants or variables. 

**Example:**
```
** function declaration
function: sum(Integer: a, b) => Integer:(a + b)
  
method: main() => ()
  Integer: r
process  
  r := sum(10,20)  ** function call
  print(r)         ** this will print 30
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
print ("True" ? True)
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
method: main() => ()
  Integer: p1, p2, x
process
  p1 := 2
  p2 := 1
  ** using λ expression  
  x  := ( 0 ? p1 = 0, 0 ? p2 = 0: p1+p2)
  print x ** expect: 3 
return;
```

**example**
```
given
  Logic:   b := False
  Integer: v := 0   
do
  v := (1 ? b : 2)   
  print v ** expect 2  
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
discard
  ** release region
return;
```

**Read more:** [Classes](classes.md)

## Test cases 

A method can be organized as a workflow of multiple use-cases that can fail.

```
method main() => ()
process
  ** initialization
  case: c1("description") do
    ...
    abort if (condition)
  case: c2("description") do
    ...
    solve s4 if (condition)    
  case: c3("description") do
    ...
    retry s1 if (condition)    
  case: c4("description") do    
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

* abort, will terminate the method early
* solve, will continue with a forward case
* retry, will continue with a previous case

## Program Execution

EVE program is hosted using a virtual machine. This is capable of running multiple sessions in parallel. Each session represents one independent application. You can run same application in different sessions. The sessions are independent and encapsulated. That means sessions can not communicate with each other.

Server is in charge of allocating memory for one session before the application starts. There is no shared memory. That is a session is dedicated for a single application. After application is terminated the memory is released.

This is the reason EVE do not use parallel programming. The server is handling all the parallel work. EVE applications are single threaded applications. This also simplify the interpreter. There is no possibility to have race conditions or unexpected results.

To execute a program or application there are 2 methods:

1. Using the command line with parameters
2. Using console command line with commands

eve:> run script_name


**notes**
* You can executed script methods from another script
* Only scripts that have main() method can be executed 
* You can use _alias_ to create an alias for script name before you run it 
* You can use _from_  to import public members from a library and avoid dot notation

**pattern example:**
```
#driver "test"

import 
   my_lib    := $pro_lib/my_lib.eve
   my_script := $pro_mod/my_script   
   
   from: my_lib use all

** you can run a script with arguments
method main() => ()
process
  run my_script(arguments) +> (results)
return;
```

**Read next**: [Control Flow](control.md)