## Data Processing

By using collections and control structures one can load, modify and store data.

* [List operations](#@list-operations)
* [Collection iteration](#Collection-iteration)
* [Scanning items](#Scanning-items)
* [Using hash table](#Using-hash-table)
* [Text functions](#@text-functions)

## List operations
We can add elements to a list or remove elements from the list using next operations: 

* .insert()
* .append()
* .delete()

**List concatenation**

List concatenation is ready using operator “+”. This operator represent union. 
Therefore @list union act very similar to append, except we add multiple elements. 

```
method main:
  @list{@symbol}: a := ['a','b','c'];
  @list{@symbol}: b := ['1','2','3'];
  @list{@symbol}: c := [];
process
  c := a + b;
  print c; ! ['a','b','c','1','2','3'];
return;
```

**Join() built-in**

The join function receive a list and convert elements into a string separated be specified character.

```
given
  @string: str;
do
  str := join([1,2,3],",");
  print (str) ** "1,2,3";
done; 
```

**Split built-in**
The join function receive a list and convert elements into a string separated be specified character.

```
given
  @list{@integer}: lst;
do
  alter lst := split("1,2,3",",");
  print lst; ! (1,2,3)
done;
```

**List as queue**

Two operations are possible

* enqueue()  append to the end of the @list
* dequeue()  extract first element from the @list

**List as stack**

Two operations are possible

* push() - can append element in top of the stack
* pop()  - can extract the last element of the stack 

**Note:** There is no protection about using a @list as stack or queue. 

**Other built-ins**

Following other functions should be available
* @list.append(value) :can append an element at the end of the list
* @list.insert(value) :can insert an element at the beginning of the list
* @list.delete(value) :can delete one element at specified index
* @list.count()       :retrieve the number of elements 

**Special attributes**
A list has properties that can be used in logical expressions:

* @list.empty()  ** true or false
* @list.full()   ** true or false

## Collection iteration

A special _while loop_ that is executed for each element belonging to a collection.

**pattern**
```
given
  Class_Name: element := collection.first()
while element is not null do
  **statements
  ...
  alter element := collection.next(element);
repeat;
```

The "element" is local to iteration and is used as control variable.

**example**

```
method main:
  @list{@symbol}: my_list := ['a','b','c','d','e']; 
process  
  given
    @string: e;
  for e in my_list do
    write e;
    when e = 'd' do
      stop; ! early termination;
    else
      write(',');
    done;
  next;
return;
```
> c,d

## Scanning items

Collections have common methods that enable traversal using _for_ loop. 

{@list, @hash, @set} 

**built-in:**

* count      - retrieve the number of elements 
* capacity   - retrieve the maximum capacity
* next       - position next element 
* first      - position to first element
* last       - position to last element
* this       - reference to current element

**set iteration**
@hash and @set are similar. We can visit all elements using _for_ loop:

**Example:**
```
method main:
  @hash: my_map := {("a":1),("b":2),("c":3)};
process  
  ** print pairs (key:value)
  given
    @symbol: key;
    @binary: value;
  for (key,value) in my_map do
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

## Using hash table

Hashs are sorted in memory by _key_ for faster search. It is more difficult to search by value because is not unique and not sorted. To search by value one must create a loop and verify every element. This is called full scan and is very slow so you should never use this method.


**example:**
```
** check if a key is present in a hash collection
given
  @hash:  my_map := {(1:'a'),(2:'b'),(3:'c')};
  @integer: my_key := 3;
when (my_key in my_map) do
  print('true'); ! expected
else
  print('false');
done;
```

**example**
```
** create new elements in the hash collection
method main:
process
  given
    @hash(@string, @string): animals := {};
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

### Example

```  
method main:
  @hash: animals := {}; ! partial declaration
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

## @string: concatenation

Strings can be concatenated using:

* fast concatenation operator: "&"
* left trim concatenation operator: "+"
* all  trim concatenation operator: "-"
* path concatenation operator: "/"

**Example:**
```
** this is example of string concatenation
given
  @string: str := ""; 
do
  ** set string value using different operators
  str := "this " & " string";  ! "this  string"
  str := "this " + " string";  ! "this string"
  str := "this " . " string";  ! "this/string"
  str := "this " - " "      ;  ! "this"  
done;
```

**path concatenation**
Two strings can be concatenated using concatenation operator "/" or "\\". This operator is used to concatenate "path" strings or URL locations. Notice "\\" is also escape character used for string templates.

```
given
  @string: s := "";
do  
  s := 'te/' / '/st'; ! "te/st" Linux
  s := 'te/' \ '/st'; ! "te\st" Windows
done;
```

## Text functions

* @text:    replace(@text: str, @string: target, @string: arrow );
* @integer: find   (@text: str, @string: patern);
* @integer: count  (@text: str, @string: patern);
* @integer: length (@text: str);

**Note:**
The text also support escape sequences like a normal string. However in a text literal we do not have to escape the single quote symbols: "'". However we have to escape the double quotes like: "This is \"quoted\" text". This is very rare since quoted text should use symbols: "« »" like "«quoted»"

**Read next:** [Standard](standard.md)