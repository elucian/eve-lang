## Control Flow

EVE has only 4 control statements: 

* [with](#with)
* [when](#when)
* [quest](#quest)
* [while](#while)
* [scan](#scan)

## With

Establish a declaration region and qualifier supression block. 

**syntax**
```
given
  ** local declarations
with qualifier := long_qualifier do
  ** local statements
  method_name();  -- instead of: qualifier.method_name()
  var := function_name(); -- instead of qualifier.function_name()
done;
```

**Notes:** 

* keyword _given_ start a local scope for any block statement
* one blocks is ending with keywords: { done \| next}

## when

This keyword in conjunction with {do, else} declare a multi-path block selector;


**patterns**

1.single path selector
```
given
  ** local context
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

The quest is a multi-path value based selector. 
It is used in conjunction with { "do", "other", "done"}

**syntax:**

```
given 
  value_typ: val := expression
quest val
  match constant1 do
    ** first path
  match constant2 do
    ** second path
  match constant3 do
    ** third path
none
  ** default path
done;
```

**Using list and range**
It is possible to use more then one value using a list, range or collection. 

**Example:**
```
method test(Integer: p:=0) => ()
  String: message := "";
  Integer: v := p + 4;
process 
  quest v
    match (1,2,3) do
      message := "first match";
    match [1..8]  do
      message := "second match";
    match [5..10] do
      message := "third match";    
  none
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
  ** local context
while (condition) do
  ** forced iteration
  skip if (condition);
  ** eary intreruption
  stop if (condition);
else
  ** alternative path  
repeat;
```
**example**

```
** example of collection iteration
method main() => ()
  Array:test := ["a","b","c","d","e"];
  Integer: i := 0;
process
  while (i < test.length) do
    element := my_list[i];
    i += 1;
    ** shortcut 
    if (element >= "c") do
       write(element);
       write(',') if (element ≠ "e");
    done;
  repeat;
return;
```
> "c","d","e"

## Scan

Scan block use a control variable to visit all elements in a range or collection.

**Pattern:**
``` 
given 
  Integer:var := 0;  ** initial value
scan [min..max] +> var do
  ** block statements;
  skip if (condition);
  ** eary interruption
  stop if (condition);
  ...
next;
```

**Notes:**    
* Control variable is manual incremented;
* Control variable must be declared in local scope;

Example of range iteration:
```
given
  Integer: i := 0;
scan [0..10] +> i do
  when (i % 2 <> 0) do
    ** write only odd numbers
    write(i);
    write(',') if (i < 10);
  done;
next;
```
> 1,3,5,7,9

**Read next:** [Basic Types](basic.md)