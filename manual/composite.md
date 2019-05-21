## Composite Types

Composite types represents groups of multiple elements. 
 
* [ordinal](#ordinal) 
* [array](#array)
* [slice](#slice)
* [matrix](#matrix)
* [list](#list)
* [set](#set)
* [table](#table)
* [string](#string)
* [text](#text)
* [exception](#exception)

## Array

An array is a collection of elements stored in order of natural index. Array elements all must have same data type and can be native or references. Default array index start from 1 to capacity. 

**array declaration** 
```
** declaration of an array with capacity
  Array[element_type](capacity): array_name;
```

**array capacity**
An array have fix capacity that must be specified when the Array memory is allocated. You can’t add or remove elements from array once the capacity is established. This is because array elements are stored in a contiguous memory range with no gaps.

**array literals**

Arrays are represented by an enumeration of elements enclosed by square brackets and delimited by comma [,,,]. An empty array is theoretical possible but not usable. When an array is initialized the capacity of the array  will be the same with the number of elements.

**array initialization**

In the next example we define an array with capacity of 3 elements.

```
** array declaration and initialization
   Array[Integer](3): my_arra := [1,2,3];
```

**array constructor**

An array can be established using a constructor. All elements of a array can be set to a single value using operator ":=" during declaration. Default constructor for an array is the array variable name follow by parameter (c):capacity.

```
** define a constructor con based on based constructor: my_array()
method con(Integer: capacity) => (Array[Integer]: my_array):
process
  my_array(capacity) := 0;
return;
```

**array inference**
When declare a array we can use a literal to initialize the array with value. Array type can be partial declared. That is we can have a logical deduction of missing information from literals.
```
  Array(10): my_array := 0;   --  Integer number
  Array(10): my_array := 0.0; -- real number
  Array(10): my_array := "";  -- text with variable size
  Array(10): my_array := '';  -- string with capacity 1024 bytes
```

The most convenient way to define an Array is by using inference literals:
```
  ** array with capacity 4 of type strings 
  Array: my_array := ['a','bc','def','chk'];
```

**array elements**
Array elements can be addressed by subscript starting from 1:

```
my_array[1];   -- is the first element of Array
my_array[-1];  -- is the last element of Array
```

## Matrix
A matrix is a multidimensional array that is a collection of elements organized in rows and columns. Usually a matrix have two logical dimensions but multiple dimensions are possible.A matrix has a predefined capacity and occupy a fixed memory size.

**syntax:** 
```
   Matrix[type](n,m): matrix_name := expression;
```

**example:**
```
**  a matrix m that has 2 dimensions with 3 rows and 3 columns.
given
  Matrix[String(2)](3,3): m := '__';
do
  m[1] := ['a1','b1','c1'];
  m[2] := ['a2','b2','c2'];
  m[3] := ['a3','b3','c3'];
  print m;
done;
```

**matrix elements**
Matrix elements can be addressed by subscript starting from 1:

```
var_name[1,1];   -- is the first element of the matrix.
var_name[-1,-1]; -- is the last element of a matrix.
```

## List

A list is a consecutive sequence of elements having a dynamic capacity. 

**syntax**
```
  List[Class_Name]: list_name; -- new empty list
  List: list_name := (value, ...); -- new populate list
```

**notes:**

* The elements of a list have the same type; 
* Access to elements is sequential not direct;

**examples**
```
given
  List[Integer] : n_list; 
  List[Object]  : o_list; 
  List[String]  : s_list; 
```

**list literals**
 
* List literals enclosed in round bracket
* Elements are separated by comma. (,,,) 
* All elements are using the same type

**examples**

Literals can be used for initialization:
```
given
  List[Symbol] : c_list := ('a', 'b', 'c');
  List[Integer]: n_list := (1, 2, 3);  
```

Literals can be used in expressions:
```
given
  ** define empty list if native types
  List[Integer]: c_list;
do
  ** update list using  ":=" 
  c_list := (1,2,3); 
done;
```

## Set
In mathematics a set is an abstract data structure that can store certain values, without any particular order, and no repeated values. Sets are fast to search, add or remove elements from. However, you have to know the element value in order to search for it or to remove it from the set. 

**declaration**

```
  Set[type] :name;
```

**Empty Set**

An empty set is represented like this: {} and can be assigned to a set if you wish to remove all elements of the set. A set that is not initialized is empty. This is also called zero value for set.

**Set restrictions**

* All elements of a set must have the same type
* Set elements can have only comparable types: {Ordinal, Numeric, String}.

**Mutability**

A set can be modified during run-time using operators. 

* += for append 
* -= for delete  
* := for replace 

**Example:**
```
given
  Set[integer]: my_set := {0,2,3};
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
  Set: first := {0,1,2,3,4,5,6,7,8,9};
  Set[Integer]: second := {};
do
  second := first | {0,1,2,10}; -- set union
  print(second); -- {0,1,2,3,4,5,6,7,8,9,10}
done;
```

### Intersection
Intersect operator & find common elements:

```
given
  Set: test := {};
do
  test := {1,2,3,4} & {3,4,5}; 
  print test; -- {3,4}
done;
```

**Note:** Operators "|" and "&" are overloaded betwise operators

## Table

It is called "H" due to similar methodof letter H representing a connection, link or bridge between two columns, the key column is in tirect relation to a value.

* Table is set of (key:value) pairs; 
* The key must be one of {Integer, Natural, String} and is unique;

**syntax**
```
given
  Table[key_type, value_type]: name := {(key:value), ...};
```

**Example**
```
given
  Table[String,  Integer]: dictionary := {};
do   
  dictionary := {('one':1), ('two':2)};
done;
```

## String

In EVE There are two types of strings. Single quoted and double quoted strings. They are using different internal representation but same encoding: UTF8. Single quoted strings can store a single line. Double quoted strings can store multiple lines of text separated by new line "\n".

* Single quoted string, has default capacity 1024 bytes;
* Double quote strings have unrestricted capacity;

### String: declaration
String can be initialized with a constant literal using single quotes or double quotes. 

```
  String(100): short_string := ''; -- this string can hold 100 symbols, 100*4 = 400 bytes
  String: string_name       := ''; -- default capacity 1024 can hold 256 ASCII symbols
  Text: text_name           := ""; -- variable capacity string can hold many lines of text
```

### String: mutability
In EVE strings are mutable. If you use `:=` new memory is allocated. If you use a modifier: `+=` the string is fill too capacity. If the capacity is over the limit you will get an error: "capacity overflow".

**Example:**
```
method test_string()
  String: str := 'First value';  
  String: ref := 'First value'; 
process  
  expect  (str  = ref); -- same value
  expect !(str == ref); -- different locations  
  
  ref := str;  -- reset ref
  expect (str =  ref); -- same value
  expect (str == ref); -- same location  
  
  ** if we modify "str" then "ref" will appear modified
  str += ":"; -- mutable string
  expect ref = "First value:";
  expect str == ref; -- the reference is holding
  
  ** if we recreate str, reference is reset
  str := 'First value:'; -- new string location
  expect str = ref;      -- same value
  expect !(str == ref);  -- different locations
  ** reference was broken, ref is pointing to old value
  print ref;  -- 'First value:'
return;
```

**Note:** 

* You can create garbage in EVE if you loose references to strings;
* Provision for large capacity strings is not recommended, use Text instead;

### String: comparison

* Two strings are compared using relation operators: { =, <>, <, >, >=, <= }; 
* Two strings that have identical characters are equivalent regardless of quotation;
* The length of the string is the number of represented symbols: '' is counting 0; 
* The capacity of a string is alwasy greater or equal than length.

**Example:**

```
print ('this' = 'this');    -- True (same value)
print ("this" = 'this');    -- True (same value)
print (' this' <> 'this');  -- True (not same value)
print ('this ' <> 'this');  -- True (not same value)
```

### Null strings

We can test if a string is null using "is Null" expression.

```
given 
  String: str := "";
do 
  expect (str = null);
  expect (str = '');
  expect (str = "");
done;
```

## Text

Text can contain multiple lines of symbols separated with end of line character. A text use Unicode symbols and is optimized for faster search of internal words and symbols. Text can be modified while strings are immutable.

**Literal**

A text literal can be defined on multiple lines and will preserve the end of line but will cut the indentation.

```
** declaration example of a text literal
given
  Text: my_text := "";
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
  Text: us := "I can write Greek: \αβγδ\.";
do
  print (us);
done;
```
> I can write Greek: "αβγδ".

To edit source code containing Unicode literals one must use a specific font and UTF-8 source files. 
The preferred font for EVE programming is "DejaVu Sans Mono". 

## Exception

Exception is interrupting the current logical flow and jump to the recover region in current section or parent section. In EVE all exceptions are considered errors.

The exception is a variable of type record that is created when exception is raised and is available in the recover block. System variable #Error contains several members that are fill-in by the EVE program when exception is created: 
```
** system global exception type
class Exception <: Record( 
        Integer: code 
       ,String : message 
       ,String : method_name 
       ,String : module_name 
       ,String : line_number  
      );
** global variable for holding current error
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
method main():
  Real: a;
process  
  a := 1 / 0;
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