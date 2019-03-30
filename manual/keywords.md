## Reserved keywords

In Level we use English keywords with no abbreviations.

## Establish regions

| Keyword  | Description
|----------|---------------------------------------------------------
| import   | start import region
| global   | declare global variables and constants
| define   | start a declaration region for: types and functions 
| public   | define a public region in a class
| private  | define a private region in a class
| setup    | define object initialization region
| clean    | define object disposal region
| recover  | define a recover region for methods
| finalize | define a finalize region for methods

## Blocks of code
| Keyword  | Description
|----------|-------------------------------------------------------------
| function | start a declaration region for free functions
| aspect   | start a declaration region for subroutines with no result
| class    | create a composite data type for object oriented programming
| split    | multi-path variable selector
| quest    | single-path non-repetitive block
| while    | conditional repetition block
| trial    | exception handling block
| with     | qualifier suppression block for records

## Semantic keywords

| Keyword  | Description
|----------|-------------------------------------------------------
| is       | check data type: x is Null \| x is Integer
| as       | execute explicit cast to other data type
| of       | used to declare a composite type
| if       | create a conditional augment for simple statements
| from     | bring members into current name-space
| use      | enumerate members to be used in current namespace
| all      | specify "all" members to be used in current namespace
| redo     | check while condition and repeat the block from the beginning
| next     | used in scan block to continue with next iteration
| loop     | restart cycle from the beginning usually controled by if
| stop     | interrupt the cycle and continue with next statement
| from     | used to bring members into current name-space
| alias    | usend in import region to give alias to a module
| given    | establish local scope for any block statement
| do       | start a repetitive block: while & for
| else     | alternative path for case statement 
| default  | used for switch sections to declare default branch
| case     | multi-case trial regions
| error    | trial specific error handler
| other    | trial general error handler
| raise    | create recoverable exception with error code and message
| retry    | multi-case jump backwards to specified case
| solve    | multi-case jump forward to specified case
| fail     | create quick un-recoverable error
| pass     | clear last $error and continue workflow
| resume   | used in trial error handlers to continue with next case
| abort    | silent break the trial block and continue with next statement


## Default variables

| variable | Description
|----------|-------------------------------------------------------
| Class    | the ancestor class for all classes
| object   | current instance of a class
| result   | result of a aspect if result names are not specified
