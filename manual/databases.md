# Database Layer

EVE include a descriptive database layer. We use native keywords to facilitate communication with mainstream relational databases. This makes EVE a versatile language for data oriented applications.

**Bookmarks:**

**definition**
* [model](#model)
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

## Model

A data model is a complex data structure created with tables, columns, indexes and views. One application can store and query data from these structures. This kind of application is called _data-centric_ application. EVE-PY can use a database engine using data models.

### Signature
A model has a version (signature) that belong to database where the data is stored. If the signature do not match the connection to the model fails. Connection specify the signature. We can check the signature of a model before connection is successful.

### Driver
We can define a data model is a special module that import one driver: { sqlite, oracle, pgsql }. Each driver define a Database. Tables, indexes and views are defined as members of this module. A module can define also types, classes and executable subroutines for data access. 

### Implementation
A data model is using a database. For this the model is connecting using drivers to a database. We import a driver using {sqlite |oracle |pgsql} library. Each library uses API to communicate to a database. Database need to be created before use. 

### Importing models
One application can connect to one or more models. Once connected the model members can be used to communicate with the database. A model must be "imported" like any other module and can be used with "from" to eliminate model prefix.

```
import
   from <model_name> use <list_of_members> | all;
```

## Connection

One application can connect to a database that is current database or default database and one or more source databases. A specific kind of application called "pipeline" can pull data from sources to update current database with new data. 

To connect to database we must use "connect" command. This command can be implemented as method or function in the model and must be exported. Once connected the instance of the model remain in memory until we call: "disconnect". 

```
method connect(credential:String):
  db:=Database(credential, signature); -- create a database instance
over;
```

Connection will trigger an error if module.version literal do not match database internal signature. To fix this error programmer must fix the database internal signature or the model signature. This is a feature implemented in the language to force users to sign database models.

## Structure
Each model define structure for one or several related tables. Tables have a flat data structure. Each filed in a table is related to one significant field that identify an entity with its indivisible attribute. For each table we create search indexes in a database to improve performance.  

Current database provide a structure of tables. An application can perform operations on data but not on the data structure. We do not bypass the database administrator job. To create the model in the database a database administrator can do one of two things:

1. Create structure with SQL scripts;
2. Create structure manually;

## Record
A record is a group of elements that are called fields or members. The elements can be native types, collections or other records. A variable can be defined based on a record type.

```
define
  <record_type> :(<member_name>:<type>, ...) <: Record;

define  
  <var_name> ∈ <record_type>;
```

### Recursive Records
An important application of recursion in computer science is in defining dynamic data structures such as lists and trees. Recursive data structures can dynamically grow to a theoretically infinite size.

```
-- example of single recursive node
define
   Node <: Record of
   ( 
     data: Integer,  --integer data
     previous: Node  --reference to previous node
   );
```
This kind of structure can be used to create a stack.

```
-- example of double recursive node
define
   Node <: Record of
   (
     data: Integer,  --integer data
     previous: Node, --reference to previous node
     next: Node      --reference to next node
   );
```
This kind of structure can be used to create a queue.

### Record usage
* A record can be used to store an entity that have attributes; 
* A record can be used as parameter into a function or over;
* A record can contain attributes of type record called sub-records;
* A function can return a record variable as a result;
* A array  or a matrix can contain a collection of records;
* A record can contain references to Arrays and matrices;

### Restrictions
* Records are static structures. Once defined we can not add new fields; 
* Records can not contain Arrays and matrices but can contain references to them;
* Records can not be used until they are initialized using default constructor or literal; 

### Record literals
A record literal is enclosed in parenthesis (,,,) having elements separated by coma. Elements of a record literal are represented using pairs separated by ":" like name:value. The record literal can span one or many lines and is similar to JSON notation. 

Record literals can be used so save records in files. A array  of records can be saved and can be loaded from files very fast using this format and is human readable. So I guess this can be a data format, but not a very efficient one.

**Example**
```
(
  Name: "John",
  Address: (
    streetAddress: "21 2nd Street",
    city: "New York",
    state: "NY",
    postalCode: "10021-3100"
  )
)
```

### Record Instance
A record instance is a variable of type record. The memory is allocated using the assignment operator “:=” The left member is the variable name and the right member is a literal or an expression that will return a record. A record can be created using constructor or record literals.

**Example:**
```
-- we declare a record type  
define
  Person <: Record of (name:String(32), age:Integer );

method main:
  person1,person2 ∈ Person;   -- two variables of type Person
  catalog ∈ Array(10) of Person; -- a collection of Persons

  -- creating persons using record literals
  person1 := (name:"John", age:21);
  person2 := (name:"Vera", age:20);
  print("#s and #s are lovers." <+ (person1.name, person2.name));

  -- create an array with 30 new persons
  given:
    i ∈ Integer;
  while i ≤ 10 do
    catalog[i] := Person("John Doe", 20);
    i += 1; 
  while;

  -- change first person using "with...do"
  with catalog[1] set
    name := "Ispas Inca";
    age  := "17"; 
  with;
  
  print("#s is single." <+ catalog[1].name)
over;
```

Console:  
```
John and Vera are lovers.
Ispas Inca is single.  
```
**Observation:** The catalog variable is initialized with size 10, but all its elements are void. 
To set memory location for each element we use a do and make a clone of "person" using ":=". 
We do not use ":=?" if we do all elements shall point to the same location and this is a mistake.


## Type Inference

It can be used to define the record using a constant. After first assignment the record structure is immutable;

```
global
  person := (name:"John", age:21);
```

## Gradual Types

We can use keyword Record to define a variable of type record with unknonw structure;

```
given:
  person ∈ Record;
begin:
  -- differed structure
  person:= (name:"John", age:21);
ready;
```

## Tables
Tables can be stored in databases and represent collection of records. Tables are predefined generic classes that can be used to mirror the database structure in memory for processing.

### Table Structure

 Elements of a table are records. We can declare the record type first than the table or declare the Table with the record descriptor in a single statement. 

**pattern**
```
define
  <table_name> <: Table of
  (
     <filed_name>:<data_type>,
     <filed_name>:<data_type>,
     ... 
  )
  key (<field_name>[,<field_name>]...);
```

The record for a table has restrictions: 

**restrictions**

* can not use pointers; 
* can not use objects;
* can not be recursive records;
* can not use nested records;

### Table Belonging
A table belong to a data model. 

### Table Built-in

|    Name     | Description
|-------------|--------------------------------------
| status()    | open, closed, absent, modified
| create()    | create a table if is absent
| open()      | open table for reading or writing
| close()     | close table and set status:=closed
| current()   | read current record
| next()      | read next record and set-current
| append()    | create one new record and set it current
| delete()    | remove specified record from table
| clear()     | remove all records from table
| update()    | save current record modifications
| discard()   | discard current record modifications
| find()      | search one specific record using key and set current
| end()       | return True or False. Is this last record?

### Working with tables
We can open tables only if we first connect to a data model. After successful connection tables are available for use. We can check if a table exist using status(). If a table do not exist we can create the table using create(). We can not open a table that does not exist. 

**Scanning a table**
We can scan tables using for...do like a normal collection. No need to learn anything new. The table do not have to be opened manually and is automatically closed when do is ending. This is the best way to scan a table. Tables are scan in random order.

**Example:**
```
for <record_name> ∈ <table_name> do
  ... --use <record_name>
for;
```
### Opening a table
We can open a table using open() built-in. We can use option { READ, WRITE } that are specially defined for open mode. To open a table under the hood we create a cursor. Cursors can be read one record at a time or multiple records at once.

**Using while**
We can open a table and traverse the table step by step using do. This operation is called full table scan. This can be useful to read all records from a table and perform operations record by record. 

**pattern**
```
table_name.open(READ); 
given:
  --use introspection to declare current_record
  current_record ∈ table_name.record(); 
while ⊤ do
  fetch table_name to current_record;
  with current_record map
    --use current_record fields
    ... 
  with; 
  done if table_name.end();
while;
table_name.close();
```

### Mutating a table
We can modify a table using current_record. This is a record created using the for...in do or a record created with fetch method. The record has "rowid" inside that can be used to create database update SQL.

```
map <current_record> to <source_record> set
   <current_field>:<source_field>;
   ...
map;
<current_table>.update();
```

## Data Transactions
Data model can work with transactions. We can start a transaction manually then we can make multiple modifications in the tables. After all modifications are done we can commit or rollback changes. Notice transactions are always clean. Nobody can read data that is not committed to disk.

## Working with multiple tables
We can scan many tables in the same time. We can have nested cycles and we can decide when to update or discard changes. Nothing is saved until we apply "commit". If no commit is issued the changes are automatically committed when we close the model.

## Learning how to fetch
To learn more about _fetch_ look at the view examples. You can use a similar approach for a table. 
Fetching multiple records into a cache can be useful if you wish to analyze a group of records back and forward or improve the performance.


## Index

A table can have one or more indexes. The one index that is mandatory is the primary key index. One table that do not have a primary key can use ID as primary key. The ID is a numeric unique field starting from 0 we can create for a table to define a primary key.

We use _define_ region to define indexes in database structure. These indexes can be generated automatically by the compiler using code generator. One database structure can be verified to have all indexes active and ready.

```
define
  <index_name>(<table_name>) <: Index of (<field_name>[,field_name] ...);
```

### Create indexes
Indexes are declared inside a model and are private. We do not use indexes, the database driver does. 
The only purpose of declaring indexes is to create them inside the database. We can generate scripts to create indexes and that is it. We do not use indexes in program but the database will do.

### Using indexes
When we use a view, the index is automatically used. If a join is executed and there are no index available then the operation is much slower. A good designer will optimize the database structure creating the right indexes.

### Index advice
For a beginner there it is difficult to understand when to create indexes. Here are 3 simple rules that can help.

1. A leading table should have indexes for primary key and alternate unique keys;
2. A detail table should have indexes for primary key and the foreign keys;
3. Is also useful to create indexes for the most frequent search filters;

## Views

Tables can be connected using views. One tables is the lead table. Other tables can have a relation 1:1, 1:M with the leading table. The view can filter data using logic expressions. View do not store data permanently. A view is read-only, we can not update data into a view. 

A data view is a query template. Having a view defined can improve productivity. We  _declare_ the view structure inside the data model. We can use a view to read database information or to create a select statement using view like a read-only table.

**View Example:**
```
define
  view_name <: View of (
    filed_name:<type>,
    filed_name:<type>,
    ...
   )
   from <table_name> [as alias][,<table_name>] ...
   [join  <join_expression>]   
   [where <filter_expression>]
   [order by <field_name>];
```

### View Rules
* Tables can have alias that are internal to the view;
* You specify a list of fields, each field can be qualified with table alias;
* Table in view are connected using join relations (:=, =+);
* Views can not be updated, they are read only structures;
* Views are created inside databases, therefore EVE variables can not be used in views;

### Relation types
One table is the leading table. The second table must be related to the first table. View can have relation 1:1, 1:0, 1:M. If a detail table has records that do not match any leading record this relation is damaged and should be repaired. 

### Join symbols
* We use: := for relations 1:1 and 1:0. 
* We use: =+ for relation 1:M

### Scanning a view
We can scan view using for...do. This is the most common way to scan all records in a view. The scan will open the view, automatically read all records and close the view. The only thing we need to do is to use the record.

``` 
for <current_record> ∈ <view_name> do  
  print (<current_record>);
for;
```

## Database Built In

| operation    | Description
|--------------|------------------------------
| connect()    | Connect the database
| disconnect() | Disconnect from database
| start()      | Start transaction
| commit()     | Save transaction
| rollback()   | Rollback a transaction
| verify()     | Verify data structure
| reset()      | Remove all tables
| clear()      | Remove data from all tables

## Data Communication
A EVE application can communicate with external world using JSON. Once a database model is designed we can create an interface for a model to read/write data using JSON data blocks that can transfer one or more records over TCP-IP protocol.

## SQL Generator
To communicate to other databases EVE can interact with Python drivers. For this we will create a bridge. The bridge layer will allow direct communication between EVE-PY application and target database to store: Tables and Indexes. We will create and SQL Generator that can create SQL statements for: database creation and database alteration from one version to next version. One data model can be stored into a single database user. 

**Targeted Databases:** {
[PostgreSQL](http://www.postgresql.org/), 
[Oracle](http://www.oracle.com/), 
[MySQL](https://www.mysql.com/)
}   

**Read next:** 
[cursor](cursor.md),
[table](table.md)

## Cursor

A cursor is special section that is based on one single select statement. 
Cursor can return a structure that is a record or a table row_type. 
A cursor is equivalent to a generator. It yields one record at a time on demand using fetch.

**Syntax:**
```
cursor <name>(<params>) : <record_type> is
  <select_statement>
cursor;
```

### Using a cursor
A cursor can be open, fetch and closed. This can be done also using _for_ do. 
We can fetch row by row or in bulk for several rows or all rows. This may be too much if the data set is very large. 

**Syntax:**

**using fetch...**
```
<cursor_name>.open(<arguments>);
fetch <cursor_name> to <record_variable>;
fetch <cursor_name> to <list_of_records> [limit N];
<cursor_name>.close;
```
**using for do...**
```
for <record_name> ∈ <cursor_name> do
  with <record_name> map
     ... --use record fields
  with;
for;
```

## Select

This keyword comes from SQL. 
EVE is a language used for learning therefore we try to implement a kind of Query language 
to enable beginners to get familiar with this language. 
However there are some deviations from standard SQL to improve upon language consistency with EVE dialect.

**Syntax:**
```
select (<fields>) into [collection|record] 
  [limit N] [offset M]
  from <table>|<view> [as <alias>][,<table>]...
  join   by <field := field> | <field =+ field>
  filter by <filter_expression> [and <filter_expression>] ...
  order  by <field_name>[,<field_name>] ...
  group  by <field_name>;
```

**Notes:** 

* The syntax is not specific to any database. 
* We use EVE operators for filter_expressions and for joins. 
* We can not use user defined functions in select statements. 
* We can use only aggregate functions specific to databases.

**Query Options**

* Join, where, order by and group by are optional. 
* We can capture resulting rows into a collection of records. 
* We can capture one single row into a record variable.
* Limit N will retrieve several rows and will stop. 
* Offset will start returning rows after a specific number of records. 
* We use this technique to paginate into a search. 
* Notice offset can increase the response time.

We can use group by to calculate aggregate functions: sum(), average(), count(), maximum(), median(), minimum(). These functions are translated to SQL dialect automatically. We parse the statement and convert to SQL before we sent it to the database for execution.

### Select Usability
We use select to create a query. We can define in-line query or associate a query to view or to cursor. 
We can create instant cursor using for...in <query> do to avoid cursor definition. 
This is best when the cursor is used a single time.

Select statement will inject properties into a built-in implicit object called: query. 
We can interrogate properties of query after last select statement. 
For example: query.count, query.plan, query.sql (return sql string for debugging).

## Insert statement

To create new data we have two options: Insert data or Append data. 
In standard SQL there is no Append statement so we stick with SQL and use "insert" keyword to create new rows into a data table. 

**One row:**
```
insert into <table> (<field>:value[,<field>:value] ...);
```
**One record:**
```
insert into <table> from <record_name>;
```

**Note:** Unlike the classic SQL we use pair operator (':') to have improved readability.

**Multiple rows:**
```
insert into <table>
  select (<field> as field, <field> as <field>)
  from <table>[,<table>]...
  [join...]
  [where ...];
```

**From collection:**
```
insert into <table>
  select (<field> as field, <field> as <field>)
  from <list of records>;
```

## SQL Execution

* Before execution the statement is converted into SQL string. 
* We can visualize this string by using: query.sql to debug the application. 
* Also we can use query.count to see how many records are inserted. 
* After insert statement we need to issue db.commit or else the modifications are rolled back.


## Sage Code
As a reminder the standard insert statement ins SQL looks like this:

```
insert into <table> 
  (field, field, field ...) 
values
  (value, value, value ...)
```

When the list of fields is large then the mapping between the field name and the value is very difficult to read. You have to count the number of comas to be sure. In EVE we have change this to map immediately a value to a name using ":" pair up operator like we use in record literals.

## Update
Update statement is part of DML language in SQL. EVE statement for update is a little bit different from the standard SQL. However we use keyword update and we can do single record update or multi 
record update in bulk using a combination with update and select statement.

**Syntax:**

1. Single table update:
```
update <table_name> set (field_name:expression[,field_name:expression]...)
  where <filter_condition>;
```
**note:** expression can be a constant value or a simple operation supported by the database. 
It can contain local variables that are directly inserted into SQL.

2. Use Record variable:
```
update <table_name> set (table_field:record_field[,table_field:record_field]...)
  from <record_variable> 
  where <filter_condition>;
```
**note:** In the filter_condition we can use fields from record variable.

3. Use all fields from a record variable:
```
update <table_name> 
  from <record_variable> 
  where <filter_condition>;
```
**note:** In the filter_condition we can use fields from record variable.

4. Use all fields from a record collection:
```
update <table_name> 
  from <list_of_records> 
  where <filter_condition>;
```
**note:** In the filter_condition we can use fields from record variable.

5. Join tables for update:
```
update target_table [as <target>] set (field_name:value[,field_name:value])
  from source_table [as <source>]
  join source.field_name := target.field_name;
```
**note:** you can not use outer join =+ to update. 
This can generate null values or to many records. 
It is going to be translated to left join.

6. Using sub-query:
```
update target_table [as <target>] set (field_name:value[,field_name:value])
  from (select (<list_of_fields>) 
        from <source_tables>
        join <join_relations>
        where <search_conditions>) as <alias>
  where <filter_condition>;
```
**note:** In this query, search_condition can include fields from target_table.

## Execution
Update statement is executed immediate. We can execute a statement once or many times into a do. 
After several modifications we can issue db.commit. If we do not commit changes will not be saved. 
An automatic commit will be done when we close the database. It is better to do a rollback or commit before we do so.

After execution we can use _"query"_ object to check the status of last update command. 
Some interesting attributes can be: query.updated, query.sql. We can use this to debug the program in  of errors.

## Delete

This statement will remove one or more records from a table. 
We can specify what record using primary key or a filter condition. 

**Syntax**

1. Using search condition
```
delete from <table_name> where <search_condition>;
```
**Note:** search condition can use EVE operators and EVE variables.

2. Using sub-query
```
delete from <table_name> where 
   <field_name> in (select field_name from <table> where <search_condition>);
```

3. Using in operator
```
delete from <table_name> where 
   <field_name> in (set_of_variables);
```

**Read next:**[Standard Library](standard-lib.md)