# F-LNG-16 Static checks

Name resolution, arity, visibility and type errors before the run (exit 65).

*Partial:* undefined names, constants, `apply` arguments, exports, free statements in modules, managed modules and concurrent aspects (`check.zig`, `project.zig`); the type checks are few.

## Missing

- Type checks before the run, exit 65: argument types, return types, assignment.
- A negative test for each check.
