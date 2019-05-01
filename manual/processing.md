## Data Processing

By using collections and control structures one can load, modify and store data.

## Working with arrays

Array elements have very fast direct access by index. 

```
method: test_array()
  ** array  with capacity of 10 elements
  Array[Integer](10): my_array 
process  
  given
    Integer: m := my_array.capacity()
    Integer: i := 1
  ** scan array and modify element by element    
  while i < m do
    my_array[i] := i     
    i += 1
  repeat
  ** array  elements are identified using [index]
  print ("This is the first element: {1}" <+ my_array[1])
  print ("This is the last element: {1}"  <+ my_array[m])
return
```

**console:**
```
This is the first element: 1   
This is the last element: 10   
```

**capacity**
An array can changing capacity. This can be ready using built-in method _extend_. The relocation will update any eventual references to the same array so the modification is consistent. The old memory location is free.

```
  <array_name>.extend(c)
```

## Matrix Operations

Modify all elements of the matrix is possible using [*] and assign operator “ := ”

```
** a matrix having 2 rows and 2 columns
** initialize all elements with 100
given
  Matrix[Integer](2,2): M
do
  M[*] := 100
  print (M)
done
```

```
[[100,100],[100,100]]
```

* A matrix can be initialized using literals or constructor. 
* A matrix can support scalar operations like Array

```
given
  Matrix[Integer](2,2):M
do
  M[*] := 100
  ** modify all elements
  M[*] += 10 
  print(M) ** [[110,110],[110,110]]

  ** modify an entire row 
  M[1,*] := 0
  M[1,*] := 1
  print(M) ** [[0,0],[1,1]]
  
  ** modify an entire column
  M[*,1] += 1
  M[*,2] += 2
  print(M) ** [[1,2],[2,3]]
done
```

**Memory impedance**

Matrices are multidimensional while computer memory is linear. This is an impedance mismatch that require mapping. Some computer languages organize matrices row by row and some others organize memory column by column. The difference between the orders lies in which elements of an array are contiguous in memory. 

[Row-major and column-major order](https://en.wikipedia.org/wiki/Row-_and_column-major_order)

**Transposition**
Passing a memory matrix from one computer language into another can require a transposition that can be a performance bottleneck. EVE uses row-major order therefore passing matrix arguments is the most efficient with Rust and C++ languages.  

**Matrix Traversal**
When you traverse elements use rows first, than you change the column. A processor will use the internal cache more efficient in this way. If the matrix is large this can be a significant performance issue.

**Example:**
In this example we traverse all the rows then all the column, this is the most efficient way to traverse a matrix.

```
method: main()
  Matrix[String(2)](3,3): M 
process  
  M := [ 
         ['a0','b0','c0'],
         ['a1','b1','c1'],
         ['a2','b2','c2']
       ]        
  given
    Integer: row, col := 1
  while col <= 3 do     ** traverse columns
    while row <= 3 do   ** traverse row first
      print M[row,col]
      row += 1
    repeat
    col += 1
  repeat
return
```

##  Arrays Slicing

A slice is a small portion from an Array created with range operator "[..]" 

**syntax**
```
   slice_name := collection[n..m]
```

Where (n,m) are 2 optional numbers: n ≥ 1, m <= number of elements. 

**notes**

* Slice is "zero cost" view. It does not allocate new memory. 
* Slice is a collection references to original elements. 
* If we modify elements of slice you actually modify the original.  

**Example:**
```
method: main() => ()
  Array[Integer]: a := [0,1,2,3,4,5,6,7,8,9]
  Array[Integer]: b :: a[1..4] ** slice reference
process
  print(a[1..?])   ** will print [0,1,2,3,4,5,6,7,8,9]
  print(a[1..1])   ** will print [0]
  print(a[1..4])   ** will print [1,2,3]
 
  ** modify slice b (reference to a)
  b[*] += 2
  
  ** first 4 elements of (a) are modified
  print(a)  ** will print: [2,3,4,5,4,5,6,7,8,9]
return
```

### Set builders

You can define elements of a subset from a set using the following construction:
```
given
   Set: sub_set := { var : var in set_name & filter_expression}
```

Symbol ":" is the filter operator. 
We can use _var_ to create the _filter_expression_.

Example of a new set defined from a range:

```
  new_set := { x : x in [-10..10] }
```

## Collection Casting

It is common for one collection to be created based on elements from another collection. 
Collection members can be copy into the new collection using a comprehension notation: 

**Example:**
```
given
   List: source  := [0,1,2,2,2,2]
   Set : new_set := {}
do
   ** eliminate duplicates using set comprehension
   mew_set := { x : x in my_list } 
   print my_set ** {0,1,2} 
done
```

## Filtering
Build notation can use expressions to filter out elements during comprehension operation.

**Example:**
```
given
   List: my_list := [0,1,2,3,4,5]
   Set:  my_set  := {}
do
   my_set := { x : x in my_list & (x % 2 = 0) } 
   print my_set; ** {0,2,4} 
done
```

## Mapping
The elements in one set or list can be transformed by a function or expression to create a new collection.

**Example:**
```
given
   Set:  source := {0,1,2,3,4,5}
   Hash: target := {}
do
   ** create Hash pairs (key, value) for Hash map
   ** { 0:0, 1:1, 2:4, 3:9, 4:16, 5:25} 
   target := { (x:x^2): x in source } 
done
```

## List Concatenation
List concatenation is ready using operator “+”. This operator represent union. 
Therefore List union act very similar to append, except we add multiple elements. 

```
method: main()
  List[Symbol]: a := ('a','b','c')
  List[Symbol]: b := ('1','2','3')
  List[Symbol]: c := () 
process
  c := a + b
  print(c)**['a','b','c','1','2','3']
return
```

## Join() built-in
The join function receive a list and convert elements into a string separated be specified character.

```
given
  String: str
do
  str := join([1,2,3],",")
  print (str) ** "1,2,3"
done  
```

### Split built-in
The join function receive a list and convert elements into a string separated be specified character.

```
given
  List[Integer: ]: lst := ()
do
  lst := split("1,2,3",",")
  print lst ** (1,2,3)
done
```

### List operations
We can add elements to a list or remove elements from the list using next operations: 

* insert()
* append()
* delete()

### List as queue

Two operations are possible

* enqueue()  append to the end of the List
* dequeue()  extract first element from the List

### List as stack

Two operations are possible

* push() - can append element in top of the stack
* pop()  - can extract the last element of the stack 

**Note:** There is no protection about using a List as stack or queue. 

### Other built-ins

Following other functions should be available
* append(value) – can append an element at the end of the list
* insert(value) – can insert an element at the beginning of the list
* delete(value) – can delete one element at specified index
* count() - retrieve the number of elements 

### Special attributes
A list has properties that can be used in logical expressions:

* list.empty()  ** True or False
* list.full()   ** True or False


## Iteration

A special _while loop_ that is executed for each element belonging to a collection.

**template**
```
given
  type_name: element := collection.first()
while element is not Null do
  ** statements
  ...
  element := collection.next(element)
repeat
```

### Iterator element

The "element" is local to iteration and is used as control variable.

### Early termination
It is possible to change this using stop keyword. 

**Program Example**

```
** example of collection iteration
method: main()
  List[Symbol] my_list := ['a','b','c','d','e'] 
process  
  given
    Symbol: element := my_list[1]
    Integer: x := 1
  while True
    write(element)
    if (element = 'd') do
       stop ** early termination
    else
       write(',')           
    done
    element := my_list[x++]
  repeat
return
```
> c,d

## Visit items

Collections have common methods that enable traversal using a visitor. 

{List, Hash, Set} 

**built-in:**

* count      - retrieve the number of elements 
* capacity   - retrieve the maximum capacity
* next       - position next element 
* first      - position to first element
* last       - position to last element
* this       - reference to current element

## Set Iteration
Map and set are similar. We can visit all elements:

**Example:**
```
method: main()
  Hash: my_map := {("a":1),("b":2),("c":3)}
process  
  ** print pairs (key:value)
  given
    String: key
    Integer: value
  visit (key, value) in my_map do
    print('("' + key + '",' + value +')');
  repeat
return
```
Will print:
```
("a",1)
("b",2)
("c",3)
```

## Hash collections

Hashes are sorted in memory by _key_ for faster search. It is more difficult to search by value because is not unique and not sorted. To search by value one must create a loop and verify every element. This is called full scan and is very slow so you should never use this method.


**example:**
```
** check if a key is present in a hash collection
given
  Hash: my_map := {(1:'a'),(2:'b'),(3:'c')}
  Integer: my_key := 3
if (my_key in my_map) do
  print('True') ** expected
else
  print('False')
done
```

**example**
```
** create new elements in the hash collection
method: main()
process
  given
    Hash(String, String): animals := {}
  do
    animals['Bear'] := 'dog'
    animals['Kiwi'] := 'bird'
    print(animals)
  done
return
```

Output:
```
{('Bear':'dog'),('Kiwi':'bird')}
```

## Type inference

* The default type inference for empty "set" is {}
* An empty hash map will be created using notation {} 

### Example
```  
method: main()
  Hash: animals := {} ** partial declaration
process
  ** establish element types S:U
  animals['Rover'] := "dog"

  ** use direct assignment to create 2 more element
  animals['Bear'] := "dog"
  animals['Kiwi'] := "bird"
  print(animals)
return
```
output:
```
{('Rover':"dog"),('Bear':"dog"),('Kiwi':"bird")}  
```

## String: concatenation

Strings can be concatenated using:

* string concatenation operator: "&"
* trim and concatenation operator: "+"
* path concatenation operator  : "/"

**Example:**
```
** this is example of string concatenation
given
  String: str := "" 
do
  ** set string value using different operators
  str := "this "&" string"   ** "this  string"
  str := "this "+" string"   ** "this string"
done
```

**path concatenation**
Two strings can be concatenated using concatenation operator ".". This operator is used to concatenate "path" strings. The "." is converted to \ or / depending on the operating system.

```
given
  String: s := ""
do  
  s := 'te/' / '/st' ** "te/st" ** Linux
  s := 'te/' / '/st' ** "te\st" ** Windows
done
```

## Text concatenation

String: and text can be concatenated using the string concatenation operators: {+, - , _ }. A normal string can be implicit converted into a text. However a text can not be converted into a string without force casting string(<text_variable>). This may return good string or gibberish depending on text_variable content.

## Text template
We use hash "#" to create a placeholder into a Text. We use "<+" operator to replace the placeholder with values. If placeholder is not found the compiler raise an error. If the string is a variable this verification is not possible at compile time so maybe you get a run-time error.

#s  := sub-string placeholder   
#n  := integer or real number   
#u  := Unicode placeholder: example "≠" is U+2260
#{} := Hash key placeholder 
#[] := Array placeholder    

```
print ("number #n" <+ 10)
print ("strings #s and #s" <+ ('10','even'))
print ("unicode #u" <+ U+2260)
```
**Expected output:**
```
number 10
strings 10 and even
unicode ≠
```

**Notes**: 
* Operator <+ is polymorph and overloaded. 
* For template we can use numbers, strings, lists, hashes, arrays


## How to use a template?
* Create a map collection of elements
* Create the template text 
* Use the _format_ build in function to replace placeholders with values
* Alternative use operators: <+ to replace template with values

**Using Hash**
```
method: main()
  Text: template := "Hey look at this #{key1} it #{key2}"
  Hash: my_map   := {("key1":"test"),("key2":"works!")}
process  
  ** using format function
  print(template.format(my_map)) 
return
```

Expect output:
```
Hey look at this test it works!
```

**Using Array**
```
method: main()
  String: template := "Hey look at this #[0] it #[1]"
  List: my_list    := ("test","works!")
process  
  print (template <+ my_set)
return
```

Expect Output:
```
Hey look at this test it works!
```

## Numeric format
Number type is implementing format() method. This method has one string parameter that is optional.

```
method: format(Number: n, String: f) => String
```

Where "f" is a pattern: '(ap:m.d)'

* a is alignment one of {<,>,^}, 
* p is the padding character: {'_','.',' ',0...}
* m is the length 
* d is number of decimals 

### Alignment symbol "a" can be one of:
```
> is used to align to the right
< is used to align to the left
^ is used to align to center
```
### Format examples:
```
 '(>_:10)'  ** right align string fill with spaces to 10 characters
 '(>0:10.2)' ** right align fill with 0 up to 10 digits and use 2 decimals
```

### Text functions

* Text:    format (Text: str, Hash: map)
* Text:    replace(Text: str, String: target, String: arrow )
* integer: find   (Text: str, String: patern)
* integer: count  (Text: str, String: patern)
* integer: length (Text: str)

**Reading a Text**

Text is iterable by "word". The word separator is space. So we can read a text string word by word not line by line. We can use "for" iteration to check every word in the text. This makes EVE a text reader.

**Note:**
The text also support escape sequences like a normal string. However in a text literal we do not have to escape the quote symbols: "'" and '"'. However we have to escape three dots: "\..." inside text to avoid early termination by mistake.

**Read next:** [Databases](databases.md)