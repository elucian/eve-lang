# Atomic

Status: **0.1-draft**, standard library (D-132). The declaration is level 3 (it makes a variable of a managed module legal, `semantics/modules.md`); the operations that need threads are level 4. Tests: `test/level3` (c29, c30, c31).

## What it is

`Atomic(:T)` is a class of the standard library. It wraps the atomic of the machine (the virtual machine is written in Zig, and the class is a wrapper of the Zig atomic): each operation on the value is indivisible, needs no lock and can never be part of a deadlock. A variable of an atomic type is thread safe, so a `safe` module may have it (D-129), and a concurrent aspect may use it.

`T` is one of:

| `T` | Examples |
|---|---|
| Logic | `Atomic(:Logic)` |
| a number | `Atomic(:Integer)`, `Atomic(:Natural)`; `Atomic(:Real)` supports only reading and replacing the value, no arithmetic *(proposed: the machine has no atomic arithmetic on a real)* |
| a reference | `Atomic(:Point)` holds a reference to an object; the object itself is not made thread safe |
| an ordinal | `Atomic(:Color)` |

## Declaring

```eve
new safe_integer = 0 :Atomic(:Integer);      ** a variable, initialized with a value
new ready = False :Atomic(:Logic);
new empty :Atomic(:Integer);                  ** no value: the zero value of T

class SageInteger <: Atomic(:Integer);        ** a type: a class derived from Atomic(:Integer)
new hits = 0 :SageInteger;
```

A class derived from `Atomic(:T)` has no attribute of its own (`class Name <: Atomic(:T);`, with no shape). It may add methods. A variable typed with it is atomic.

## Using

In this version (a single task) an atomic variable is used like a variable of the type `T`: `let safe_integer += 5;`, `expect safe_integer == 5;`, `print safe_integer`. The operations of level 4 are *(proposed)*: `get!()`, `set(v)`, `add(n)`, `swap!(v)`, `compare_swap!(old, new)`, `fetch_add!(n)`; see `tutorial/multitasking.html#atomic`.

## Open points

1. The operations and their names (above, level 4); whether the operators `+=` and `-=` on an atomic variable are one atomic operation.
2. `Atomic(:Real)` and `Atomic` of a reference: which operations the machine can make indivisible.
3. A record or an object field that is atomic: `new self.count = 0 :Atomic(:Integer);` in a constructor.
