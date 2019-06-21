## Composite Types

Composite types represents groups of multiple elements. 
 
* [list](#list)
* [set](#set)
* [hash](#hash)
* [string](#string)
* [text](#text)
* [exception](#exception)

## @list

A list is a consecutive sequence of elements having a dynamic capacity. 

**syntax**
```
  @list{@type}: list_name := [];     ! new empty list
  @list: list_name := [value, ...]; ! new populate list
```

**notes:**

* The elements of a list have the same type; 
* Access to elements is sequential not direct;

**examples**
```
given
  @list{@integer} : n_list; 
  @list{@object}  : o_list; 
  @list{@string}  : s_list; 
```

**list literals**
 
* @list literals enclosed in square brackets,
* Elements are separated by comma,
* All elements are having the same type.

**examples**

Literals can be used for initialization:
```
given
  @list{Symbol} : c_list := ['a', 'b', 'c'];
  @list{@integer}: n_list := [1, 2, 3];  
```

Literals can be used in expressions:
```
given
  ** define empty list if native types
  @list{@integer}: c_list := [];
do
  ** alter list using  ":=" 
  c_list := [1,2,3]; 
done;
```

## @set
In mathematics a set is an abstract data structure that can store certain values, without any particular order, and no repeated values. Sets are fast to search, add or remove elements from. However, you have to know the element value in order to search for it or to remove it from the set. 

**declaration**

```
  @set{type}: set_name;
```

**Empty @set**

An empty set is represented like this: {} and can be assigned to a set if you wish to remove all elements of the set. A set that is not initialized is empty. This is also called zero value for set.

**@set restrictions**

* All elements of a set must have the same type
* @set elements can have only comparable types: {@ordinal, Numeric, @string}.

**Mutability**

A set can be modified during run-time using operators. 

* += for append 
* -= for delete  
* := for replace 

**Example:**
```
given
  @set{@integer}: my_set := {0,2,3};
do
  ** append element 1
  my_set    += 1;  
  expect my_set = {0,1,2,3};
  
  ** modify all elements
  my_set[*] += 1;  
  expect my_set = {1,2,3,4};
  
  ** remove all elements  
  my_set    := {}; 
  expect my_set = {};
done  
```

### Union

Use union operator | combine two sets.

```
given
  @set: first := {0,1,2,3,4,5,6,7,8,9};
  @set{@integer}: second := {};
do
  second := first | {0,1,2,10}; ! set union
  print(second); ! {0,1,2,3,4,5,6,7,8,9,10}
done;
```

### Intersection
Intersect operator & find common elements:

```
given
  @set: test := {};
do
  test := {1,2,3,4} & {3,4,5}; 
  print test; ! {3,4}
done;
```

**Note:** Operators "|" and "&" are overloaded betwise operators

## @hash

It is called "@hash" due to similar letter H representing a connection between two columns: the key column and value column.

* @hash is set of (key:value) pairs; 
* The key must be sortable: { @number, @ordinal, @string };

**syntax**
```
alias Table_Name := @hash{key_type, value_type}; ! type alias 

variable
  @hash{key_type, value_type}: name; ! explicit type
  @hash: name := {(key:value), ...}; ! implicit type
  Table_Name := {(key:value), ...}; ! using alias
```

**Example**
```
given
  @hash{@string,  @integer}: table := {}; ! empty table
do   
  table := {('one':1), ('two':2)};
done;
```

## @string

In EVE There are two types of strings. @single quoted and double quoted strings. They are using different internal representation but same encoding: UTF8. @single quoted strings can store a single line. @double quoted strings can store multiple lines of text separated by new line "\n".

* @single quoted string, has default capacity 1024 bytes;
* @double quote strings have unrestricted capacity;

### @string: declaration
@string can be initialized with a constant literal using single quotes or double quotes. 

```
  @string(100): short_string := ''; ! this string can hold 100 symbols, 100*4 = 400 bytes
  @string: string_name       := ''; ! default capacity 1024 can hold 256 ASCII symbols
  @text: text_name           := ""; ! variable capacity string can hold many lines of text
```

### @string: mutability
In EVE strings are mutable. If you use `:=` new memory is allocated. If you use a modifier: `+=` the string is fill too capacity. If the capacity is over the limit you will get an error: "capacity overflow".

**Example:**
```
method test_string()
  @string: str := 'First value';  
  @string: ref := 'First value'; 
process  
  expect  (str  = ref); ! same value
  expect  (str <> ref); ! different locations  
  
  ref := str;  ! reset ref
  expect (str =  ref); ! same value
  expect (str == ref); ! same location  
  
  ** if we modify "str" then "ref" will appear modified
  str += ":"; ! mutable string
  expect ref = "First value:";
  expect str == ref; ! the reference is holding
  
  ** if we recreate str, reference is reset
  str := 'First value:'; ! new string location
  expect str = ref;      ! same value
  expect str <> ref;     ! different locations
  ** reference was broken, ref is pointing to old value
  print ref;  ! 'First value:'
return;
```

**Note:** 

* You can create garbage in EVE if you loose references to strings;
* Provision for large capacity strings is not recommended, use @text instead;

### @string: comparison

* Two strings are compared using relation operators: { =, <>, <, >, >=, <= }; 
* Two strings that have identical characters are equivalent regardless of quotation;
* The length of the string is the number of represented symbols: '' is counting 0; 
* The capacity of a string is alwasy greater or equal than length.

**Example:**

```
print ('this' = 'this');    ! true (same value)
print ("this" = 'this');    ! true (same value)
print (' this' <> 'this');  ! true (not same value)
print ('this ' <> 'this');  ! true (not same value)
```

### Null strings

We can test if a string is null using "is Null" expression.

```
given 
  @string: str := "";
do 
  expect (str = null);
  expect (str = '');
  expect (str = "");
done;
```

## @text

@text can contain multiple lines of symbols separated with end of line character. A text use Unicode symbols and is optimized for faster search of internal words and symbols. @text can be modified while strings are immutable.

**Literal**

A text literal can be defined on multiple lines and will preserve the end of line but will cut the indentation.

```
** declaration example of a text literal
given
  @text: my_text := "";
do
  my_text:= "Opportunity is missed by most people 
             because it is dressed in overalls 
             and looks like work."; 
  print (my_text);
done;
```

**Output:**
```
"Opportunity is missed by most people 
 because it is dressed in overalls 
 and looks like work."
```

**Unicode**

The _Unicode_ is a standard for representation of writing for all human languages. An Unicode string is a set of _code points_ using symbols from universal character set (UCS). Unicode is more difficult to represent then ASCII. There are many encoding techniques available. Java uses UTF-16. We will probably use UTF-8 to be more efficient.

See also: [wikipedia ucs](https://en.wikipedia.org/wiki/Universal_Coded_Character_Set), 
[unicode characters](https://en.wikipedia.org/wiki/List_of_Unicode_characters#Character_reference_overview)

**Example:**
```
given
  @text: us := "I can write Greek: \αβγδ\.";
do
  print (us);
done;
```
> I can write Greek: "αβγδ".

To edit source code containing Unicode literals one must use a specific font and UTF-8 source files. 
The preferred font for EVE programming is "DejaVu Sans Mono". 

## Exception

Exception is interrupting the current logical flow and jump to the recover region in current section or parent section. In EVE all exceptions are considered errors.

The exception is a variable of type @object that is created when exception is raised and is available in the recover block. System variable #Error contains several members that are fill-in by the EVE program when exception is created: 
```
** system global exception type
alias Exception: @object { 
        @integer: code 
       ,@string : message 
       ,@string : method_name 
       ,@string : module_name 
       ,@string : line_number  
      };

** system variables for last error
variable
  Exception: #error;
```
### Run-time errors
Exceptions can be system exceptions or user defined exceptions.

**system exception** 
System exceptions are predefined and created during the program execution 
when there is a _"run-time error"_ and program can not continue.

### User defined exceptions

There are two alternative statements to create user defined exceptions.

```
** raise exception
when condition do
  raise (code,"message");
done;

** conditional 
raise (code,"message") if (condition);
```

### Exception handling

Recover: region define an "exception handling region" for a method.

In this region developer can use control statements like "switch","case" to analyze the #Error. Developer can decide to stop the program, print a message and resume the program using _resume_ keyword.

**Example:** 

```
method main:
  @double: a;
process  
  alter a := 1 / 0;
recover
  print (#error.message);
return;
```

```
error: numeric division by zero.
```

### Using expect

The expect statement check a condition and raise an error if condition is false. Error message is default: "Unexpected error in line: N".

```
  ** precondition
  expect (condition);
  
  ** equivalent
  raise ("Unexpected error in line \n" <+ #error.line_number ) if (condition);
```

**note:**
* can be used as pre-condition
* can be used as post-condition
* unexpected error has code = 0

**Read next:** [Classes](classes.md)