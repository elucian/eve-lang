## EVE Exceptions

Exception is interrupting the current logical flow and jump to the recover region in current section or parent section. In EVE all exceptions are considered errors.

The exception is a variable of type record that is created when exception is raised and is available in the recover block. System $error variable contains several members that are fill-in by the EVE program when exception is created: 
```
$error <: Record of (
   code: Integer, 
   message: String, 
   section_name: String, 
   module_name:  String, 
   line_number:  String
);
```
## Run-time errors
Exceptions can be system exceptions or user defined exceptions.

**system exception** 
System exceptions are predefined and created during the program execution 
when there is a _"run-time error"_ and program can not continue.

## User defined exceptions

There are two alternative statements to create user defined exceptions.

```
-- raise exception
when <condition> then
  raise(<code>,"message");
ready;

-- conditional 
raise(<code>,"message") if <condition>;
```

## Quick exception
Using keyword _"fail"_ user can quick create an exception that has no message or continue program using _"pass"_. Fail is used most frequent in combination with conditional statement "when" or "if". 

```
-- quick exception
when <condition> then 
  fail;
when:
  pass;
ready;

-- conditional exception
fail if <condition>;
```

## Exception handling

**recover:** region define an "exception handling region" for a aspect.

In this region developer can use control statements like "switch","case" to analyze the $error. Developer can decide to stop the program, print a message and resume the program using _resume_ keyword.

**Example:** 

```
aspect main:
  a ∈ Real; 
  a := 1/0;  
recover
  print($error.message);
over;
```

```
Error: Numeric division by zero.
```

## Unrecoverable exception
Most exceptions are recoverable except the exception created by panic statement.

**Example:**
```
when <condition> then
  panic;
ready;
```

**Todo:** System exception codes are not yet defined. In the example code 1000 is hypothetical;

**Read next:** [Data Processing](processing.md)