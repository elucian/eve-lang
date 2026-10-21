# F-LNG-22 External routines and errors of modules

An `external` routine of a module whose name is that of a native module (`os`, `fs`, `crypto`,...) is bound to the native of the same name; an error raised in a module names the file of the module and the call lines end with `of <file>` (`spec/semantics/modules.md#members`, `errors.md#where-an-error-is-reported`, ).
