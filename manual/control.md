## Control Flow

EVE has only 7 control statements: 

* [with](#with)
* [when](#when)
* [case](#case)
* [quest](#quest)
* [given](#given)
* [while](#while)
* [scan](#scan)

**Notes:** 

* keyword _given_ start a local scope for any block statement
* one {* blocks *} is ending with keywords: { done \| next \| repeat}

## With

Establish a declaration region and scope qualifier suppression block. 

**syntax**
```
with qualifier := long_qualifier do
  ** local statements
  method_name();  ! instead of: qualifier.method_name()
  alter var := function_name(); ! instead of qualifier.function_name()
  ...
done;
```

long_qualifier ::= file_name.Class_Name | file_name.record_name

## when

This keyword in conjunction with {do, else} declare a multi-path block selector;

**patterns**

1.single path selector
```
when expression do
  ** single path
  ...
done;
```
  
2.dual path selector
```  
when expression do
  ** true path
  ...
else
  ** false path
  ...
done;
```
  
3.nested selector 
```  
when expression do
  ...
  when expression do
   ** nested path
   ...
  done;
done;
```

## Case

It is a multi-path selector based on a condition:

case condition do
  ** first case  
case condition do
  ** second case
case condition do
  ** third case
else
  ** default case  
done;

## Quest

Is is a multi-path value based selector similar to switch:

```
quest value:
  match c do
    ...
  match c1,c2... do
    ...
other
  ...
done;
```

**Note:**
* it can match only constants or enumeration of constants
* it can not match an expression or a domain 
* only one branch can be executed
* other is executed when no match was found
* quest is stopping on first match


## Given

Is used to define a local scope for a simple block or repetitive block of code.

**Pattern:**
``` 
given 
  @type_name: var_name; ! local variable  
  ...
do
  ** block statements;
  ...
  abort if condition;  
done;
```

## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
while condition do
  ** shortcut iteration
  skip if condition;
  ...
  ** early interruption
  stop if condition;
  ...
else
  ** alternative path  
  ...
repeat;
```

**example**

```
** example of collection iteration
given
  @list:test := ["a","b","c","d","e"];
  @integer: i := 0;
  @symbol: e;
while i < test.length() do
  alter e := my_list[i];
  alter i += 1;
  when e  >= "c" do
    write e;
    write ',' if e ≠ "e";
  done;
else
  print ('i = ' + i);  
repeat;
```
> "c","d","e"
> i = 5

## Scan

This block use one or more control variables to visit elements in a collection or domain.

**Pattern:**
``` 
given 
  @integer: var;
scan (min..max) +> var do
  ** block statements;
  ...
  ** next iteration
  skip if condition;
  ...  
  ** early interruption
  stop if condition;
  ...
next;
```

**Notes:**    

* Control variable is auto-incremented using next;
* Control variable must be declared in local scope;

Example of range iteration:
```
given 
  @integer: i;
scan (1..10:2) +> i do
  ** write only odd numbers
  write i;
  write ',' if (i < 10);
next;
```
> 1,3,5,7,9

**Read next:** [Basic Types](basic.md)