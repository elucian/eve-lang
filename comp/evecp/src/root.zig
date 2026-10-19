//! evecp: the compiler of Eve (design-packages.md §3). It reads source text and gives a checked
//! syntax tree: the lexer, the parser, the checker, the overload rules and the link of a root aspect
//! with its aspects and modules. It also writes documentation and the layout of new projects.
//! It imports `evecm` only; it knows nothing of the interpreter or the databases.

/// The tokens of a script.
pub const lexer = @import("lexer.zig");

/// The grammar: tokens to a syntax tree.
pub const parser = @import("parser.zig");

/// The static checks of the language.
pub const check = @import("check.zig");
/// The emitter of the bytecode.
pub const emit = @import("emit.zig");

/// The rules for choosing among overloaded subprograms.
pub const overload = @import("overload.zig");

/// A root aspect with its aspects and modules: the project link.
pub const project = @import("project.zig");

/// `eve --doc`: Markdown from the comments of a source file.
pub const doc = @import("doc.zig");

/// `project init` and `project new`: the layout of a new project.
pub const scaffold = @import("scaffold.zig");

/// The entry point of the tools: diagnostics and outline of a text in one call (TD-34).
pub const analyze = @import("analyze.zig");

/// The commands `check`, `doc` and `project`, shared by the program `evecp` and by `eve cp` (D-198).
pub const cli = @import("cli.zig");

test {
    _ = lexer;
    _ = parser;
    _ = check;
    _ = overload;
    _ = project;
    _ = doc;
    _ = scaffold;
    _ = cli;
    _ = analyze;
    _ = emit;
}
