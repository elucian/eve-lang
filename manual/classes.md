## Object Oriented

EVE language is using single inheritance similar to Java.

**bookmarks**

* [concept](#concept)
* [design](#design)
* [parameters](#parameters)
* [instance](#instance)
* [attributes](#attributes)
* [constructor](#constructor)
* [generics](#generics)
 
## Concept

A class is a smart composite data type. It implement properties and methods required to create objects. Objects are _state machines_ that are instantiated on demand and released from memory when they are no longer needed. The most important characteristics of objects are:

* Encapsulation: each object has its own states;
* Inheritance: an object inherit its base class;
* Polymorphic: an object can play its base class role;

## Design
A class is inherited from a base class or from root class called: Object.

**pattern:**
```
class class_name(parameters): base_class
  ** object attributes
  ...
static
  ** class attributes  
  ...
create
  ** object initialization  
  object := base_class();
  ... 
discard
  ** object release region
  ...
return;
```

## Parameters 
A class can have parameters that receive values during object initialization. You can define optional parameters with default value using assignment (param_name := value). Native type parameters are pass by value, composite types and objects are pass by reference.

**example**
```
given
  ** declare object from arbitrary class
  class_name: object_name;
do
  ** create object 
  object_name := class_name(param:value,...);
  ...
done;
```

## Instance
The "object" is the current instance that is created explicit.  It is initialized in class constructor and is visible in all methods of the class. In the creation region _object_ must be initialized from base class. In Java language current "object" is called "this". I have chosen "object" instead. You can not use this name for something else.

**Syntax:**
```
  object := base_class(arguments);
```

**Note:** 
* In Java you must use "new" to create an object;
* EVE use := to create a new object using class name to call class constructor.

## Attributes

A class can have object attributes and class attributes.

* We declare object attributes in default region after base_class;
* We declare class attributes after keyword: static;

**Object attributes**

To access object attributes we can use dot notation:

```
  object_name.object_attribute;
```

**Class attribute**
Class attributes are static and can be accessed using two qualifiers:

```
  object_name.class_attribute;
  class_name.class_attribute;
```

**Class Tree**
There is a special class that has name _"Object"_ and represents the "root" class. Each classes can grow from Object or from other "base class" forming _"class tree"_.

## Constructor
A class can have a single constructor. A constructor can use decision statements based on parameter values to create _"object"_ in different ways based on several conditions. This is a smart constructor.

```
...
create
  when (condition) do
    object := base_class(some_arguments);
  else
    object := base_class(<other_arguments>);
  done;
return;
```

**Initialization**
Objects can be declared and initialize in a single statement using operator ":=" with constructor or can be declared first using "<:" and initialize later using operator ":=" with the constructor call. 

## Comparing objects
We can use comparison operators: "==" and "=" with objects. First comparison "==" will compare the object location. If the objects have same location they are also equal. Second compare object class and object attributes. If is the same class and all attributes are equal the objects are equivalent.

**Example:**
```
method main():
 Integer: o,n; -- boxed integers
process  
  o := 1;
  n := 1; 
  ** expectations
  expect  (o  = n) -- equivalent  
  expect !(o == n) -- not the same 
return;
```

## Generics

A class can receive type as parameters. This allows to create generic algorithms for different data types. A similar effect can be created using variant parameters. The difference is at compile time the generic types create more efficient code.

**Generic Class:**
```
class [Generic_Type,...] Generic_Name (parameter:Generic_Type,...) <: Base_Class
  ** declarations
create
  ** constructor
return;
```

**Using Generic:**
Generic class is used to define a subtype then you can declare one or more instance of the new type

```
** create new object from generic
type new_type <: Generic_class[generic_type];

```

**Read next:** [Data Processing](processing.md)