# csv

Read and write csv files as streams of records typed by a record class (D-189). Signature file: the body is native, in code/evevm/src/dlib.zig (csvModule, recordModule).
@spec spec/library/data-language.md  @feature F-LIB-05  @tests test/level5

## `external function read!(path: String) => (@result: Stream);`

A stream of records of the class given as type argument: csv.read!(:Row)(path).

## `external procedure write(path: String, rows: Iterable);`

Write records to a file: csv.write(path, rows).

