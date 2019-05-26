## Data Processing

By using collections and control structures one can load, modify and store data.

* [List operations](#List-operations)
* [Collection Iteration](#Collection-Iteration)
* [Scanning items](#Scanning-items)

## List operations
We can add elements to a list or remove elements from the list using next operations: 

* .insert()
* .append()
* .delete()

### List Concatenation
List concatenation is ready using operator “+”. This operator represent union. 
Therefore List union act very similar to append, except we add multiple elements. 

```
method main:
  List{Symbol}: a := ['a','b','c'];
  List{Symbol}: b := ['1','2','3'];
  List{Symbol}: c := [];
process
  c := a + b;
  print c; -- ['a','b','c','1','2','3'];
return;
```

### Join() built-in
The join function receive a list and convert elements into a string separated be specified character.

```
given
  String: str;
do
  str := join([1,2,3],",");
  print (str) -- "1,2,3";
done; 
```

### Split built-in
The join function receive a list and convert elements into a string separated be specified character.

```
given
  List{Integer}: lst;
do
  lst := split("1,2,3",",");
  print lst; -- (1,2,3)
done;
```

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
* List.append(value) -- can append an element at the end of the list
* List.insert(value) -- can insert an element at the beginning of the list
* List.delete(value) -- can delete one element at specified index
* List.count() -- retrieve the number of elements 

### Special attributes
A list has properties that can be used in logical expressions:

* List.empty()  -- True or False
* List.full()   -- True or False

## Collection Iteration

A special _while loop_ that is executed for each element belonging to a collection.

**pattern**
```
given
  Class_Name: element := collection.first()
while element is not null do
  ** statements
  ...
  element := collection.next(element);
repeat;
```

The "element" is local to iteration and is used as control variable.

**example**

```
method main:
  List{Symbol}: my_list := ['a','b','c','d','e']; 
process  
  given
    Symbol: element;
    Integer: x := 1;
  scan my_list +> element do
    write element;
    when element = 'd' do
      stop -- early termination;
    else
      write(',');
    done;
  next;
return;
```
> c,d

## Scanning items

Collections have common methods that enable traversal using _scan_. 

{List, Hash, Set} 

**built-in:**

* count      - retrieve the number of elements 
* capacity   - retrieve the maximum capacity
* next       - position next element 
* first      - position to first element
* last       - position to last element
* this       - reference to current element

### Set Iteration
Hash and Set are similar. We can visit all elements using _scan_:

**Example:**
```
method main:
  Hash: my_map := {("a":1),("b":2),("c":3)};
process  
  ** print pairs (key:value)
  given
    String: key;
    Integer: value;
  scan my_map :> (key:value) do
    print('("' + key + '",' + value +')');
  repeat;
return;
```

Will print:
```
("a",1)
("b",2)
("c",3)
```

## Hash collections

Hashs are sorted in memory by _key_ for faster search. It is more difficult to search by value because is not unique and not sorted. To search by value one must create a loop and verify every element. This is called full scan and is very slow so you should never use this method.


**example:**
```
** check if a key is present in a hash collection
given
  Hash:  my_map := {(1:'a'),(2:'b'),(3:'c')};
  Integer: my_key := 3;
when (my_key in my_map) do
  print('True'); -- expected
else
  print('False');
done;
```

**example**
```
** create new elements in the hash collection
method main:
process
  given
    Hash(String, String): animals := {};
  do
    animals['Bear'] := 'dog';
    animals['Kiwi'] := 'bird';
    print(animals);
  done;
return;
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
method main:
  Hash: animals := {}; -- partial declaration
process
  ** establish element types S:U
  animals['Rover'] := "dog";

  ** use direct assignment to create 2 more element
  animals['Bear'] := "dog";
  animals['Kiwi'] := "bird";
  print(animals);
return;
```
output:
```
{('Rover':"dog"),('Bear':"dog"),('Kiwi':"bird")}  
```

## String: concatenation

Strings can be concatenated using:

* fast concatenation operator: "&"
* trim concatenation operator: "+"
* path concatenation operator: "/"

**Example:**
```
** this is example of string concatenation
given
  String: str := ""; 
do
  ** set string value using different operators
  str := "this " & " string";  -- "this  string"
  str := "this " + " string";  -- "this string"
done;
```

**path concatenation**
Two strings can be concatenated using concatenation operator "/" or "\\". This operator is used to concatenate "path" strings or URL locations. Notice "\\" is also escape character used for string templates.

```
given
  String: s := "";
do  
  s := 'te/' / '/st'; -- "te/st" Linux
  s := 'te/' \ '/st'; -- "te\st" Windows
done;
```

## Text concatenation

String: and text can be concatenated using the string concatenation operators: {+, &}. 


## Text functions

*  Text:    replace(Text: str, String: target, String: arrow );
*  Integer: find   (Text: str, String: patern);
*  Integer: count  (Text: str, String: patern);
*  Integer: length (Text: str);

**Reading a Text**

Text is iterable by "word". The word separator is one space. So we can read a text string word by word not line by line. We can use "for" iteration to check every word in the text. One word can not start/end with space. 

**Note:**
The text also support escape sequences like a normal string. However in a text literal we do not have to escape the single quote symbols: "'". However we have to escape the double quotes like: "This is \"quoted\" text". This is very rare since quoted text should use symbols: "« »" like "«quoted»"

**Read next:** [Standard](standard.md)