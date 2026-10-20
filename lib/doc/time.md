# time

The clock (D-087, D-168, D-189). Signature file: the body is native, in code/evevm/src/dlib.zig (timeModule).
@spec spec/library/registry.md  @feature F-LIB-06  @decision D-087  @tests test/level5

## `external function now!() => (@result: Instant);`

The current instant. It gives another value at each call, so the name ends with `!`.

