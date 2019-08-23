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

A class is a composite data type. It implement properties and methods required to create objects. Objects are _state machines_ that are instantiated on demand and released from memory when they are no longer needed. The most important characteristics of objects are:

* Encapsulation: each object has its own states;
* Inheritance: an object inherit its base class;
* Polymorphic: an object can play its base class role;

## Design
A class is inherited from a base class or from root class called: Object.

**simple objects**

You can create simple objects using Object default constructor notation {}:

```
variable
  Object: object_name = {attribute:value, ...};
```

One object can receive attribute names that do not exist. Default constructor will create new attributes automatic and assign the value for each. Attributes do not need to be created for default constructor. However after object is created the structure is locked: no other attributes can be added.

**complex object**

You can create more complex object using a class.

```
class ClassName(parameters) <: base_class:
  ** class local context
  ...
create
  ** call base class constructor
  forge object := base_class(object_attribute:argument,...);
  ... 
remove
  ** object release region
  ...
return;
```
**Initialization**
Objects can be declared and initialized in a single statement, or can be declared first initialize later.  Once declared an object is empty {}, it does not have attributes until it is initialized with a JSON literal or a constructor.

## Parameters 
A class can have parameters that receive values during initialization. You can define optional parameters with default values using pair notation like ( TypeName: param_name = value). Parameters can be received values using a constructor call, that is similar to a function call. Parameters can be also assigned using JSON literal/

**example**
```
given
  ** declare object from arbitrary class
  ClassName: object_name;
do
  ** create object using constructor
  forge object_name := ClassName(param:value,...);
  ...
done;
```

## Instance
The _object_ is the current instance that is created using forge or implicit constructor. Object can be initialized explicit in the creation region of the class using this syntax:

**Syntax:**
```
  inherit object := (arguments);
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
Class attributes are static and can be accessed using two scope qualifiers:

```
  object_name.class_attribute;
  ClassName.class_attribute;
```

**Class Tree**
There is a special class that has name _"@object"_ and represents the "root" class. Each classes can grow from @object or from other "base class" forming a _"class tree"_.

## Constructor
A class can have a single constructor. A constructor can use decision statements based on parameter values to create _"object"_ in different ways based on several conditions. This is a flexible constructor.

```
...
create
  when (condition) do
    forge object := base_class(some_arguments);
  else
    forge object := base_class(other_arguments);
  done;
return;
```

## Comparing objects
We can use comparison operators: "==" and "=" with objects. First comparison "==" will compare the object location. If the objects have same location they are also equal. Second compare object class and object attributes. If is the same class and all attributes are equal the objects are equivalent.

**Example:**
```
routine main():
  Integer: o,n; //  boxed  Integers
process  
  alter o := 1;
  alter n := 1; 
  
  ** equal values
  expect  (o  = n); 
  expect  not (o <> n); 
  
  ** not the same location
  expect  (o != n);     
  expect  not (o == n); 

return;
```

## Generics

A class can receive type as parameters. This allows to create generic algorithms for different data types. A similar effect can be created using variant parameters. The difference is at compile time the generic types create more efficient code.

**Generic Class:**
```
class {Generic_Type,...} Generic_Name(Generic_TypeName: parameter,...) <: Base_Class:
  ** declarations
  ...
create
  ** constructor
  ...
return;
```

**Using Generic:**
Generic class is used to define a subtype then you can declare one or more objects using alias TypeName:

```
** declare new alias type from generic
alias 
  New_Type := Generic_Class{Type_Name};

** create new object: using new alias with arguments
variable
  New_Type: object_name = {argument:value,...};

** alternative: create new object directly from generic type
variable  
  Generic_Class{Type_Name}: onject_name := {argument:value,...};

```

**Read next:** [Data Processing](processing.md)