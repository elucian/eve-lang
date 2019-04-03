## Composite Types

Composite types represents groups of multiple elements. 
 
* [array](#array)
* [matrix](#matrix)
* [list](#list)
* [set](#set)
* [hash](#hash)

## Array

An array is a collection of elements stored in order of natural index. Array elements all must have same data type and can be native or references. Array index start from 1 to last index ≡ capacity.

**array declaration** 
```
-- declaration of an array with capacity
global
  Array array_name[type](capacity);              -- initialized with zero
  Array array_name[type](capacity) *= constant;  -- initialized with constant
```

**array capacity**
An array have fix capacity that must be specified when the Array memory is allocated. You can’t add or remove elements from array once the capacity is established. This is because array  elements are stored in a contiguous computer memory space with no gaps.

**array literals**

Arrays are represented by an enumeration of elements enclosed by square brackets and delimited by comma [,,,]. An empty array is theoretical possible but not usable. When an array is initialized the capacity of the array  will be the same with the number of elements.

**array initialization**

In the next example we  am array with capacity of 3 elements.

```
-- array declaration and initialization
global
   Array my_array[Integer](3) := [1,2,3];
```

**array constructor**

An array  capacity can be established using a parameter and a constructor. All elements of a array  can be set to a single value using operator ":=" during declaration. 

```
-- variable array size depending upon parameter n
method test(n ∈ Integer)
  Array my_array(n) *= 0;
over;
```

**array inference**
When declare a array we can use a literal to initialize the array with value. Array type can be partial declared. That is we can have a logical deduction of missing information from literals.
```
global
  Array my_array(10) *= 0   ; --> of integer
  Array my_array(10) *= 0.0 ; --> of real 
  Array my_array(10) *= ""  ; --> of Text
  Array my_array(10) *= ''  ; --> of String
```

The most convenient way to an Array using full inference literal:
```
global
  -- capacity is 4 and element type is string
  Array my_array := ['a','bc','def','chk'];
```

**Note:** my_array will be a list if the Array keyword is missing.

## Matrix
A matrix is a multidimensional array that is a collection of elements organized in rows and columns. Usually a matrix have two logical dimensions but multiple dimensions are possible.A matrix has a predefined capacity and occupy a fixed memory size.

**syntax:** 
```
global
   Matrix matrix_name[type](n,m)  *= constant ;
```

**example:**
```
--  a matrix m that has 2 dimensions with 3 rows and 3 columns.
given:
  m := '__' ∈ Matrix(3,3) of String(2); 
begin:
  m[1] := ['a0','b0','c0'];
  m[2] := ['a1','b1','c1'];
  m[3] := ['a2','b2','c2'];
  print m;
ready;
```

**matrix elements**
Matrix elements can be addressed by subscript starting from 1:

```
var_name[1,1] -- is the first element of the matrix.
var_name[?,?] -- is the last element of a matrix.
```

## List

A list is a consecutive sequence of elements having a dynamic capacity. 

**syntax**
```
   <list_name> ∈ List of <type_name>;
   <list_name> := (<constant>, <constant>, ...);
```

**notes:**

* The elements of a list have the same type; 
* Access to elements is sequential not direct;

**examples**
```
given:
  n_list ∈ List of Integer;
  o_list ∈ List of Class;
  s_list ∈ List of String;
```
**list literals**
 
* Initialization of a list can be done using assign operator ":="
* List literals enclosed in round bracket.
* Elements are separated by comma. (,,,). 
* All elements are using the same type.

**examples**

Literals can be used for initialization:
```
given:
  List c_list[Char]    := ('a', 'b', 'c');
  List n_list[Integer] := (1, 2, 3);  
```

Literals can be used in expressions:
```
given:
  -- define empty list if native types
  List c_list[integer] := (); 
scope
  -- update list using  ":=" 
  c_list := (1,2,3); 
scope;
```

## Set
In mathematics a set is an abstract data structure that can store certain values, without any particular order, and no repeated values. Sets are fast to search, add or remove elements. However, you have to know the element value in order to search for it or to remove it from the set. 

**syntax**

```
given:
  Set name[type] := {};
```

**Empty Set**

An empty set is represented like this: {} and can be assigned to a set if you wish to remove all elements of the set. A set that is not initialized is empty. This is also called zero value for set.

**Set restrictions**

* All elements of a set must have the same type
* Set elements can have only comparable types: {ordinal, number, string}.

**Example:**
```
given:
  Set my_set[integer] := {0,1,2,3,4,5,6,7,8,9}
```

**Mutability**

A set can be modified during run-time using operators. 

* append: += 
* remove: -= 
* clear : := {} 

### Union

Union operator ∪ combine two sets.

```
given:
  Set first := {0,1,2,3,4,5,6,7,8,9};
  Set second[Integer] := {};
begin:
  second := first ∪ {0,1,2,10}; --set union
  print(second) ; -- {0,1,2,3,4,5,6,7,8,9,10}
ready;
```

### Intersection
Intersect operator ∩ find common elements:

```
given:
  Set test := {};
begin:  
  test := {1,2,3,4} ∩ {3,4,5}; 
  print test; --> {3,4}
ready;  
```

## Hash Map

It is called "H" due to similar method of letter H representing a connection, link or bridge between two columns, the key column is in tirect relation to a value.

* Hash is set of (<key>:<value>) pairs; 
* The key must be one of {Integer, Natural, String} and is unique;

**syntax**
```
given:
  Hash name(key_type:value_type) := {(key:value), ...};
```

**Example**
```
given:
   Hash dictionary(String :Integer) := {};
begin:   
   dictionary := {('one':1), ('two':2)};
begin:   
```

## Unicode Strings
The _Unicode_ is a standard for representation of writing for all human languages. An Unicode string is a set of _code points_ using symbols from universal character set (UCS). Unicode is more difficult to represent then ASCII strings. There are many encoding techniques available. Java uses UTF-32. We will probably use UTF-8 to be more efficient.

See also: [wikipedia ucs](https://en.wikipedia.org/wiki/Universal_Coded_Character_Set), 
[unicode characters](https://en.wikipedia.org/wiki/List_of_Unicode_characters#Character_reference_overview)

**Example:**
```
given:
   Text us := "I can write Greek: \αβγδ\.";
begin:   
   print(us);   
ready;   
```
> I can write Greek: "αβγδ".

To edit source code containing Unicode literals one must use a specific font and UTF-8 source files. 
The preferred font for EVE programming is "DejaVu Sans Mono". 


## Large Text

Text can contain multiple lines of symbols separated with end of line character. A text use Unicode symbols and is optimized for faster search of internal words and symbols. Text can be modified while strings are immutable.

## Text Literal

A text literal can be defined on multiple lines and will preserve the end of line.

```
-- declaration example of a text literal
given:
  Text my_text := "";
begin:
  my_text:= "Opportunity is missed by most people 
             because it is dressed in overalls 
             and looks like work." 
  print(my_text);
nigeb;
```

**Output:**
```
"Opportunity is missed by most people 
 because it is dressed in overalls 
 and looks like work."
```
**Read next:** [Classes](classes.md)