## Control Flow

EVE has only 4 control statements: 

* [do](#do)
* [when](#when)
* [quest](#quest)
* [while](#while)
* [scan](#scan)

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

## when

This keyword in conjunction with {do, else} declare a multi-path block selector;


**patterns**

1.single path selector
```
given
  ** local variables
when (expression) do
  ** single path
done;
```
  
2.dual path selector
```  
when (expression) do
   ** true path
else
   ** false path
done;
```
  
3.nested selector 
```  
when (expression) do
  when (expression) do
   ** nested path
  done;
done;
```

## Quest

The quest is a multi-path value based selector. It is used in conjunction with { "do", "other" }

**syntax:**

```
given 
  value_typ: val := expression
quest val
  ?:constant1 do
    ** first path
  ?:constant2 do
    ** second path
  ?:constant3 do
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
  quest v
    ?:(1,2,3) do
      message := "first match"
    ?:[1..8]  do
      message := "second match"
    ?:[5..10] do
      message := "third match"      
  other
    ** other cases
    message := "no match"
  done;
  print (message); 
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
  ** forced iteration
  skip if (condition)
  ** eary intreruption
  stop if (condition)
else
  ** alternative path  
redo;
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
  done;
return;
```
> "c","d","e"

## Scan

Scan block use a control variable to visit all elements in a range or collection.

**Pattern:**
``` 
given 
  Integer:var := 0  ** initial value
scan [min..max] +> var do
  ** block statements;
  skip if (condition)
  ** eary intreruption
  stop if (condition)
  ...
next;
```

**Notes:**    
* Control variable is manual incremented;
* Control variable must be declared in local scope;

Example of range iteration:
```
given
  Integer: i := 0
scan [0..10] +> i do
  if (i % 2 <> 0) do
    ** write only odd numbers
    write(i)  
    write(',') if (i < 10)  
  done;
redo;
```
> 1,3,5,7,9

**Read next:** [Data Types](data-types.md)