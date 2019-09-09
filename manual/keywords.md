## Reserved keywords

EVE use 51 English reserved words, without any abbreviations. You can not use these words as identifiers.


## Definition regions

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| import   | start import region
| type     | define data-type or sub-type 
| constant | declare module constants (start with "." if is public)
| variable | declare module variables (start with "." if is public)
| function | start a declaration region for named expression

## Memory allocation

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| forge    | create a new object reference / object instantiation on the heap
| alter    | modify underline value of a reference or value of a native variable
| clone    | copy a reference into another reference, with deep copy operator "::"
| share    | share  a reference from existing reference

## Semantic keywords

| Keyword  | Description
|----------|-----------------------------------------------------------------------
| class    | define a composite data type for object oriented programming
| routine  | create a sub-routine similar to a void function
| create   | start constructor region for a classes
| remove   | define object disposal region, executed when object is out of scope
| feature  | define a design pattern that can be _enabled_ by a class
| augment  | define an augment for an existing class
| routine  | define a named block of code belonging to a module
| method   | define a named block of code belonging to a class
| process  | start executable region for a routine and constructor for a class
| recover  | define a recover region for methods
| release  | define a finalization region for routines
| return   | terminate a routine/function or a class declaration

## Blocks of code/sections

| Keyword  | Description
|----------|---------------------------------------------------------------------
| do       | start a block or branch of a block
| with     | scope qualifier suppression block for records
| when     | multi-path conditional block
| else     | alternative path for { when, case, while } statements 
| check    | multi-path variable selector
| case     | define a pas-way in multi-case methods
| given    | establish local scope for a block statement 
| cycle    | unconditional repetitive block
| while    | conditional repetition block
| for      | visitor iteration loop 
| repeat   | trigger a condition check, finalize if condition yield false
| done     | finalization keyword for non repetitive blocks 
| next     | finalize a scan block and start next iteration

## Operator keywords

| Keyword  | Description
|----------|-----------------------------------------------------------------
| if       | conditional operator
| is       | check data type x is Null \| quest associated keyword
| in       | check data type x is Null \| quest associated keyword
| not      | logical NOT operator
| and      | logical AND operator
| or       | logical OR  operator
| xor      | logical XOR operator


## Interruption statements

| Keyword  | Description
|----------|-------------------------------------------------------------------
| exit     | silent stop a routine and return control to the caller
| over     | close resources, release memory and stop program execution
| stop     | early terminate execution of a routine / function
| skip     | jump over all other statements to the end of block
| raise    | create recoverable exception with error code and message
| fail     | create standard work-flow error if condition is true
| pass     | create standard unexpected error if condition is true
| abort    | abort current process and clear error object
| retry    | work-flow jump backwards to specified step
| apply    | interrupt current execution and wait for subroutine execution
| resume   | used in work-flow handlers to continue with next step


## Default variables

| variable  | Description
|-----------|------------------------------------------------------------------
| object    | current instance of a class, current object
| result    | default result of a routine when a name is not specified
| error     | current exception object of type Exception

**read next:** [Operators](operators.md)