# checkpoint

Checkpoints of a restartable load, kept in the core database (D-158, D-159, D-189). Signature file: the body is native, in comp/evevm/src/dlib.zig (checkpointModule); the type argument names the type of the value: checkpoint.read!(:Instant)(name, default: x).
@spec spec/library/database.md#checkpoints  @feature F-DAT-04  @decision D-159  @tests test/level5

## `external function read!(name: String, default: Any) => (@result: Any);`

The value saved under a name, or the default when none was saved.

## `external procedure write(name: String, value: Any);`

Save a value under a name.

