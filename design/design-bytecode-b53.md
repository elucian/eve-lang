# B5.3: Collections and strings natively

## Goal

Translate the collection and string operations to bytecode, removing the bridge for level 1. This includes:
- List creation, indexing, append, iteration
- Map/DataSet creation, indexing, methods
- String concatenation, interpolation, methods
- Collection method calls (`.count()`, `.length()`, `.keys()`, `.values()`, `.delete()`, `.join()`, `.split()`, `.has()`, `.get()`)

## Current state

All collection operations run on the tree walker through the bridge (`evalx`/`execx`). The tests pass but the benchmarks (`p1c_collections`, `p1d_strings`) are slow because of the bridge overhead.

- `p1c_collections`: 21.9 ms tree walker, 21.9 ms bytecode (same, all bridged)
- `p1d_strings`: 16.3 ms tree walker, 15.3 ms bytecode (slightly faster due to reduced bridge calls)

The method implementations are in:
- `comp/evevm/src/interp/calls.zig` lines 250-291 (general methods: `.count()`, `.length()`, `.delete()`, string methods)
- `comp/evevm/src/interp/collections.zig` lines 348-380 (map methods: `.has()`, `.get()`, `.keys()`, `.values()`, `.delete()`)

## New instructions

| Instruction | Meaning | Notes |
|---|---|---|
| `new_list` | `A := []` | Empty list |
| `new_map` | `A := {}` | Empty map |
| `new_set` | `A := {}` (set) | Empty set; requires type context |
| `list_push` | `A <+ B` | Append B to list A; A is modified |
| `list_index` | `A := B[C]` | Get element at index C (1-based, negative for from-end) |
| `list_set` | `A[B] := C` | Set element at index B to C |
| `map_get` | `A := B[C]` | Get value for key C from map B |
| `map_set` | `A[B] := C` | Set A[B] to C for map A |
| `set_add` | `A <+ B` | Add B to set A; A is modified |
| `set_has` | `A := B in C` | Check if B is in set C (as boolean) |
| `length` | `A := B.len` | Length or count; works on list, map, set, string |
| `call_method` | `A := B.method(args)` | Call a method on a collection or string; method name and args in the next word |
| `concat_str` | `A := B <+ C` | Concatenate strings B and C |
| `interpolate` | `A := f"..."` | String interpolation (complex, may stay bridged initially) |

## Phased implementation

### Phase 1: List operations (1 day)
- `new_list`, `list_push`, `list_index`, `list_set`
- `length` for lists
- Emitter support for list literals `(1, 2, 3)` and indexing `a[i]`
- Test: `a17_list` passes fully natively (currently all `evalx`)

### Phase 2: Map and set operations (1 day)
- `new_map`, `new_set`, `map_get`, `map_set`, `set_add`, `set_has`
- `length` for maps and sets
- Emitter support for map/set literals and indexing
- Test: `a20_dataset` passes fully natively

### Phase 3: Collection methods (1 day)
- `call_method` instruction to dispatch `.count()`, `.keys()`, `.values()`, `.delete()`, `.join()`, etc.
- Emitter support for method calls on collections
- Test: all `a17`, `a18`, `a19`, `a20` pass natively

### Phase 4: String operations (1 day)
- `concat_str` for `<+` on strings
- `length` for strings
- Emitter support for string concatenation and methods
- Test: `a10_strings` passes natively
- Note: `.split()`, `.join()` already work through collection methods in Phase 3

### Phase 5: String interpolation (1 day)
- Decide: translate `f"..."` to bytecode or keep it bridged
- If translated: add `interpolate` instruction or expand to concat chain
- Test: `a11_interpolation` passes natively

## Risks

1. **Register pressure:** collection operations may need more temporaries; register limit is 255
2. **Type information:** maps and sets need type hints to distinguish `{}` (empty map) from `{1,2,3}` (set)
3. **Indexing with ranges:** `a[1..5]` and `a[<..5]` return slices; not in phase 1
4. **Builder expressions:** `(x ^ 2 | x in lst)` may need to stay bridged (generator-like)
5. **Negative indices:** Eve lists support `a[-1]` for the last element; bytecode must preserve this

## Success criteria

- Level 1 tests `a17`, `a18`, `a19`, `a20` run fully natively (no `evalx`/`execx`)
- Benchmarks:
  - `p1c_collections`: 21.9 ms → ≤ 15 ms (30% faster)
  - `p1d_strings`: 16.3 ms → ≤ 12 ms (25% faster)
- All tests pass on both engines with `--both`
- No slowdown on other benchmarks
- `EVE_GC_VERIFY=1` reports no leaks

## Files to change

- `comp/evecm/src/op.zig`: add new Op enum variants
- `comp/evecm/src/chunk.zig`: add disassembly for new instructions
- `comp/evecp/src/emit.zig`: emitter support for collection literals and indexing
- `comp/evevm/src/bcvm.zig`: add execute cases for new instructions
- `comp/evevm/src/interp/collections.zig`: share method dispatch with bytecode
- `test/bytecode/`: add golde listings for collection operations
- `comp/evecm/doc/instructions.md`: update instruction table

## Dependencies

- B5.2 must be complete (done 2026-10-19)
- Tests must pass on tree walker first (done)
