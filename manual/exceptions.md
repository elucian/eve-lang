## EVE Exceptions

Exception is interrupting the current logical flow and jump to the recover region in current section or parent section. In EVE all exceptions are considered errors.

The exception is a variable of type record that is created when exception is raised and is available in the recover block. System $error variable contains several members that are fill-in by the EVE program when exception is created: 
```
** system global exception type
define
   type: .Exception <: Record[ 
           Integer: code 
          ,String : message 
          ,String : section_name 
          ,String : script_name 
          ,String : line_number  
         ]
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

## Quick exception
Using keyword _"fail"_ user can quickly create an exception that has no message or continue program using _"pass"_. Fail is used most frequent in combination with conditional statement "when" or "if". Fail has _code_ = 1 and no message.

```
** quick exception
when (condition) do
  fail
else
  pass
done;

** conditional exception
fail if (condition)
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
  ** continuation after error recovery    
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
  expect (condition)
```


**Read next:** [Data Processing](processing.md)