## EVE Exceptions

Exception is interrupting the current logical flow and jump to the recover region in current section or parent section. In EVE all exceptions are considered errors.

The exception is a variable of type record that is created when exception is raised and is available in the recover block. System $error variable contains several members that are fill-in by the EVE program when exception is created: 
```
** system global exception type
define
   type: .Exception <: Record( 
           Integer: code 
          ,String : message 
          ,String : section_name 
          ,String : script_name 
          ,String : line_number  
         )
** global variable for holding current error
global
   Exception: $error
```
## Run-time errors
Exceptions can be system exceptions or user defined exceptions.

**system exception** 
System exceptions are predefined and created during the program execution 
when there is a _"run-time error"_ and program can not continue.

## User defined exceptions

There are two alternative statements to create user defined exceptions.

```
** raise exception
when condition do
  raise (code,"message")
done;

** conditional 
raise (code,"message") if (condition)
```

## Exception handling

Recover: region define an "exception handling region" for a method.

In this region developer can use control statements like "switch","case" to analyze the $error. Developer can decide to stop the program, print a message and resume the program using _resume_ keyword.

**Example:** 

```
method: main() => ()
  Real: a
process  
  a := 1 / 0
recover
  print ($error.message)
closure
  ** close process
return;
```

```
Error: Numeric division by zero.
```

## Halt

This is a way to release all locked resources and stop the program.

**Example:**
```
when (condition) do
  halt
done;
```

## Expect

The expect statement is very simple. It check a condition and raise an error if condition is false. Does not produce any error message but: "Unexpected error in line: N".

```
  ** precondition
  expect (condition)
  
  ** equivalent
  raise ("Unexpected error") if (condition)
```

**note:**
* can be used as pre-condition
* can be used as post-condition
* unexpect error has code = 0

**Read next:** [Data Processing](processing.md)