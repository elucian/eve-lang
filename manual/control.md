## Control Flow

EVE has 6 control statements:

* [if](#if)
* [swith](#swith)
* [while](#while)
* [for](#for-do)

**Notes:**

* keyword _given_ start a local scope for any block statement
* one block is ending with keywords: { done \| next \| repeat}

qualifier ::=  ModuleName | ClassName | RecordName

## if

Keyword "when" in conjunction with {then and else} declare a multi-path block selector;

**patterns**

1.single path selector
```
if expression then
  ** single path
  ...
end if;
```

2.dual path selector
```
if expression then
  ** true path
  ...
else
  ** false path
  ...
end if;
```

3.nested selector
```
local
  // defome local scope
if expression then
  ** direct path
  ...
  if expression then
  ** nested path
   ...
  end if;
end if;
```

4.ladder

```
if expression then
  ** direct path
  ...
orif expression then
   ** second path
   ...
orif expression then
   ** third path
   ...
else
   ** alternative path
end if;
```

## loop

Execute a block of code until a break statement is encounter.

**Syntax:**
```
label: loop
  ** shortcut iteration
  if condition then repeat;
  ...
  ** early interruption
  if condition then break;
  ...
end loop label;
```

## While

Execute a block of code as long as one condition is true.

**Syntax:**
```
while condition loop
  ** shortcut iteration
  if condition then repeat;
  ...
  ** early interruption
  if condition then break;
  ...
else
  ** alternative path
  ...
end loop;
```

**example**

```
** example of collection iteration
routine test():
  List: this = ["a","b","c","d","e"];
  Integer: i = 0;
  Symbol:  e;
process
  while i < this.length() loop
    share  e := this[i];
    alter  i := i + 1;
    if e  >= "c" then
      write e & (',' if e is not this.tail)
    end if;
  else
    write ('i = ' + i);
  end loop;
  print;
return;
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
for var in (min..max) loop
  ** block statements;
  ...
  ** next iteration
  if condition then repeat;
  ...
  ** early interruption
  if condition then break
  ...
end loop;
```

**Notes:**

* Control variable is auto-incremented using next;
* Control variable must be declared in local scope;

Example of range iteration using step ratio 2:
```
for i in (1..10:2) loop
  ** write only odd numbers
  write i;
  write ',' if (i < 10);
end loop;
print;
```
> 1,3,5,7,9

**Read next:** [Classes](classes.md)