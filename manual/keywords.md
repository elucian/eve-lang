## Reserved keywords

For keywords, EVE use English reserved words, without any abbreviation.

## Define regions

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| import   | start import region
| constant | declare module constants (start with "." if is public)
| variable | declare module variables (start with "." if is public)
| alias    | define alias for data-type or member name from imported modules
| function | start a declaration region for named expression

## Define subregions

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| class    | define a composite data type for object oriented programming
| method   | define a named block of code
| process  | start executable region for a method and constructor for a class
| create   | start constructor region for a classes
| remove   | define object disposal region, executed when object is out of scope
| recover  | define a recover region for methods
| closure  | define a finalization region for methods
| return   | terminate a method/function or a class declaration

## Blocks of code/sections

| Keyword  | Description
|----------|---------------------------------------------------------------------
| given    | establish local scope for a block statement 
| do       | single-path non-repetitive block
| with     | scope qualifier suppression block for records
| when     | multi-path conditional block
| quest    | multi-path variable selector
| while    | conditional repetition block
| scan     | start an examination loop

## Operator keywords

| Keyword  | Description
|----------|-----------------------------------------------------------------
| is       | check data type x is Null \| quest associated keyword
| in       | check data type x is Null \| quest associated keyword
| if       | conditional operator
| not      | logical NOT operator
| and      | logical AND operator
| or       | logical OR  operator
| xor      | logical XOR operator

## Semantic keywords

| Keyword  | Description
|----------|-----------------------------------------------------------------
| do       | start a repetitive block: while & for
| else     | alternative path for when & while statements 
| case     | define a pas-way in multi-case methods
| other    | define alternative pasway in a quest
| done     | finalization keyword for non repetitive blocks 
| next     | finalize a scan block and start next iteration
| repeat   | trigger a condition check, finalize if condition yield false

## Interruption statements

| Keyword  | Description
|----------|-------------------------------------------------------------------
| exit     | silent stop a method and return control to the caller
| quit     | close resources, release memory and stop program execution
| stop     | early terminate execution of a method / function
| skip     | jump over all other statements to the end of any repetitive block
| raise    | create recoverable exception with error code and message
| retry    | multi-case jump backwards to specified case
| solve    | multi-case jump forward to specified case
| resume   | used in trial error handlers to continue with next case

## Default variables

| variable | Description
|----------|------------------------------------------------------------------
| object   | current instance of a class, current object
| result   | default result of a method when a name is not specified


**read next:** [Operators](operators.md)