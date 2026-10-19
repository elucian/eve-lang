# test

Checks for the tests that a user writes in Eve: one line per check, counters, a summary that fails the process.
@spec spec/library/test.md  @feature F-LIB-12  @decision D-189  @tests test/level6/f03_test_module

## `procedure check(name: String, ok: Logic) is`

Count a pass when ok is True, a failure otherwise.

## `procedure equal(:T)(name: String, actual: T, expected: T) is`

A pass when actual equals expected; a failure shows both values.

## `procedure differ(:T)(name: String, actual: T, other: T) is`

A pass when the two values are not equal.

## `procedure close(name: String, actual: Real, expected: Real, tolerance: Real) is`

A pass when actual is within tolerance of expected.

## `function passed!() => (@result: Integer) is`

The number of passes so far.

## `function failed!() => (@result: Integer) is`

The number of failures so far.

## `procedure summary() is`

Print the totals; raise an error when a check failed, so the process ends with a failure code.

