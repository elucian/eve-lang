# secret

Secrets that never appear in logs or code (D-189). Signature file: the body is native, in comp/evevm/src/interp/datatypes.zig (secretGet).
@spec spec/library/registry.md  @feature F-LIB-08  @tests test/level5

## `external function get(name: String) => (@result: Secret);`

A Secret read from the secret store or the environment by name.

