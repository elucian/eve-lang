## Control Flow

EVE has only 7 control statements: 

* [given](#given)
* [with](#with)
* [when](#when)
* [case](#case)
* [check](#check)
* [cycle](#while)
* [while](#while)
* [for](#for-do)

**Notes:** 

* keyword _given_ start a local scope for any block statement
* one block is ending with keywords: { done \| next \| repeat}

## Given

Is used to define a local scope for any block of code.

**Pattern:**
``` 
given 
  Type_name: var_name; //  local variable  
  ...
do
  ** block statements;
  ...
  abort if condition;  
done;
```

## With

Keyword "with" establish local region and scope qualifier suppression block. 

**syntax**
```
with qualifier do
  ** local statements
  routine_name();  //  instead of: qualifier.routine_name()
  alter var := function_name(); //  instead of qualifier.function_name()
  ...
done;
```

qualifier ::=  ModuleName | ClassName | RecordName

## When

Keyword "when" in conjunction with {do and else} declare a multi-path block selector;

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
  ** direct path
  ...
  when expression do
   ** nested path
   ...
  done;
done;
```

## Case

It is a multi-path selector based on multiple conditions:

case condition do
  ** first case  
case condition do
  ** second case
case condition do
  ** third case
else
  ** default case  
done;

## Check

Using "check" and "match" you can create a multi-path selector.

```
check value:
  match c do
    ...
  match c1,c2... do
    ...
else
  ...
done;
```

**Note:**
* it can match only constants,
* it can match a list of constants,
* it can not match an expressions,
* it can not match domain of values,
* execution stop on first match or else.

## Cycle

Execute a block of code until is interrupted using "stop"

**Syntax:**
```
cycle
  ** shortcut iteration
  skip if condition;
  ...
  ** early interruption
  stop if condition;
  ...
repeat;
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
routine test(): 
  List: this = ["a","b","c","d","e"];  
process
  given
    Integer: i := 0;
    Symbol: e;
  while i < this.length() do
    share  e := this[i];
    alter  i := i + 1;
    when e  >= "c" do
      print e & (',' if e <> "e")
    done;
  else
    print ('i = ' + i);  
  repeat;
return;  
```

**output**
```
"c","d","e"
i = 5
```

## For do

This block use one or more control variables to visit elements in a collection or domain.

**Pattern:**
``` 
given 
  Integer: var;
for var in (min..max) do
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
  Integer: i;
for i in (1..10:2) do
  ** write only odd numbers
  write i;
  write ',' if (i < 10);
next;
print;
```
> 1,3,5,7,9

**Read next:** [Classes](classes.md)