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

A data model is a complex data structure created with tables, columns and indexes. One application can store and query data from these structures. This kind of application is called _data-centric_ application.

### Signature
A model has a version (signature) that belong to database where the data is stored. Connection verify the signature. We can check the signature of a model before connection is successful. If the signature do not match the model connection is invalid. 

### Database adapter
We can define a data model is a special module that import one adapter: { sqlite, oracle, pgsql }. Each adapter define a Database. Tables and index types are defined as members of this modules. A module can define also classes and executable subroutines for data access. 

### Implementation
A data model is using a database. For this the model is connecting using adapters to a database. We import an adapter using {sqlite |oracle |pgsql} library. Each library uses API to communicate to a database. Database need to be created before use. 

### Importing models
One application can connect to one or more models. Once connected the model members can be used to communicate with the database. A model must be "imported" like any other module and can be used with "from" to eliminate model prefix.

```
import
   from <model_name> use <list_of_members> | all
```

## Connection

One application can connect to a database that is target database or default database and one or more source databases. A specific kind of application called "pipeline" can pull data from sources to update target database with new data. 

To connect to database we must use "connect" command. This command can be implemented as method or function in the model and must be exported. Once connected the instance of the model remain in memory until we call: "disconnect". 

```
method: connect(String: credential)
  ** create a database instance
  mySQL.Database: db 
process  
  db := mySQL.Database(credential, signature) 
return
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
  type: record_type <: Record (member_name:type, ...)

global
  record_type: var_name
```

### Recursive Records
An important application of recursion in computer science is in defining dynamic data structures such as lists and trees. Recursive data structures can dynamically grow to a theoretically infinite size.

```
** example of single recursive node
define
   type: Node <: Record ( 
     Integer: data,   ** integer data
     Node: previous   ** reference to previous node
   )
```
This kind of structure can be used to create a stack.

```
** example of double recursive node
define
   type: Node <: Record (
     Integer: data,  ** integer data
     Node: previous, ** reference to previous node
     Node: next      ** reference to next node
   )
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
** we declare a record type  
define
  type: Person <: Record (String(32): name:, Integer: age )

method: main()
  Person: person1,person2     ** two variables of type Person
  Array[Person](10): catalog  ** a collection of Persons
process
  ** creating persons using record literals
  person1 := (name:"John", age:21)
  person2 := (name:"Vera", age:20)
  print("#s and #s are lovers." <+ (person1.name, person2.name))

  ** create an array with 30 new persons
  given:
    Integer: i
  while (i <= 10) do
    catalog[i] := Person("John Doe", 20)
    i += 1 
  repeat

  ** change first person using "with...do"
  with catalog[1] do
    name := "Ispas Inca"
    age  := "17" 
  ready
  
  print("#s is single." <+ catalog[1].name)
return
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
  Record: person := (name:"John", age:21)
```

## Gradual Types

We can use keyword Record to define a variable of type record with unknonw structure;

```
given
  Record: person
begin
  ** differed structure
  person:= (name:"John", age:21)
ready
```

## Tables
Tables can be stored in databases and represent collection of records. Tables are predefined generic classes that can be used to mirror the database structure in memory for processing.

### Table Structure

 Elements of a table are records. We can declare the record type first than the table or declare the Table with the record descriptor in a single statement. 

**pattern**
```
global
  Table: table_name[
     data_type : filed_name,
     ... 
  ]
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
scan record_name <+ table_name do
  ** use record_name
  ... 
next;
```
### Opening a table
We can open a table using open() built-in. We can use option { READ, WRITE } that are specially defined for open mode. To open a table under the hood we create a cursor. Cursors can be read one record at a time or multiple records at once.

**Using while**
We can open a table and traverse the table step by step using do. This operation is called full table scan. This can be useful to read all records from a table and perform operations record by record. 

**pattern**
```
table_name.open(READ) 
given
  ** use introspection to declare current_record
  Record: current_record   
scan current_record <+ table_name do
  with current_record do
    ** use current_record fields
    ... 
  ready 
repeat
table_name.close()
```

### Mutating a table
We can modify a table using current_record. This is a record created using the for...in do or a record created with fetch method. The record has "rowid" inside that can be used to create database update SQL.

```
map current_record to source_record do
   current_field := source_field
   ...
ready
<current_table>.update()
```

## Data Transactions
Data model can work with transactions. We can start a transaction manually then we can make multiple modifications in the tables. After all modifications are ready we can commit or rollback changes. Notice transactions are always clean. Nobody can read data that is not committed to disk.

## Working with multiple tables
We can scan many tables in the same time. We can have nested cycles and we can decide when to update or discard changes. Nothing is saved until we apply "commit". If no commit is issued the changes are automatically committed when we close the model.

## Learning how to fetch
To learn more about _fetch_ look at the view examples. You can use a similar approach for a table. 
Fetching multiple records into a cache can be useful if you wish to analyze a group of records back and forward or improve the performance.


## Index

A table can have one or more indexes. The one index that is mandatory is the primary key index. One table that do not have a primary key can use ID as primary key. The ID is a numeric unique field starting from 0 we can create for a table to define a primary key.

We use _define_ region to define indexes in database structure. These indexes can be generated automatically by the compiler using code generator. One database structure can be verified to have all indexes active and ready.

```
global
  Index: index_name(table_name) <: (<field_name>[,field_name] ...)
```

### Create indexes
Indexes are declared inside a model and are private. The only purpose of declaring indexes is to create them inside the database. We can generate scripts to create indexes and that is it. We do not use indexes in program but the database will do.

### Using indexes
When we use a cursor, the index is automatically used. If a join is executed and there are no index available then the operation is much slower. A good designer will optimize the database structure creating the right indexes.

### Index design
For a beginner there it is difficult to understand when to create indexes. Here are 3 simple rules that can help. 

1. A leading table should have indexes for primary key and alternate unique keys;
2. A detail table should have indexes for primary key and all foreign keys;
3. Is also useful to create indexes for the most frequent search filters;

## Views

Tables can be connected using views. One tables is the lead table. Other tables can have a relation 1:1, 1:M with the leading table. The view can filter data using logic expressions. View do not store data permanently. A view is read-only, we can not update data into a view. 

A data view is a query template. Having a view defined can improve productivity. We  _declare_ the view structure inside the data model. We can use a view to read database information or to create a select statement using views as read-only table.

**View Example:**
```
global
   View: view_name [
            field_type: filed_alias = alias.field_name,
            ...
         ]
   from alias = table_name ,...
     join  join_expression   
     where filter_expression
     order by field_alias
```

### View Rules
* Tables can have alias that are internal to the view;
* You specify a list of fields, each field can be qualified with table alias;
* Table in view are connected using join relations (==, =+)
* Views can not be updated, they are read only structures;
* EVE variables and functions can not be used in views;

### Relation types
One table is the leading table. The second table must be related to the first table. View can have relation 1:1, 1:0, 1:M. If a detail table has records that do not match any leading record this relation is damaged and should be repaired. 

### Join symbols
* We use: == for relations 1:1 and 1:0. 
* We use: =+ for relation 1:M

### Scanning a view
We can scan view using _scan_ statement. This is the most common way to access all records in a view. The _scan_ will open the view, automatically read all records and close the view. The only thing we need to do is to use the records.

``` 
given
  Record: current_record
scan current_record <+ view_name do  
  print (current_record)
scan
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
To communicate to other databases EVE can interact with external drivers. For this we will create adapters. The adapters will allow direct communication between EVE application and target database. EVE can generate specific SQL code to interact with the database. This code is dynamic and can be spool-out in a log file using a directive: "#echo:on", "#spool:on", "#log:file-name"

**Targeted Databases:** {
[PostgreSQL](http://www.postgresql.org/), 
[Oracle](http://www.oracle.com/), 
[MySQL](https://www.mysql.com/)
}   

## Cursor

* A cursor is special section that is based on one single select statement. 
* Cursor can return a structure that is a record or a table row_type. 
* A cursor is equivalent to a generator. It yields one record at a time on demand using fetch.

**Syntax:**
```
cursor: cursor_name>(params) => record_type
  ** select_statement
return
```

### Using a cursor
A cursor can be open, fetched and closed. This can be done also using _scan_.  We can fetch row by row or in bulk for several rows or all rows. This may be too many if the data set is very large. To avoid too many records in memory we can _limit_ the fetch. 

**Syntax:**

**using fetch...**
```
cursor_name.open(arguments)
fetch cursor_name +> record_variable;
fetch cursor_name +> list_of_records [limit N]
cursor_name.close();
```
**using scan**
```
given 
  record_type: record_name 
scan record_name <+ cursor_name(arguments) do
  with record_name do
     ... ** use record fields
  ready
next
```

## Select

This keyword comes from SQL. EVE is a pragmatic language. In practice we use SQL for relational databases. EVE is an adaptive language. It uses a modified SQL dialect to improve consistency with EVE language.

**Syntax:**
```
select (field_list) +> collection | record 
  [limit N] [offset M]
  from alias = table_name | alias = view_name,...
  join   alias.field == alias.field
  where filter_expression ...
  group  field_names,...
  order  field_names,...  
```

**Notes:** 

* The syntax is not specific to any database; 
* We use EVE operators for filter_expressions and for joins; 
* We can not use user defined functions in select statements; 
* We can use only aggregate functions specific to databases;

**Query Options**

* Join, where, order and group are optional; 
* We can capture resulting rows into a collection of records using +>; 
* We can capture one single row into a record variable;
* Limit N will retrieve several rows and will stop;
* Offset will start returning rows after a specific number of records; 
* We use this technique to paginate into a search; 
* Notice offset can increase the response time;

We can use group by to calculate aggregate functions: sum(), average(), count(), maximum(), median(), minimum(). These functions are translated to SQL dialect. We parse the statement and convert to SQL before we sent it to the database for execution.

### Select Usability
We use select to create a query. We can define in-line query or associate a query to view or to cursor. 
Instant cursor is created using ` scan ... <+ query ` to avoid separated cursor definition. This is best when the cursor is used a single time.

Select statement will inject properties into a built-in implicit global object called: $query. We can interrogate properties of $query after last select statement. For example: $query.count, $query.plan, $query.sql (return sql string for debugging).

## Insert statement

To create new data we have two options: Insert data or Append data. In standard SQL there is no append statement but for performance we also use append statement to create new rows into a data table faster. 

**One row:**
```
insert in table_name (field_name:value,...)
append to table_name (field_name:value,...)
```

**Note:** Unlike the classic SQL we use pair operator (':') to have improved readability.

**One record:**
```
insert in table_name map record_name
append to table_name map record_name
```

**Multiple rows:**
```
append to table_name
  select (field_target:field_source, ...)
  from alias = table_source,...
  join join_expression
  where filter_expression
```

**From collection:**
```
insert in table_name map record_collection
append to table_name map record_collection
```

## SQL Execution

SQL Is declarative language. Behind the scene we generate complex code that is dynamically created and executed. For debug purpose we enable introspection. 

* Before execution the statement is converted into SQL string. 
* We can visualize this string by using: $query.sql to debug the application. 
* Also we can use $query.count to see how many records are inserted. 
* After insert/append we need to issue db.commit or else the modifications are lost.


## Sage Code
As a reminder the standard insert statement ins SQL looks like this:

```
insert into table_name 
  (field, field, field ...) 
values
  (value, value, value ...)
```

When the list of fields is large then the mapping between the field name and the value is very difficult to read. You have to count the number of comas to be sure. In EVE we have change this to map directly a value to a filed_name using ":" pair up operator.

## Update
Update statement is part of DML language. EVE statement for update is a little bit different from the standard SQL. We can do single record update or multi record update in bulk using a combination with select statement.

**Syntax:**

1. Single table update:
```
update table_name map (field_name:expression,...)
  where where_condition
```
**note:** 
* Expression can be a constant value or a simple operation supported by the database. 
* It can contain local variables that are directly inserted into SQL.

2. Use Record variable:
```
update table_name map (table_field:record_field...) <: record_variable 
  where where_condition
```
**note:** In the where_condition we can use fields from record variable.

3. Use all fields from a record variable:
```
update table_name <: record_variable 
  where where_condition
```
**note:** In the where_condition we can use fields from record variable.

4. Use all fields from a record collection:
```
update table_name <: list_of_records 
  where where_condition;
```
**note:** In the where_condition we can use fields from record variable.

5. Join tables for update:
```
update target_alias = target_table map (target_alias.field_name:source_alias.field_name,...)
  from source_alias = source_table
  join   source_alias.field_name == target_alias.field_name
  where filter_expression
```
**note:** 
* you can not use outer join =+ for update. 
* this can generate null values or to many records. 

6. Using sub-query:
```
update target_alias = target_table map (field_name:value,...)
  from source_alias = (select (list_of_fields) 
        from source_tables
        join join_relations
        where search_conditions)
  where filter_expression
```
**note:** In this query, search_condition can include fields from target_table.


## Delete

This statement will remove one or more records from a table. 
We can specify what record using primary key or a where condition. 

**Syntax**

1. Using search condition
```
delete from table_name where search_condition
```
**Note:** search condition can use EVE operators and EVE variables.

2. Using sub-query
```
delete from table_name where 
   field_name in (select field_name from table where search_condition)
```

3. Using in operator
```
delete from table_name where 
   field_name in (set_of_variables)
```

## Execution
Any DML statement is executed immediate. We can execute a statement once or many times into a cycle. 
After several modifications we can issue db.commit(). 

If we do not commit changes will not be saved. An automatic commit will be done when we close the database. It is better to do a rollback or commit before this event.

After execution we can use _$query_ object to check the status of last update, append, insert or delete command.   

**Read next:**[Standard Library](standard-lib.md)