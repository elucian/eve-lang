## Control Flow

EVE has a versatile set of control statements:

* [given](#given)
* [when](#when)
* [quest](#quest)
* [cycle](#cycle)
* [while](#while)
* [scan](#scan)
* [trial](#trial)

## Given

Given, establish a new declaration region for a block statement. 

**syntax**
```
given
  ** local declarations
begin
  ** local scope 
ready
```

**Notes:** 

* given is optional region for <block>
* block is { when, quest, cycle, while, scan, trial }
* one blocks is ending with keywords: { ready \| repeat}

## When

When, can be used in conjunction with {do, else} keywords to create a dual path fork based on logic expressions;


**patterns**

1.single path selector
```
when (expression) do
  ** single path
ready
```
  
2.dual path selector
```  
when (expression) do
   ** true path
else
   ** false path
ready
```
  
3.nested selector 
```  
when (expression) do
  when (expression) do
   ** nested path
  ready
ready
```

4.ladder

```  
when (expression)    do
   ** first path
else if (expression) do
   ** second path
else if (expression) do
   ** third path
else if (expression) do
   ** last path
ready
```


## Quest

The quest is a multi-path value based selector. It is used in conjunction with { "if" and "cover" }

**syntax:**

```
given 
  value_typ: val := expression
quest val
  if (val = constant1) do
    ** first path
    ...
  if (val = constant2) do
    ** second path
    ...
  if (val ? val_list)  do
    ** third path
cover
  ** default path
ready
```

**Using list and range**
It is possible to use more then one value using a list, range or collection. 

**Example:**
```
method: test(Integer: p:=0) 
  String: message := ""
process 
  given 
    Integer: v := p + 4
  quest v
    if v ? (1,2,3) do
      message := "first match"
    if v ? [1..8]  do
      message := "second match"
    if v ? [5..10] do
      message := "third match"      
  cover
    ** other cases
    message := "no match"
  ready
  print (message) 
return
```

**notes:**

* The "all" keyword is optional 
* Each condition is evaluated in order from top down one time;
* When no condition is satisfied the _"other"_ branch is executed.
* To evaluate next condition we can use 3 dots: "...", that means "next".


### Cycle

Create repetitive statement block.


**pattern**
```
given
  ** control variables
cycle
  ** repeating block
  ...
repeat if (condition)
```

**interruptions**
```
given
  ** control variables
cycle
  ...
  skip if (condition)
  ...
  stop if (condition)
  ...
repeat
```

**example**

```
given
  Integer: a := 10
cycle
  a -= 1
  ** conditional repetition
  skip if (a % 2 = 0)  
  write a  
  ** conditional termination
  write ',' 
  stop if (a < 0)
repeat
```

**Notes:** 

* If _stop_ condition is missing the cycle is infinite;
* The cycle can be controlled using conditional if;

### Nested cycles

Nested cycles can be labeled

**pattern:** 

```
** label 2 nested cycles 
cycle: outer
  ** outer cycle
  cycle: inner
    ** skip both cycles
    skip outer if (condition)
    ...    
    ** stop both cycles
    stop outer if (condition)    
  repeat  
repeat  
```

**example**

```
given
   Integer: x   := 9
   Integer: a,r := 0
cycle
  r := x % 2
  a := (0: r = 0, 1)
  write "{1}:{2}" <+ (x,a)
  x -= 1
  write ','
repeat if (x < 5)

print ** 9:1, 8:0, 7:1, 6:0, 5:1,
```

## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
given 
  ** local_variables
while (condition) do
  ** statements
  skip if (condition)
  ...
  stop if (condition)
  ...
repeat
```
**example**

```
** example of collection iteration
method: main()
  given 
    Array:test := ["a","b","c","d","e"]
    Integer: i := 0
  while (i < test.length) do
    element := my_list[i]
    i += 1
    ** shortcut 
    skip if (element < "c")
    write(element)
    write(',') if (element ≠ "e") 
  repeat
return
```
> "c","d","e"

## Scan

Scan a "range", that is a _subset_ from a continuous _type_ using syntax: `[n..m]`.  

```
[0..10]  ** {0,1,2,3,4,5,6,7,8,9,10}
```
Note: 

* A range can be only in ascending order. 
* Default range is native integer.
* Range can use negative numbers.

**Pattern:**
``` 
given
  Integer: min := constant
  Integer: max := constant  
  Integer: var ;
scan var <+ Z[min..max] do
  ** block statements;
  ...
next
```

**Notes:**    
* Control variable is automatic incremented;
* Control variable must be declared in local scope;

Example of forward iteration:
```
given
  Integer: i := 0 
scan i <- Z[0..10] do
  ** force next iteration
  when (i % 2 = 0) do
    skip
  else
    ** write only odd numbers
    write(i)  
    write(',') if (i < 10)  
  ready
next
```
> 1,3,5,7,9

**Notes:**
* scan can be shortcut using next;
* scan can be terminated early using stop;

## Trial

The "trial" statement execute a process that can fail for some reason.

**Keywords:**

| word  | description
|-------|-----------------------------
| trial | start and end trial block
| case  | open a case
| retry | re-open a previous case
| solve | continue with a forward case
| error | catch an error
| other | catch other errors
| abort | abort the entire trial
| resume| resume trial with next case

```
given
  ** declaration
trial
  ** initialization
  case: name_1 do
    abort if (condition)
  case: name_2 do
    retry name_1 if (condition)
  case: name_3 do
    solve name_4 if (condition)
  ...    
error: code1
  patch_statement
error: code2
  patch_statement  
...  
other
  other_errors  
after
  finalization
ready
```

**error**

Error regions are "exception handlers". Each can resolve one single error identified by code.

**other**

The "other" section you can use a control statement for a range of errors. 

**after**

This region contains resource closing statements:

**usability**

* Trial block can be used to create multi-case processes. 
* Trial block can be used to log informations about each case. 

## EVE Exceptions

Exception is interrupting the current logical flow and jump to the recover region in current section or parent section. In EVE all exceptions are considered errors.

The exception is a variable of type record that is created when exception is raised and is available in the recover block. System $error variable contains several members that are fill-in by the EVE program when exception is created: 
```
** system global exception type
define
   type .Exception <: Record (
                         Integer: code, 
                         String:  message, 
                         String:  section_name, 
                         String:  module_name, 
                         String:  line_number  
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
raise (code,"message") if (condition)
```

## Quick exception
Using keyword _"fail"_ user can quick create an exception that has no message or continue program using _"pass"_. Fail is used most frequent in combination with conditional statement "when" or "if". 

```
** quick exception
when (condition) do
  fail
else
  pass
ready

** conditional exception
fail if (condition)
```

## Exception handling

**recover:** region define an "exception handling region" for a method.

In this region developer can use control statements like "switch","case" to analyze the $error. Developer can decide to stop the program, print a message and resume the program using _resume_ keyword.

**Example:** 

```
method: main()
  Real: a 
process  
  a := 1 ÷ 0
recover
  print $error.message
return
```

```
Error: Numeric division by zero.
```

## Panic

Most exceptions are recoverable except the exception created by panic statement.

**Example:**
```
panic if (condition)
```

## Assert

The assert statement is very simple. It check a condition and raise an assert error if condition is false. Does not produce any error message but: "Assert error in line x".
```
  assert (condition)
```

## Expect
The expect statement is similar to assert. It verify an expression and  it produce "Unexpected error."

```
  expect (condition)
```

**directive**

* #trace:on|off  ** create trace records for ...errors
* #echo:on|off   ** each case print out to console when is executed

**Read next:** [Data Types](data-types.md)