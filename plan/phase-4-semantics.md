# Phase 4 — Semantics

Goal: the meaning of every construct, precise enough that two independent compilers produce the same output for the same program.

### S4.1 `semantics/types.md` + `types.json` `[ ]`
Source: `types.html`.
- Native, primitive and numeric types; `Symbol`; composite types; default (zero) values.
- Coercion: an implicit/explicit matrix in `types.json` (from → to, allowed, lossless).
- Type inference and gradual typing rules; polymorphic operators (link `operators.json`).
- Numeric precision and `$epsilon` comparison semantics (`demo/shared_state.eve`).
- Date, time and duration types.

### S4.2 `semantics/scopes.md` `[ ]`
- Name resolution, shadowing, globals (`@name`), system variables (`$name`), constants.
- Lifetime of module state versus aspect state.

### S4.3 `semantics/topology.md` `[ ]`
Source: `topology.html`, `manifest.html`.
- Projects, scripts, drivers, aspects, modules; import resolution; configuration.
- Execution model: driver start, aspect launch and unload, module persistence, termination, exit codes, exclusive mode.

### S4.4 `semantics/control.md` `[ ]`
Source: `control.html`, `processing.html`.
- Evaluation order, loop semantics, `case` fall-through rules.
- Errors: `try`/`recover`, `panic`, `raise`, `retry`, `resume`; what uncaught errors do.

### S4.5 `semantics/multitasking.md` `[ ]`
Source: `multitasking.html`, `processing.html`.
- Methods, side-effect rules, parameter passing modes (input, output, variant), generators, parallel aspects.
- D-050: multitasking is not in 0.1. Methods, side effects and parameter passing (D-048, D-049) are normative for 0.1; parallel aspects (D-066) go in a section marked "planned, not in 0.1", keywords reserved. Generators and the module `task` are specified in version 2 (D-067); `yield` is reserved.

### S4.6 Collections and objects `[ ]`
Source: `collections.html`, `classes.html`.
- List, Array, Matrix, DataSet, HashMap, String semantics (copy versus reference, bounds,
  iteration order).
- Object model: constructors, inheritance, partials, method chaining, equality.
