# fs

Files, folders and paths in one module (Q-024 a, D-189). Signature file: the body is native, in code/evevm/src/dlib.zig (fsCall).
@spec spec/library/data-language.md  @feature F-LIB-04  @decision D-189  @tests test/level5

## `external function read!(path: String) => (@result: String);`

Whole file as text (UTF-8 by default).

## `external function read_bytes!(path: String) => (@result: List);`

Whole file as a list of bytes (0 to 255).

## `external function lines!(path: String) => (@result: Stream);`

The lines of a file as a stream, read one at a time.

## `external procedure write(path: String, text: String);`

Write text to a file, replacing it.

## `external procedure write_bytes(path: String, bytes: List);`

Write a list of bytes (0 to 255) to a file, replacing it.

## `external procedure append(path: String, text: String);`

Add text at the end of a file.

## `external function exists!(path: String) => (@result: Logic);`

Does the path exist.

## `external function size!(path: String) => (@result: Integer);`

Size of a file in bytes.

## `external function list!(path: String) => (@result: List);`

The names in a folder.

## `external procedure make_dir(path: String);`

Create a folder.

## `external procedure move(from: String, to: String);`

Rename or move a file.

## `external procedure remove(path: String);`

Delete a file.

## `external function join(a: String, b: String) => (@result: String);`

Join two parts of a path (the operator / does the same).

## `external function name(path: String) => (@result: String);`

The last part of a path.

## `external function parent(path: String) => (@result: String);`

The path without its last part.

## `external function extension(path: String) => (@result: String);`

The extension of the last part, with its dot.

