## Composite Types

Composite types represents groups of multiple elements. 
 
* [ordinal](#ordinal) 
* [array](#array)
* [matrix](#matrix)
* [list](#list)
* [set](#set)
* [hash](#hash)
* [text](#text)

## Ordinal

A ordinal is an enumeration of terms. It is an ordered list of identifiers that can represent things, ideas, concepts, keywords. Each item has an identifier name that can be uppercase, lowercase or mixed . To each item we associate a value that is two Byte number that starts from 0 to N. Maxim number of items is 65535.

**Syntax:**
Ordinal type is usually a finite set that can be enumerated using a literal. In mathematics a set of items is represented using curly brackets {} separated by comma. In the next example we define the days of the week in EVE:

```
define
  type <type_name> <: Ordinal(symbol:<value>, ... )

```

## Usage
Ordinal type is suitable for creation of options that can be used for switch statement. 

* Value of first element can be specified. If is not specified it starts from: 1.    
* Values of next elements can not be specified. That is next element is previous element +1.   
* Elements declared in a Ordinal type are public is we use "." prefix

**Example:**
```
define
  type: Day <: Ordinal (.Sunday:1, .Monday, .Tuesday, .Wednesday, .Thursday, .Friday, .Saturday)  

method: main()
  String: message
process  
  given
    Day: today := today()  
  quest
    if today <+ (Friday, Saturday, Sunday) then
      message:='weekend'
      ...
    if today = Monday then
      message:='first workday'
    if today = Friday then
      message:='last workday'
  other
    message:='middle of the week'
  ready
  print('Is', message)
return
```
**Note** For private enumerations you can use a record type.

**Range**
We can use Ordinal to create a range of values:
```
when (today <+ [Monday..Friday]) do
   print ("Have a nice day!")
else
   print ("Have a happy weekend!")  
ready
```

**Operators**
Ordinal is a ordered set of Natural:numbers identified by a name. Ordinal is a discrete numeral type so it has support for  relation operators: { <, >, ≤, ≥ }. It can be incremented and decremented using += and -=. We can perform addition, subtraction, multiplication.

```
** using type Day declared before
given
  Day: v := Friday
begin
  v += 1 
  expect v = Saturday
ready  
```

## Array

An array is a collection of elements stored in order of natural index. Array elements all must have same data type and can be native or references. Array index start from 1 to last index = capacity.

**array declaration** 
```
** declaration of an array with capacity
global
  Array: array_name[element_type](capacity)
```

**array capacity**
An array have fix capacity that must be specified when the Array memory is allocated. You can’t add or remove elements from array once the capacity is established. This is because array  elements are stored in a contiguous computer memory space with no gaps.

**array literals**

Arrays are represented by an enumeration of elements enclosed by square brackets and delimited by comma [,,,]. An empty array is theoretical possible but not usable. When an array is initialized the capacity of the array  will be the same with the number of elements.

**array initialization**

In the next example we  am array with capacity of 3 elements.

```
** array declaration and initialization
global
   Array: my_array[Integer](3) := [1,2,3]
```

**array constructor**

An array  capacity can be established using a parameter and a constructor. All elements of a array  can be set to a single value using operator ":=" during declaration. 

```
** variable array size depending upon parameter n
method: test(Integer: n)
process
  Array: my_array(n)
return
```

**array inference**
When declare a array we can use a literal to initialize the array with value. Array type can be partial declared. That is we can have a logical deduction of missing information from literals.
```
global
  Array: my_array(10) := 0   ** integer
  Array: my_array(10) := 0.0 ** real 
  Array: my_array(10) := ""  ** Text
  Array: my_array(10) := ''  ** String
```

The most convenient way to an Array using full inference literal:
```
global
  ** capacity is 4 and element type is string
  Array: my_array := ['a','bc','def','chk']
```

**Note:** my_array will be a list if the Array keyword is missing.

## Matrix
A matrix is a multidimensional array that is a collection of elements organized in rows and columns. Usually a matrix have two logical dimensions but multiple dimensions are possible.A matrix has a predefined capacity and occupy a fixed memory size.

**syntax:** 
```
global
   Matrix: matrix_name[type](n,m) := constant
```

**example:**
```
**  a matrix m that has 2 dimensions with 3 rows and 3 columns.
given
  Matrix[String(2)](3,3): m := '__'
begin
  m[1] := ['a1','b1','c1']
  m[2] := ['a2','b2','c2']
  m[3] := ['a3','b3','c3']
  print m
ready
```

**matrix elements**
Matrix elements can be addressed by subscript starting from 1:

```
var_name[1,1] ** is the first element of the matrix.
var_name[?,?] ** is the last element of a matrix.
```

## List

A list is a consecutive sequence of elements having a dynamic capacity. 

**syntax**
```
   List[type_name]: list_name
   List: list_name := (<constant>, <constant>, ...)
```

**notes:**

* The elements of a list have the same type; 
* Access to elements is sequential not direct;

**examples**
```
given
  List[Integer]: n_list 
  List[Object] : o_list 
  List[String] : s_list 
```

**list literals**
 
* List literals enclosed in round bracket
* Elements are separated by comma. (,,,) 
* All elements are using the same type

**examples**

Literals can be used for initialization:
```
given
  List[Char]   : c_list := ('a', 'b', 'c')
  List[Integer]: n_list := (1, 2, 3)  
```

Literals can be used in expressions:
```
given
  ** define empty list if native types
  List[integer]: c_list := () 
begin
  ** update list using  ":=" 
  c_list := (1,2,3) 
ready
```

## Set
In mathematics a set is an abstract data structure that can store certain values, without any particular order, and no repeated values. Sets are fast to search, add or remove elements. However, you have to know the element value in order to search for it or to remove it from the set. 

**declaration**

```
  Set[type] :name := {} 
```

**Empty Set**

An empty set is represented like this: {} and can be assigned to a set if you wish to remove all elements of the set. A set that is not initialized is empty. This is also called zero value for set.

**Set restrictions**

* All elements of a set must have the same type
* Set elements can have only comparable types: {Ordinal, Numeric, String. Text}.

**Example:**
```
given
  Set[integer]: my_set := {0,1,2,3,4,5,6,7,8,9}
```

**Mutability**

A set can be modified during run-time using operators. 

* += for append 
* -= for remove  
* := for replace 

```
  my_set    += 1  ** try to append element 1
  my_set[*] += 1  ** modify each element
  my_set    := {} ** remove all elements  
```
### Union

Union operator ∪ combine two sets.

```
given
  Set: first := {0,1,2,3,4,5,6,7,8,9}
  Set[Integer]: second := {}
begin
  second := first ∪ {0,1,2,10} ** set union
  print(second) ** {0,1,2,3,4,5,6,7,8,9,10}
ready
```

### Intersection
Intersect operator ∩ find common elements:

```
given
  Set: test := {}
begin
  test := {1,2,3,4} ∩ {3,4,5} 
  print test ** {3,4}
ready  
```

## Hash

It is called "H" due to similar method:of letter H representing a connection, link or bridge between two columns, the key column is in tirect relation to a value.

* Hash is set of (<key>:<value>) pairs; 
* The key must be one of {Integer, Natural, String} and is unique;

**syntax**
```
given
  Hash[key_type, value_type]: name := {(key:value), ...}
```

**Example**
```
given
   Hash[String, Integer]: dictionary := {}
begin   
   dictionary := {('one':1), ('two':2)}
ready
```

## Text

Text can contain multiple lines of symbols separated with end of line character. A text use Unicode symbols and is optimized for faster search of internal words and symbols. Text can be modified while strings are immutable.

**Literal**

A text literal can be defined on multiple lines and will preserve the end of line.

```
** declaration example of a text literal
given
  Text: my_text := ""
begin
  my_text:= "Opportunity is missed by most people 
             because it is dressed in overalls 
             and looks like work." 
  print (my_text)
ready
```

**Output:**
```
"Opportunity is missed by most people 
 because it is dressed in overalls 
 and looks like work."
```

**Unicode**

The _Unicode_ is a standard for representation of writing for all human languages. An Unicode string is a set of _code points_ using symbols from universal character set (UCS). Unicode is more difficult to represent then ASCII strings. There are many encoding techniques available. Java uses UTF-32. We will probably use UTF-8 to be more efficient.

See also: [wikipedia ucs](https://en.wikipedia.org/wiki/Universal_Coded_Character_Set), 
[unicode characters](https://en.wikipedia.org/wiki/List_of_Unicode_characters#Character_reference_overview)

**Example:**
```
given
  Text: us := "I can write Greek: \αβγδ\."
begin
  print (us)   
ready   
```
> I can write Greek: "αβγδ".

To edit source code containing Unicode literals one must use a specific font and UTF-8 source files. 
The preferred font for EVE programming is "DejaVu Sans Mono". 

**Read next:** [Classes](classes.md)