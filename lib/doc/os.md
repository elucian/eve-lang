# os

Run a program without a shell, the environment, the machine (F-LIB-07, D-189). Signature file: the body is native, in code/evevm/src/syslib.zig (osModule).
@spec spec/library/os.md  @feature F-LIB-07  @decision D-189  @tests test/level6/f05_os

## `external function run!(command: String, args: List, cwd: String) => (@result: ProcessResult);`

Start command with the arguments of the list in the folder cwd ("" = here); gives status, out and err.

## `external function env!(name: String, default: String) => (@result: String);`

The value of an environment variable, or default when it is not set.

## `external function hostname!() => (@result: String);`

The name of this computer.

## `external function pid!() => (@result: Integer);`

The process id of this machine.

## `external function platform() => (@result: String);`

"windows", "linux" or "macos".

