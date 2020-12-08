## Control Flow

EVE has 6 control statements: 

* [task](#task)
* [if](#if)
* [swith](#swith)
* [while](#while)
* [for](#for-do)

**Notes:** 

* keyword _given_ start a local scope for any block statement
* one block is ending with keywords: { done \| next \| repeat}

## task

Is used to define a local scope for any block of code.

**Pattern:**
``` 
task 
  Type_name: var_name; //  local variable  
  ...
begin
  ** block statements;
  ...
  if condition then abort;
end task;
```

qualifier ::=  ModuleName | ClassName | RecordName

## if

Keyword "when" in conjunction with {then and else} declare a multi-path block selector;

**patterns**

1.single path selector
```
if expression begin
  ** single path
  ...
end if;
```
  
2.dual path selector
```  
if expression begin
  ** true path
  ...
else
  ** false path
  ...
end if;
```
  
3.nested selector 
```  
if expression begin
  ** direct path
  ...
  if expression begin
   ** nested path
   ...
  end if;
end if;
```

## Switch

It is a multi-path selector based on multiple conditions:

switch x begin
    case condition(x) go
        ** first case  
    case condition(x) go
        ** second case
    case condition(x) go
        ** third case
    else
        ** default case  
end switch;

## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
while condition begin
  ** shortcut iteration
  if condition then repeat;
  ...
  ** early interruption
  if condition then break;
  ...
else
  ** alternative path  
  ...
end while;
```

**example**

```
** example of collection iteration
method test(): 
  List: this = ["a","b","c","d","e"];  
  Integer: i = 0;
  Symbol: e;  
begin
  while i < this.length() 
  begin
    share  e := this[i];
    alter  i := i + 1;
    if e  >= "c" then
      print e & (',' if e is not this.tail)
    end if;
  else
    print ('i = ' + i);  
  end while;
end method;  
```

**output**
```
"c","d","e"
i = 5
```

## For

This block use one or more control variables to visit elements in a collection or domain.

**Pattern:**
``` 
for var in (min..max) 
begin
  ** block statements;
  ...
  ** next iteration
  if condition then repeat;
  ...  
  ** early interruption
  if condition then break 
  ...
end for;
```

**Notes:**    

* Control variable is auto-incremented using next;
* Control variable must be declared in local scope;

Example of range iteration using step ratio 2:
```
task
  Integer: i;
begin  
  for i in (1..10:2) 
  begin
    ** write only odd numbers
    write i;
    write ',' if (i < 10);
  end for;
end task;  
print;
```
> 1,3,5,7,9

**Read next:** [Classes](classes.md)