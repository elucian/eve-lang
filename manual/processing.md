## Data Processing

By using collections and control structures one can load, modify and store data.

* [List operations](#@list-operations)
* [Collection iteration](#Collection-iteration)
* [Scanning items](#Scanning-items)
* [Using hash table](#Using-hash-table)
* [Text functions](#@text-functions)

## List operations
We can add elements to a list or remove elements from the list using next operations: 

* append
* delete

**List concatenation**

List concatenation is ready using operator “+”. This operator represent union. 
Therefore @list union act very similar to append, except we add multiple elements. 

```
routine main:
  @list{@symbol}: a := ['a','b','c']; //  initialized collection
  @list{@symbol}: b := ['1','2','3']; //  initialized collection
  @list{@symbol}: c; //  deferred initialization require forge
process
  forge c := a ++ b;
  print c; //  ['a','b','c','1','2','3'];
return;
```

**Join() built-in**

The join function receive a list and convert elements into a string separated be specified character.

```
given
  @string: str; //  Null String
do
  forge str := join([1,2,3],",");
  print str; // "1,2,3"
done; 
```

**Split built-in**
The join function receive a list and convert elements into a string separated be specified character.

```
given
  @list{@integer}: lst; //  Null List
do
  ** initialize new reference for "lst"
  forge lst := split("1,2,3",","); 
  print lst; // (1,2,3)
done;
```

**List as queue**

Two operations are possible

* enqueue() append to the end of the @list
* dequeue() extract first element from the @list

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
  @class_name: element := collection.first();
while element is not null do
  ** statements
  ...
  strap element := collection.next(element);
repeat;
```

The "element" is local to iteration and is used as control variable.

**example**

```
routine main:
  @list{@symbol}: my_list; //  this list is Null
process  
  forge my_list := ['a','b','c','d','e'];
  given
    @string: e;
  for e in my_list do
    write e;
    when e = 'd' do
      stop; //  early termination;
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
routine main:
  @hash: my_map;
process  
  forge my_map := {("a":1),("b":2),("c":3)};
  given
    @symbol: key;
    @binary: value;
  for (key,value) in my_map do
    ** print pairs (key:value)
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

Hashes are sorted in memory by _key_ for faster search. It is more difficult to search by value because is not unique and not sorted. To search by value one must create a loop and verify every element. This is called full scan and is very slow so you should never use this routine.


**example:**
```
routine main:
  @hash: my_map; //  uninitialized collection
process
  ** initialize my_map with values
  forge my_map := {(1:'a'),(2:'b'),(3:'c')};
  
  ** check if a key is present in a hash collection
  when 3 in my_map do
    print('true'); //  expected
  else
    print('false');! unexpected
  done;
return;  
```

**example**
```
** create new elements in the hash collection
routine main:
  @hash(@string, @string): animals := {}; //  empty initialization
process
  ** forge is not necessary here
  append animals['Bear'] += 'dog';
  append animals['Kiwi'] += 'bird';

  ** verify effect of append  
  print  animals; 
return;
```

Output:
```
{('Bear':'dog'),('Kiwi':'bird')}
```

**Example**

```  
routine main:
  @hash: animals := {}; //  empty initialization
process
  ** establish element types S:U
  append animals['Rover'] += "dog";

  ** use direct assignment to create 2 more element
  append animals['Bear'] += "dog";
  append animals['Kiwi'] += "bird";
  
  ** print the collection to console
  print  animals;
return;
```

output:
```
{('Rover':"dog"),('Bear':"dog"),('Kiwi':"bird")}  
```

## String: concatenation

Strings can be concatenated using:

* fast concatenation operator: "&"
* left trim concatenation operator: "+"
* all  trim concatenation operator: "-"
* path concatenation operator: "/"

**Example:**
```
** this is example of string concatenation
given
  @string: str := "";  //  Null String
do
  ** set string value using different operators
  alter str := "this " & "_string";  //  "this_string"
  alter str := "this " + " string";  //  "this string"
  alter str := "this " . " string";  //  "this/string"
  alter str := "this " - " "      ;  //  "this"  
done;
```

**path concatenation**

Two strings can be concatenated using concatenation operator "/" or "\\". This operator is used to concatenate "path" strings or URL locations. Notice "\\" is also escape character used for string templates.

```
given
  @string: s := "";
do  
  alter s := 'te/' / '/st'; //  "te/st" Linux
  alter s := 'te/' \ '/st'; //  "te\st" Windows
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