## Reserved keywords

In EVE we use English keywords with no abbreviations.

## Establish regions

| Keyword  | Description
|----------|---------------------------------------------------------
| import   | start import region
| global   | declare global variables and constants
| define   | start a declaration region for types
| start    | define object initialization region
| scrap    | define object disposal region
| recover  | define a recover region for methods
| finalize | define a finalize region for methods

## Blocks of code
| Keyword  | Description
|----------|-------------------------------------------------------------
| function | start a declaration region for subroutine with result
| method   | start a declaration region for subroutine with no result
| class    | create a composite data type for object oriented programming
| begin    | single-path non-repetitive block
| while    | conditional repetition block
| quest    | multi-path variable selector
| trial    | exception handling block
| with     | qualifier suppression block for records

## Semantic keywords

| Keyword  | Description
|----------|-------------------------------------------------------
| is       | check data type: x is Null \| quest associated keyword
| in       | check data type: x is Null \| quest associated keyword
| do       | start a repetitive block: while & for
| as       | execute explicit cast to other data type
| if       | create a conditional augment for simple statements
| from     | bring members into current name-space
| use      | enumerate members to be used in current name-space
| all      | specify "all" members to be used in current name-space
| from     | used to bring members into current name-space
| alias    | usend in import region to give alias to a module
| given    | establish local scope for any block statement
| else     | alternative path for when statement 
| cover    | used for switch sections to declare default branch
| case     | multi-case trial regions
| error    | trial specific error handler
| other    | trial general error handler
| next     | used to mark end of scan block and continue with next value

## Interruption statements

| Keyword  | Description
|----------|-------------------------------------------------------------------
| skip     | jump over all other statements to the end of any repetitive block
| exit     | interrupt the cycle and continue with next statement
| raise    | create recoverable exception with error code and message
| retry    | multi-case jump backwards to specified case
| solve    | multi-case jump forward to specified case
| fail     | create quick un-recoverable error
| pass     | clear last $error and continue workflow
| resume   | used in trial error handlers to continue with next case
| abort    | silent break the trial block and continue with next statement
| stop     | early terminate execution of a method / function

## Default variables

| variable | Description
|----------|-------------------------------------------------------
| myself   | current instance of a class
| result   | result of a function if result names are not specified
