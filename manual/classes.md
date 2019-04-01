## Object Oriented

EVE language using single inheritance OOP paradigm similar to Java.
 
## Class Section

A class is smart composite data type. It implement properties and methods required to create objects. Objects are _state machines_ that are instantiated on demand and released when they are not needed any longer. The most important characteristics of objects are:

* Encapsulation: each object has its own states;
* Inheritance: an object inherit its base class;
* Polymorphic: an object can play its base class role;

## Conceptual Design
Classes are derived from a single base class that is the root Class. To design more complex classes developers can use mix-ins. That is a larger class with properties having as type other classes. 

**syntax:**
```
class[(<generic_types>)] <class_name>(<parameters>) <: <base_class>
  -- define attributes
  <attributes>
setup:
  object := <base_class>(); -- object initialization  
  ... 
scrap:
  <object_dispose_region> 
over;
```

## Arguments
A class can have parameters used for object initialization declared in "receive" region. We can define optional parameters with default value using assignment (param_name := value). Parameters are pass by value except implicit references and variants that are pass by reference.

**example**
```
given
  -- declare object
  <object_name> ∈ <class_name>;
begin:
  -- create object 
  <object_name> := <class_name>(<param>:value[,<param>:value]...);
  ...
ready;
```

## Instance _object_
The "object" is the current instance that is created.  It is visible in class constructor and all methods of the class. In the creation region _object_ must be initialized from base class;

**Syntax:**
```
setup
  object := <base_class>(<arguments>);
```

## Declaration regions
Between symbol ":" and keyword "create" there are 3 declaration regions. 

1. default - start immediate after :<base_class>; 
1. private - for private object properties;
1. public  - for public object properties;

* We declare class attributes in default region;
* Class attributes are static and public for all instances;
* We can use object name or class name as dot qualifier to access these attributes;

**Class Attribute**
```
  <class_name>.<class_attribute>;
```

**Object Attributes**
```
  <object_name>.<object_attribute>;
```

## Class Tree
There is a special class that has name _"Class"_ and represents the "root" class. Each classes can grow from Class or from other "base class" forming _"class tree"_.

## Constructor
A class can have a single constructor. A constructor can use decision statements based on parameter values to create _"object"_ in different ways based on several conditions. This is a smart constructor.

```
...
setup
  when <condition>:
    object := <base_class>(<some_arguments>);
  else:
    object := <base_class>(<other_arguments>);
  ready;
over;
```

## Object Initialization
Objects can be declared and initialize in a single statement using operator ":=" with constructor or can be declared first using "∈" and initialize later using operator ":=" with the constructor call. 

## Comparing objects
We can use comparison operators: "=" and "≡" with objects. First comparison "=" will compare the object location. If the objects have same location they are also equal. Second compare object class and object attributes. If all attributes are equal and have same base class the objects are equivalent.

**Example:**
```
aspect main:
  o,n ∈ Integer;    
  o := 1; 
  n := 1; 
  when o = n then
    print("o and n objects are the same"); --> unexpected
    fail;
  else:
    print("n and o are not the same"); -->expected
  ready;
  -- verify
  expect  (o ≡ n); -- equivalent  
  expect !(o = n); -- not the same 
over;
```

## Generic Class

A class can receive <generic_types> parameters. This allows to create generic algorithms for different data types. A similar effect can be created using variant parameters. The difference is at compile time the generic types create more efficient code.

**Generic Class:**
```
class (<Generic_Parameters>) GenericName(<parameters>) <: Class:
```

## Using Generic Type
Generic class is used to define a subtype then you can declare one or more instance of the new type:
```
-- create new type from generic
<new_type> <: <generic_class> of <type>;

```

**Read next:**[Exceptions](exceptions.md)