# F-LNG-18 `Atomic(:T)`

A class of the standard library that wraps the atomic of the machine, for Logic, numbers, references and ordinals; `class Name <: Atomic(:T)`.

*Partial:* the declaration and the check of managed modules work, the value is a plain value; the operations (`add`, `get!`, `swap!`) need threads.

## Missing

- `add`, `get!`, `swap!` on real threads; the value is a plain value today.
- A counter under parallel tasks gives the same total at every run (`--repeat 5`).
