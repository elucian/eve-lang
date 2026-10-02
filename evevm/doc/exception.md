# exception

Exceptions and warnings: the Error and Warning classes, the system variables, the
statements that raise and report, and the predefined constants $err_name and $wrn_name.
The same codes and message patterns are listed in tutorial/exceptions.html: keep both in step.
A declaration with the keyword external is implemented in Zig by the virtual machine.

## `class .Error = {code: Integer, message: String, module: String, line: Integer, job: String} <: Object is`

An error that interrupts a process. Its code is also the exit code of the application.

## `class .Warning = {code: Integer, message: String, module: String, line: Integer} <: Object is`

A condition that is reported but does not interrupt the process.

## `class .Call = {line: String, method: String} <: Object is`

One entry of the call stack.

## `external set $error: Error;`

The last error of the process.

## `external set $stack: ()Call;`

The calls that led to the error.

## `external set $trace: ()Error;`

The errors and the warnings of the process.

## `external .raise(e: Error);`

Raise an exception object.

## `external .raise(code: Integer, message: String);`

Raise an error with a code and a message.

## `external .raise(message: String);`

Raise an error with the default code 4.

## `external .expect(condition: Logic, message := "");`

Raise the error 2 when the condition is false. The message is optional.

## `external .assert(condition: Logic, message := "");`

Report the warning 3 when the condition is false and go on. The message is optional.

## `external .warn(code: Integer, message: String);`

Report a warning and go on.

## `set $err_panic = 1;`

panic: the message given to panic

## `set $err_expect = 2;`

expect: "Unexpected error in line {line}", or the custom message

## `set $err_raise = 4;`

raise without a code: the message given to raise

## `set $err_index = 10;`

"Index {index} is out of range {first}..{last}"

## `set $err_key = 11;`

"Key {key} not found"

## `set $err_divide = 12;`

"Division by zero"

## `set $err_overflow = 13;`

"Overflow in {operation}"

## `set $err_convert = 14;`

"Cannot convert {value} to {type}"

## `set $err_parse = 15;`

"Cannot parse {text} as {type}"

## `set $err_null = 16;`

"Null value used as {type}"

## `set $err_argument = 17;`

"Invalid argument {name}: {reason}"

## `set $err_file = 20;`

"File not found: {path}"

## `set $err_access = 21;`

"Access denied: {path}"

## `set $err_io = 22;`

"Input/output error on {path}: {reason}"

## `set $err_module = 30;`

"Module {name} not found in {library}"

## `set $err_process = 31;`

"Process {name} not found in aspect {aspect}"

## `set $err_memory = 40;`

"Out of memory while allocating {size}"

## `set $err_timeout = 41;`

"Time-out after {time}"

## `set $err_deadlock = 42;`

"Deadlock: every task of the group waits on a channel"

## `set $err_output = 43;`

"Output {name} is given to two tasks of the group"

## `set $wrn_assert = 3;`

assert: "Assertion failed in line {line}", or the custom message

## `set $wrn_deprecated = 5;`

"{name} is deprecated, use {other}"

## `set $wrn_truncate = 6;`

"Value {value} truncated to {type}"

## `set $wrn_unused = 7;`

"{name} is declared but never used"

