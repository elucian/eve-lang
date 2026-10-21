# Map functions

Status: **draft**, level 1. Library step L1. Written in the VM, in Zig. Feature: F-LIB-03.

The functions of a `DataMap` `{k: v}`. A function never changes the map it is called on. The functions `has`, `get`, `keys`, `values` and `delete` are described with the type ([types.md](../semantics/types.md#datamap-methods)).

## Functions

| Function | Result | Meaning |
|---|---|---|
| `merge(other)` | `DataMap` | a new map with the entries of both; for a key in both, the value of `other` |
| `invert()` | `DataMap` | a new map with the values as keys and the keys as values; the values must be texts or whole numbers, and two keys with the same value are the error `$err_argument` (17) |

```eve
new a := {"x": 1, "y": 2};
print a.merge({"y": 20, "z": 30});   ** {"x":1,"y":20,"z":30}
print {"a": 1, "b": 2}.invert();     ** {1:"a",2:"b"}
```
