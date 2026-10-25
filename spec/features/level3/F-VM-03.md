# F-VM-03 Library loader and `external` bindings

Load `.eve` library modules and bind `external` declarations to Zig.

*Done:* project modules are loaded (`project.zig`); an `external` of a module that has the name of a native module is bound to the native of the same name, any other is a clear run-time error (tests c29, c30, c31, c38); `print` and the exception names are built into the interpreter.

## Missing

Nothing.
