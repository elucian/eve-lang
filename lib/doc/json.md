# json

Read and write json files as streams of records typed by a record class (D-189). Signature file: the body is native, in comp/evevm/src/dlib.zig (jsonModule, recordModule).
@spec spec/library/data-language.md  @feature F-LIB-05  @tests test/level5

## `external function read!(path: String) => (@result: Stream);`

A stream of records of the class given as type argument: json.read!(:Row)(path).

## `external procedure write(path: String, rows: Iterable);`

Write records to a file: json.write(path, rows).

## `external function parse(text: String) => (@result: Any);`

The JSON text as one value: null, Logic, Integer, Real, String, List or DataMap; a bad text is $err_format.

## `external function text(value: Any) => (@result: String);`

The compact JSON text of a value.

## `external function valid(text: String) => (@result: Logic);`

True when json.parse accepts the text.

