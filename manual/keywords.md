## Reserved keywords

In EVE we use English keywords with no abbreviations.

## Establish regions

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| import   | start import region
| define   | start a declaration region for user defined sub-types
| global   | declare global variables or constants (constants start with uppercase)
| process  | start executable region for a method and constructor for a class
| create   | start constructor region for a classes
| dispose  | define object disposal region
| recover  | define a recover region for methods
| closure  | define a finalization region for methods
| function | start a declaration region for subroutine with result
| method   | start a declaration region for subroutine with no result
| class    | create a composite data type for object oriented programming
| return   | terminate a method or a class constructor block

## Blocks of code/sections

| Keyword  | Description
|----------|-------------------------------------------------------------
| given    | establish local scope for any block statement 
| begin    | single-path non-repetitive block
| when     | multi-path conditional block
| quest    | multi-path variable selector
| while    | conditional repetition block
| scan     | start an examination loop
| with     | qualifier suppression block for records

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
|----------|-------------------------------------------------------
| from     | bring members into current name-space
| use      | enumerate members to be used in current name-space
| all      | specify "all" members to be used in current name-space
| alias    | usend in import region to give alias to a script
| if       | create a conditional augment for simple statements
| do       | start a repetitive block: while & for
| else     | alternative path for when statement 
| case     | define a pasway in multi-case methods
| other    | define alternative pasway in a quest
| next     | used to prepare a scan block for next iteration

## Interruption statements

| Keyword  | Description
|----------|-------------------------------------------------------------------
| abort    | silent stop a method and return control to the caller
| stop     | early terminate execution of a method / function
| skip     | jump over all other statements to the end of any repetitive block
| raise    | create recoverable exception with error code and message
| retry    | multi-case jump backwards to specified case
| solve    | multi-case jump forward to specified case
| resume   | used in trial error handlers to continue with next case
| halt     | suddenly finalize a program and create an error

## Default variables

| variable | Description
|----------|------------------------------------------------------------
| object   | current instance of a class, current object
| result   | default result of a method when a name is not specified

**read next:** [Operators](operators.md)