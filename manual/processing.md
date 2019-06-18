## Data Processing

By using collections and control structures one can load, modify and store data.

* [@list operations](#@list-operations)
* [Collection iteration](#Collection-iteration)
* [Scanning items](#Scanning-items)
* [Using hash table](#Using-hash-table)
* [@text functions](#@text-functions)

## @list operations
We can add elements to a list or remove elements from the list using next operations: 

* .insert()
* .append()
* .delete()

**@list concatenation**

@list concatenation is ready using operator “+”. This operator represent union. 
Therefore @list union act very similar to append, except we add multiple elements. 

```
method main:
  @list{Symbol}: a := ['a','b','c'];
  @list{Symbol}: b := ['1','2','3'];
  @list{Symbol}: c := [];
process
  c := a + b;
  print c; ** ['a','b','c','1','2','3'];
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
  print lst; ** (1,2,3)
done;
```

**@list as queue**

Two operations are possible

* enqueue()  append to the end of the @list
* dequeue()  extract first element from the @list

**@list as stack**

Two operations are possible

* push() - can append element in top of the stack
* pop()  - can extract the last element of the stack 

**Note:** There is no protection about using a @list as stack or queue. 

**Other built-ins**

Following other functions should be available
* @list.append(value) ** can append an element at the end of the list
* @list.insert(value) ** can insert an element at the beginning of the list
* @list.delete(value) ** can delete one element at specified index
* @list.count() ** retrieve the number of elements 

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
  @list{symbol}: my_list := ['a','b','c','d','e']; 
process  
  given
    @iterator: e <: my_list;
    @integer: x := 1;
  scan my_list do
    write e;
    when e = 'd' do
      stop ** early termination;
    else
      write(',');
    done;
  next;
return;
```
> c,d

## Scanning items

Collections have common methods that enable traversal using _scan_. 

{@list, @hash, @set} 

**built-in:**

* count      - retrieve the number of elements 
* capacity   - retrieve the maximum capacity
* next       - position next element 
* first      - position to first element
* last       - position to last element
* this       - reference to current element

**set iteration**
@hash and @set are similar. We can visit all elements using _scan_:

**Example:**
```
method main:
  @hash: my_map := {("a":1),("b":2),("c":3)};
process  
  ** print pairs (key:value)
  given
    @symbol: key;
    @binary: value;
  scan my_map +> (key,value) do
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
  print('true'); ** expected
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
  @hash: animals := {}; ** partial declaration
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
* trim concatenation operator: "+"
* path concatenation operator: "/"

**Example:**
```
** this is example of string concatenation
given
  @string: str := ""; 
do
  ** set string value using different operators
  str := "this " & " string";  ** "this  string"
  str := "this " + " string";  ** "this string"
done;
```

**path concatenation**
Two strings can be concatenated using concatenation operator "/" or "\\". This operator is used to concatenate "path" strings or URL locations. Notice "\\" is also escape character used for string templates.

```
given
  @string: s := "";
do  
  s := 'te/' / '/st'; ** "te/st" Linux
  s := 'te/' \ '/st'; ** "te\st" Windows
done;
```

## @text functions

* @text:    replace(@text: str, @string: target, @string: arrow );
* @integer: find   (@text: str, @string: patern);
* @integer: count  (@text: str, @string: patern);
* @integer: length (@text: str);

**Reading a @text**

@text is iterable by "word". The word separator is one space. So we can read a text string word by word not line by line. We can use "for" iteration to check every word in the text. One word can not start/end with space. 

**Note:**
The text also support escape sequences like a normal string. However in a text literal we do not have to escape the single quote symbols: "'". However we have to escape the double quotes like: "This is \"quoted\" text". This is very rare since quoted text should use symbols: "« »" like "«quoted»"

**Read next:** [Standard](standard.md)