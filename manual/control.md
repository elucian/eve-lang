## Control Flow

EVE has only 4 control statements: 

* [do](#do)
* [if](#if)
* [quest](#quest)
* [while](#while)

## do

Given, establish a new declaration region for a block statement. 

**syntax**
```
given
  ** local declarations
do
  ** local statements
done;
```

**Notes:** 

* keyword _given_ start a local scope for any block statement
* one blocks is ending with keywords: { ready \| repeat \| next}

## if do

This keyword in conjunction with {do, else} declare a multi-path block selector;


**patterns**

1.single path selector
```
given
  ** local variables
if (expression) do
  ** single path
done;
```
  
2.dual path selector
```  
if (expression) do
   ** true path
else
   ** false path
done;
```
  
3.nested selector 
```  
if (expression) do
  if (expression) do
   ** nested path
  done;
done;
```

## Quest

The quest is a multi-path value based selector. It is used in conjunction with { "if" and "other" }

**syntax:**

```
given 
  value_typ: val := expression
quest
  when (val = constant1) do
    ** first path
    ...
  when (val = constant2) do
    ** second path
    ...
  when (val <: value_list) do
    ** third path
other
  ** default path
done;
```

**Using list and range**
It is possible to use more then one value using a list, range or collection. 

**Example:**
```
method test(Integer: p:=0) 
  String: message := ""
process 
  given 
    Integer: v := p + 4
  quest
    when v in (1,2,3) do
      message := "first match"
    when v in [1..8]  do
      message := "second match"
    when v in [5..10] do
      message := "third match"      
  other
    ** other cases
    message := "no match"
  done;
  print (message) 
return;
```

**notes:**

* Each condition is evaluated in order from top down one time;
* When no condition is satisfied the _"other"_ branch is executed.
* To evaluate next condition we can use 3 dots: "...", that means "next".


## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
given 
  ** local_variables
while (condition) do
  ** statements
else
  ** alternative path  
done;
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
    if (element >= "c") do
       write(element)
       write(',') if (element ≠ "e") 
    done;   
  repeat;
return;
```
> "c","d","e"

** range **


**Pattern:**
``` 
given 
  Integer:var := 0  ** initial value
  Integer:max := 10 ** max value
while var <= max do
  ** block statements;
  var += 1;
repeat;
```

**Notes:**    
* Control variable is manual incremented;
* Control variable must be declared in local scope;

Example of range iteration:
```
given
  Integer: i := 0
while i < 10 do
  if (i % 2 <> 0) do
    ** write only odd numbers
    write(i)  
    write(',') if (i < 10)  
  done;
repeat;
```
> 1,3,5,7,9

**Read next:** [Data Types](data-types.md)