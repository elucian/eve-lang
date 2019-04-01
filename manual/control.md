## Control Flow

EVE has a versatile set of control statements:

* [given](#given)
* [when](#when)
* [begin](#begin)
* [cycle](#cycle)
* [while](#while)
* [scan](#scan)
* [trial](#trial)

## Given

Given, establish a new declaration region for a block statement. 

**syntax**
```
given
  -- local declarations
begin:
  -- local scope 
ready;
```

**Notes:** 
* given is optional region for <block>
* block ∈ { when, cycle, while, scan, trial }
* one blocks is ending with keywords: { ready \| repeat}

## When

When, can be used in conjunction with {do, else} keywords to create a dual path fork based on logic expressions;


**patterns**

1.single path selector
```
when <expression>:
  -- single path
ready;
```
  
2.dual path selector
```  
when <expression>:
   -- true path
else:
   -- false path
ready;
```
  
3.nested selector 
```  
when <expression>:
  when <expression>:
   -- first path
  ready;
ready;
```

## Quest

The quest is a multi-path value based selector. It is used in conjunction with { "if" and "cover" }

**syntax:**

```
given 
  val := <expression>;
quest:
  if val = <value1>:
    -- first path
  if val = <value2>:
    -- second path
cover:
  -- default path
quest;
```

**Using list and range**
It is possible to use more then one value using a list, range or collection. 

**Example:**
```
aspect test(Integer p:=0): 
  message ∈ String;
  given 
    Integer v := p + 4;
  quest:
    if v ∈ (1,2,3):
      message := "first match";
      ...
    if v ∈ [1..8]:
      message := "second match";
  cover:
      message := "no match";
  quest;
  print message; 
over;
```

**notes:**

* Each condition is evaluated in order from top down one time;
* When no condition is satisfied the _"other"_ branch is executed.
* To evaluate next condition we can use 3 dots: "...", that means "next".


### Cycle

Create repetitive statement block.

```
given
  -- control variables
cycle:
  -- modify control variable
  ...
  stop if condition;
repeat;  
```

**example**

```
given
  Integer a := 10;
cycle:
  a -= 1;
  -- conditional repetition
  loop if (a % 2 = 0);  
  write a;  
  -- conditional termination
  write ','; 
  stop if (a < 0);
repeat;
```

**Notes:** 

* If _stop_ condition is missing the cycle is infinite;
* The cycle can be controlled using conditional if;

### Nested cycles

Nested cycles can be labeled:

**pattern:** 

```
-- label 2 nested cycles 
cycle one:
  -- outer cycle
  cycle two:
    -- inner cycle
    redo one if condition;
    ...    
    redo two if condition;
    ...
    stop one if condition;    
  repeat;  
repeat if condition;  
```

**example**

```
create x   := 9;
create a,r := 0;

cycle:
  r := x % 2;
  a := (0 if r = 0, 1 if r = 0, 2);
  write "{1}:{2}" <+ (x,a);
  x -= 1;
  write ',' if x < 5;
repeat if (x ≥ 5);  
print; --> 9:1, 8:0, 7:1, 6:0, 5:1
```

## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
given 
  <local_variable>
while <condition>:
  <statement>
  loop if <condition>;
  ...
  stop if <condition>;
  ...
repeat;
```
**example**

```
--example of collection iteration
aspect main() go
  given 
    test := ["a","b","c","d","e"];
    i := 0 ∈ Natural;
  while i < test.length:
    element := my_list[i];
    -- shortcut 
    when element ≥ "c":
       write(element);
       write(',') if element ≠ "e"; 
    ready;       
  repeat;
over;
```
> "c","d","e"

## Scan

Scan a "range", that is a _subset_ from a continuous _type_ using syntax: `[n..m]`.  

```
[0..10]  -- {0,1,2,3,4,5,6,7,8,9,10}
```
Note: 

* A range can be only in ascending order. 
* Default range is native integer.
* Range can use negative numbers.

**Pattern:**
``` 
given
  min := <constant>;
  max := <constant>;  
  var ∈ Z[min..max];
scan var:
  -- block statements;
  ...
repeat;
```

**Notes:**    
* The "given" keyword create a local scope. 
* Control variable is automatic incremented;
* Control variable must be declared in local scope;

Example of forward iteration:
```
given
  i := 0 ∈ Z[0..10] 
scan i:
  -- force next iteration
  when (i % 2 ≡ 0):
    next;
  else
    -- write only odd numbers
    write(i);  
    write(',') if i < 10;  
  ready;
repeat;
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
  -- declaration
trial:
  -- initialization
  case <name_1>:
    abort if <condition>;
  case <name_2>: 
    retry <name_x> if <condition>
  case <name_3>:
    solve <name_x> if <condition>     
  ...    
error <code1>:
  <patch_statement>
error <code2>:
  <patch_statement>  
...  
other
  <other_errors>  
final
  <finalization>
ready;
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

**directive**

* #trace:on|off  -- create trace records for ...errors
* #echo:on|off   -- each case print out to console when is executed

**Read next:** [Data Types](data-types.md)