# Database Layer

EVE include a descriptive database layer. We use native keywords to facilitate communication with mainstream relational databases. This makes EVE a versatile language for data oriented applications.

**Bookmarks:**

**definition**
* [model](#database-model)
* [record](#record) 
* [table](#table)
* [index](#index)
* [view](#view)

**processing**
* [cursor](#cursor)
* [select](#select)
* [insert](#insert)
* [update](#update)
* [delete](#delete)

## Database model

A data model is a complex data structure created with tables, columns and indexes. EVE can read database models using meta-data query and can use a model to read and update a database. This kind of application is called _data-centric_ application.

**adapter**
A data model is using a database. For this the model is connecting using adapters to a database. We import an adapter using {sqlite | oracle | pgsql} library. Each library uses API to communicate to a database. 

```
import
   $eve_lib/db/oracle:(Database);

alias Oracle := db.oracle.Database;   
```

### Connection

One application can connect to one target database that and one or more source databases. A specific kind of application called "pipeline" can pull data from sources to update target database. 

To connect to database we must use "connect" method. Once connected the data model remain in memory until we call: "disconnect". 

```
method connect(String: user, password, dbname):
  ** create a database instance
  Oracle: db;
  String: credential;
process  
  credential := user + '/' + password + '@'+ dbname;
  db.connect(credential); 
return;
```

### Structure
One database provide a structure for tables. An application can read structure and create in-memory data model. Then it can perform operations on data but not on the database structure. We do not bypass the database administrator job. 

**notes:**
1. Data structure can be created using SQL modules;
2. Data structure can be updated/modified using SQL evolution modules;
3. After database structure is updated an EVE application should recompile;
4. Data structure can be used at compile time by EVE;

### Analyze
Before using a table it must be analyzed, this is possible only if a database connection is established.

```

analyze
  -- analyze source tables
  source.*;
  source.prefix_*;
  source:(table_name,...);
  
  -- analyze target tables
  target.*;
  target.prefix_*;  
  target:(table_name,...);
```

**Note**  
* Configuration file must provide $source, $target names for databases.
* TODO: Establish credential variable names for debug time connection 
  
## Record
A record is a group of elements that are called fields or members. The elements can be native types, collections or other records. A variable can be defined based on a record type.

```
alias Record_Name: Record {field_name:type, ...};

variable
  Record_Name: variable_name;
```

### Recursive Records
An important application of recursion in computer science is in defining dynamic data structures such as lists and trees. Recursive data structures can dynamically grow to a theoretically infinite size.

```
** example of single recursive node
alias Node := Record {
                      Integer: data,   --  Integer data
                      Node: previous   -- reference to previous node
                     };
```
This kind of structure can be used to create a data chain.

```
** example of double recursive node
class Node <: Record (
  Integer: data,  --  Integer data
  Node: previous, -- reference to previous node
  Node: next      -- reference to next node
);
```
This kind of structure can be used to create a queue.

### Record usage
* A record can be used to store an entity that have attributes; 
* A record can be used as parameter into a function or method;
* A record can contain attributes of type record called nested records;
* A function can return a record variable as a result;
* A list, set or table can contain records;

### Restrictions
* Records are static structures. Once defined we can not add new fields; 
* Records can not be used until they are initialized; 

### Record literals
A record literal is enclosed in parenthesis (,,,) having elements separated by coma. Elements of a record literal are represented using pairs separated by ":" like name:value. The record literal can span one or many lines and is similar to JSON notation. 

Record literals can be used to save records in files. A list of records can be saved and can be loaded from files very fast using this human readable format. This can be a data format, but not a very efficient one though.

**Example**
```
{
  Name: "John",
  Address: {
    streetAddress: "21 2nd Street",
    city: "New York",
    state: "NY",
    postalCode: "10021-3100"
  }
}
```

### Record instance
A record instance is a variable of type record. The memory is allocated using the assignment operator “:=” The left member is the variable name and the right member is a literal or an expression that will return a record. A record can be created using constructor or record literals.

**Example:**
```
** we declare a record type  
alias Person := Record {String(32): name,  Integer: age };

method main:
  Person: person1, person2;   -- two variables of type Person
  List{Person}(10): catalog;  -- list collection of 10 Persons
process
  ** creating persons using record literals
  person1 := (name:"John", age:21);
  person2 := (name:"Vera", age:20);
  print("#s and #s are lovers." <+ (person1.name, person2.name));

  ** create an list with 10 new persons
  given:
    Integer: i := 1; 
  while (i <= 10) do
    catalog[i] := Person("John Doe", 20);
    i += 1; 
  repeat;

  ** change first person using "with...do"
  with catalog[1] do
    name := "Ispas Inca";
    age  := "17"; 
  done;
  
  print("#s is single." <+ catalog[1].name);
return;
```

**Console:**  
```
John and Vera are lovers.
Ispas Inca is single.  
```
**Observation:** 
* The catalog variable is initialized with size 10, but all its elements are void. 
* To set memory location for each element we make a clone of "person" using ":=". 


## Type Inference

It can be used to define the record using a constant literal. After first assignment the record structure is immutable. Type inference can be used only for attributes, so it is a partial inference.

```
variable
  Record: person := {name:"John", age:21};
```

## Gradual Types

We can use keyword Record to define a variable of type record with unknown structure. This is called also a week record declaration. A strong record declaration do not use type inference.

```
given
  Record: person;
do
  ** differed structure
  person:= {name:"John", age:21};
done;
```

## Tables
Tables can be stored in databases and represent collection of records. Table structure is inspected by compiler and is internally mapped to EVE syntax at run-time.

### Table design

Tables are design in a database and stored as meta-data. We do not describe tables in EVE. Instead you must declare strong record types before you can scan a table row by row. If the record do not match table structure you will receive a runtime error.

**Note:** The record for a table has restrictions: 

**restrictions**

* can not use objects;
* can not be recursive;
* can not use nested records;

**Working with tables**

* You can use tables only if you have a database connection;
* After successful connection tables are available for use; 

**Scanning tables**
You can scan one table like a collection. No need to learn anything new. The table do not have to be opened. If is opened you must close it first. Tables rows are scanned in random order. After scan table is automatically closed.

**pattern**
```
given
  ** structure of record is establish later
  Record: current_record;  -- partial declaration
scan table_name :> current_record do
  with current_record do
    ** use current_record fields
    ... 
  done;
repeat;

```

### Mutating a table
We can modify a table using current_record. First you modify record fields. Then you can call update() for each row or for a many rows. EVE is cashing the updated rows internally and it perform a bulk update. EVE flushes the buffer automatic. If you do not update() or discard() on time EVE takes implicit control. 

After update you can commit or rollback changes. EVE do not perform automatic commit. If you forget to commit the changes are lost when you close the database connection.

```
alias Class_Nme := Record {record_fields};   
  
given
  ** use introspection to declare current_record
  Class_Name: current_record;
  Class_Name: source_record := (record_literal);
scan db.table_name :> current_record do
  ** update current_record from source_record
  with (current_record, source_record) do
     current_field := source_field;
     ...
  done;
  ** update single row
  current_table.update();
repeat;
** commit all pending updates
db.commit();

```

## Data Transactions
Data model can work with transactions. We can start a transaction manually then we can make multiple modifications in the tables. After all modifications are ready we can commit or rollback changes. Notice transactions are always clean. Nobody can read data that is not committed to disk.

## Working with multiple tables
We can scan many tables in the same time. We can have nested cycles and we can decide when to update or discard changes. Nothing is saved until we apply "commit". If no commit is issued the changes are automatically committed when we close the model.

## Indexes

A table can have one or more indexes. The one index that is mandatory is the primary key index. One table that do not have a primary key can use ID as primary key. The ID is a numeric unique field starting from 0 you can create for a table to define a primary key.

**design**
For a beginner there it is difficult to understand when to create indexes. Here are 3 simple rules that can help. 

1. A leading table should have indexes for primary key and alternate unique keys;
2. A detail table should have indexes for primary key and all foreign keys;
3. Is also useful to create indexes for the most frequent search filters;

**usability**
When we use a cursor, the index is automatically used. If a join is executed and there are no index available then the operation is much slower. A good designer will optimize the database structure creating the right indexes.

## Views

Related tables can be connected using views. One tables is the lead table in a view. Other tables can have a relation 1:1, 1:M with the leading table. The view can filter data using logic expressions. View do not store data permanently. A view is read-only. You can not update data into a view. 

A data view is a query template. Having a view defined in the database can improve productivity and can protect data for unauthorized updates. In EVE a view do not have to be declared. You can use a view almost like a table.

** View Rules
* Views and tables are similar data sources;
* Views can not be updated, they are read only structures;

### Relation types
One table is the leading table. The second table must be related to the first table. View can have relation 1:1, 1:0, 1:M. If a detail table has records that do not match any leading record this relation is damaged and should be repaired. 

### Scanning a view
We can scan view using _scan_ statement. This is the most common way to access all records in a view. The _scan_ will open the view, automatically read all records and close the view. The only thing we need to do is to use the records.

``` 
given
  Record: current_record;
scan database.view_name :> current_record do  
  print (current_record);
next;
```

## Database Built In

| operation    | Description
|--------------|------------------------------
| connect()    | Connect the database
| disconnect() | Disconnect from database
| save()       | Create a save-point
| commit()     | Save transaction
| rollback()   | Rollback a transaction

## Cursor

* A cursor is special section that is based on one single select statement; 
* Cursor can return a structure that is like a record; 
* A cursor yields one record at a time on demand using fetch;

**Syntax:**
```
cursor cursor_name(parameters) <: select (
         data_type table_name.field_name,
         ...
        )
   from first_table, 
        second_table,
        ...
   join table_name.field == table_name.field, ...
  where filter_expression ...
  group by field_names,...
  order by field_names,...;  
```

**Note:**

* A cursor generate a record type described in select clause;
* One single table can be updated with a cursor: first_table;


### Cursor methods

|    Name     | Description
|-------------|-----------------------------------------
| open(args)  | open table or cursor with arguments
| fetch()     | fetch one or more records into buffer
| update()    | update current record or buffer
| discard()   | discard all modifications from buffer
| close()     | close table or cursor

**Notes:** 
* Same methods are available for a table;
* One table or view can be used as a cursor;

### Using a cursor
You can open a cursor use it then close it. You can fetch row by row from cursor. Also you can use _scan_ that is optimized using memory cache.  To improve performance you can use a "buffer" system variable. With buffer = 10 you will fetch 10 records at a time. By default the buffer is not active: buffer = 1. This have no effect for while loop.

**Syntax:**

**using fetch...**
```
cursor_name.open(arguments);
given  
  cursor_name: current_record;
while not cursor_name.finish() do
  current_record := cursor_name.fetch();
  with current_record do
     ** use record members    
    ...
  done  
done;  
cursor_name.close(); -- cursor_name is no longer available
```

**using scan**
```
#cursor.buffer := 10
given 
  cursor_name: current_record;
scan cursor_name(arguments) :> current_record  do
  with record_name do
    -- use record fields
    ... 
  done;
next;
print #cursor.fetched; 
```

**Notes:** 

* DML statements are terminated by ";" this is mandatory;
* You can use aggregate functions specific to database;
* You can use database stored functions in SQL;
* You must use EVE operators for filter expressions and join; 
* You can not use EVE functions in SQL calls; 
* You can use EVE variables in SQL using notation {variable_name}
* You can use EVE unpacking and template operator {} <+ (variable_list) 

**Query Options**

* Clause join, where, order by and group by are optional; 
* You can capture resulting rows into a collection of records using +>; 
* You can capture one single row into a record variable;
* Limit N will retrieve several rows and will stop;
* Offset will start returning rows after a specific number of records; 
* You can use pagination technique to report search results; 
* Notice offset can increase the response time;

We can use group by to calculate aggregate functions: sum(), average(), count(), maxim(), median(), minim(). These functions are translated to SQL dialect. We parse the statement and convert to SQL before we sent it to the database for execution.

## Insert statement

To create new data we have two options: Insert data or Append data. In standard SQL there is no append statement but for performance we also use append statement to create new rows into a data table faster. 

**One row:**
```
insert in table_name (field_name:value,...);
append to table_name (field_name:value,...);
```

**Note:** Unlike the classic SQL we use pair operator (':') to have improved readability.

**One record:**
```
insert in table_name <+ record_name;
append to table_name <+ record_name;
```

**Multiple rows:**
```
append to table_name
  select (field_target:field_source, ...)
  from src := table_source,...
  join join_expression
  where filter_expression;
```

**From collection:**
```
insert in table_name <+ record_collection;
append to table_name <+ record_collection;
```

## Update
Update statement is part of DML language. EVE statement for update is a little bit different from the standard SQL. We can do single record update or multi record update in bulk using a combination with select statement.

**Syntax:**

1. Single table update:
```
update table_name (field_name:eve_variable,...) <+ #global
 where filter_condition;
```

2. Use Record variable:
```
update table_name (table_field:record_field...) <+ eve_record
 where filter_condition;
```
**note:** In the where_condition we can use fields from record variable.

3. Use all fields from EVE record variable:
```
update table_name <+ eve_record
 where filter_condition;
```
**note:** In the where_condition we can use fields from record variable.

4. Use all fields from a record collection:
```
update table_name <+ record_list;
```
**note:**  You can not use where with list of records.

5. Join tables for update:
```
update target (target.field_name:source.field_name,...)
  from source
  join source.field_name = target.field_name
 where filter_condition;
```
**note:** 
* you can not use outer join =+ for update. 
* this can generate null values or to many records. 

6. Using sub-query:
```
update target (target.field:source.field,...)
  from source = 
     (select list_of_fields 
        from source_tables
       where search_condition)
  where filter_condition <+ eve_source;
```

filter_condition ::= field_name op {eve_variable}
filter_condition ::= {eve_variable} op field_name 
op ::= {=, <=, >=}



**note:** 
* In this query, search_condition can include fields from target_table;
* Filter expression is referring to target table;
* Composite filter conditions are available using logic operators: {and, or, not}.

## Delete

This statement will remove one or more records from a table. 
We can specify what records using search condition. 

**Syntax**

1. Using search condition
```
delete 
  from table_name 
 where search_condition;
```
**Note:** search condition can use EVE operators and EVE variables.

2. Using sub-query
```
delete from table_name 
 where field_name in 
   (select source_field
      from source_table 
     where search_condition);
```

3. Using list unpacking
```
delete from table_name 
 where field_name <+ eve_list;
```

## SQL Execution

SQL Is declarative language. Behind the scene we generate complex code that is dynamically created and executed. For debug purpose we enable introspection using global variables: #query, #cursor. 

* Before execution the statement is converted into SQL string. 
* We can visualize this string by using: #query.sql to debug the application. 
* Also we can use #query.count to see how many records are inserted. 
* After insert/append we need to issue db.commit or else the modifications are lost.

### Global Properties
SQL and DML statement will inject properties into global object called: #query. We can interrogate properties of #query after last DML statement. Also #cursor is providing information about last used cursor. 

**last query**
* #query.count; 
* #query.plan; 
* #query.sql;
* #query.updated; 
* #query.deleted; 

**last cursor**
* #cursor.status; 
* #cursor.plan; 
* #cursor.sql;
* #cursor.updated; 
* #cursor.fetched; 
* #cursor.finish; 

## SQL Generator
The adapters will allow direct communication between EVE application and target database. EVE can generate specific SQL code from source database and convert data structure to the target database. This code is dynamically created and can be spool-out using SQL introspection.

TODO: Define built-in SQL generator

## Data Communication
An EVE application can communicate with external world using JSON. Once a database model is designed we can create an interface for a model to read/write data using JSON data blocks that can transfer one or more records over TCP-IP protocol. This communication is transparent to EVE users. It is used by database adapters.


**Targeted Databases:** {
[PostgreSQL](http://www.postgresql.org/), 
[Oracle](http://www.oracle.com/), 
[MySQL](https://www.mysql.com/)
}

**Read next:** [Standard Library](standard-lib.md)