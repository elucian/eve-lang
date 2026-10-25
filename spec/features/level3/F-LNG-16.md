# F-LNG-16 Static checks

Name resolution, arity, visibility and type errors before the run (exit 65).

*State:* undefined names, constants, `apply` arguments, exports, free statements in modules, managed modules, concurrent aspects (`check.zig`, `project.zig`), and the type checks of a basic type given where another basic type is declared: an assignment, an argument, a result, a declaration (`types.md#static-checks`, tests e160).

## Missing

- The type checks of the classes, the lists and the optional types before the run (the optional type is checked at run time by the narrowing rules of `types.md`).
