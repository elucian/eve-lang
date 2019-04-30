## Reserved keywords

For keywords, EVE use English reserved words, without any abbreviation.

## Establish regions

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| import   | start import region
| define   | start a declaration region for user defined sub-types
| global   | declare global variables or constants (constants start with uppercase)
| process  | start executable region for a method and constructor for a class
| create   | start constructor region for a classes
| remove   | define object disposal region, executed when object is out of scope
| recover  | define a recover region for methods
| closure  | define a finalization region for methods

## Define identifiers

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| method   | start a declaration region for subroutine with no result
| class    | create a composite data type for object oriented programming
| function | start a declaration region for subroutine with result
| type     | define sub-type or composite super-type

## Blocks of code/sections

| Keyword  | Description
|----------|-------------------------------------------------------------
| given    | establish local scope for a block statement 
| begin    | single-path non-repetitive block
| with     | qualifier suppression block for records
| when     | multi-path conditional block
| quest    | multi-path variable selector
| while    | conditional repetition block
| scan     | start an examination loop


## Operator keywords

| Keyword  | Description
|----------|-------------------------------------------------------
| is       | check data type: x is Null \| quest associated keyword
| in       | check data type: x is Null \| quest associated keyword
| as       | execute explicit cast to other data type
| not      | logical NOT operator
| and      | logical AND operator
| or       | logical OR  operator
| xor      | logical XOR operator

## Semantic keywords

| Keyword  | Description
|----------|-----------------------------------------------------------------
| if       | create a conditional augment for simple statements
| do       | start a repetitive block: while & for
| else     | alternative path for when & while statements 
| case     | define a pasway in multi-case methods
| other    | define alternative pasway in a quest
| done     | finalization keyword for non repetitive blocks 
| next     | finalize a scan block and start next iteration
| repeat   | trigger a condition check, finalize if condition yield false
| return   | terminate a method or a class constructor block

## Interruption statements

| Keyword  | Description
|----------|-------------------------------------------------------------------
| exit     | silent stop a method and return control to the caller
| stop     | early terminate execution of a method / function
| skip     | jump over all other statements to the end of any repetitive block
| raise    | create recoverable exception with error code and message
| retry    | multi-case jump backwards to specified case
| solve    | multi-case jump forward to specified case
| resume   | used in trial error handlers to continue with next case

## Default variables

| variable | Description
|----------|------------------------------------------------------------
| object   | current instance of a class, current object
| result   | default result of a method when a name is not specified

## Other keywords

EVE uses other reserved words that are gradually explained in syntax manual.

* Directives
* Data types
* Data query

**read next:** [Operators](operators.md)