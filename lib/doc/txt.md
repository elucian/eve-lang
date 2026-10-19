# txt

Read and write txt files as streams of records typed by a record class (D-189). Signature file: the body is native, in comp/evevm/src/dlib.zig (txtModule, recordModule).
@spec spec/library/data-language.md  @feature F-LIB-05  @tests test/level5

## `external function read!(path: String) => (@result: Stream);`

A stream of records of the class given as type argument: txt.read!(:Row)(path).

## `external procedure write(path: String, rows: Iterable);`

Write records to a file: txt.write(path, rows).

