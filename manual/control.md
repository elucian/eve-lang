## Control Flow

EVE has only 5 control statements: 

* [with](#with)
* [when](#when)
* [while](#while)
* [given](#given)

**Notes:** 

* keyword _given_ start a local scope for any block statement
* one {* blocks *} is ending with keywords: { done \| next \| repeat}

## With

Establish a declaration region and scope qualifier suppression block. 

**syntax**
```
with qualifier := long_qualifier do
  ** local statements
  method_name();  ** instead of: qualifier.method_name()
  var := function_name(); ** instead of qualifier.function_name()
  ...
done;
```

long_qualifier ::= file_name.Class_Name | file_name.record_name

## when

This keyword in conjunction with {do, else} declare a multi-path block selector;

**patterns**

1.single path selector
```
when (expression) do
  ** single path
  ...
done;
```
  
2.dual path selector
```  
when (expression) do
  ** true path
  ...
else
  ** false path
  ...
done;
```
  
3.nested selector 
```  
when (expression) do
  ...
  when (expression) do
   ** nested path
   ...
  done;
done;
```

4.ladder selector

```  
when (expression)    do
  ...
else if (expression) do
  ...
else if (expression) do
  ... 
else
  ...
done;
```

## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
while (condition) do
  ** forced iteration
  skip if (condition);
  ** early interruption
  stop if (condition);
else
  ** alternative path  
repeat;
```
**example**

```
** example of collection iteration
method main:
  @list:test := ["a","b","c","d","e"];
  @integer: i := 0;
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
given @integer: var <: (min..max) do
  ** block statements;
  ...
  ** next iteration
  skip if (condition);
  ** early interruption
  stop if (condition);
  ...
next;
```

**Notes:**    
* Control variable is manual incremented;
* Control variable must be declared in local scope;

Example of range iteration:
```
given @integer: i <: (1..10:2) do
  ** write only odd numbers
  write i;
  write ',' if (i < 10);
next;
```
> 1,3,5,7,9

**Read next:** [Basic Types](basic.md)