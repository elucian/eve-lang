//! The project of a driver: the aspects its `apply` statements run (D-066, D-112). Eve is a
//! compiler first (D-110): before the driver starts, every aspect it applies is found, read,
//! parsed and checked, and every `apply` is matched with the parameters of the `main` of that
//! aspect. A missing aspect, a wrong argument, a bad aspect file: all exit 65, and nothing runs.
//! The interpreter then finds the parsed aspect in the map built here and only runs it.
const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Node = ast.Node;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

// Zig tip: a struct can carry the state of a whole pass, so its functions take one `*Linker`
// instead of five parameters. `where` is the file the error is in ("" for the driver itself):
// the caller prints it in front of the position. `[]const u8` slices are views, never copies;
// every text here lives in the arena `a`, which the caller frees when the run is over.
const Linker = struct {
    a: std.mem.Allocator,
    io: Io,
    /// The folder of the driver: the project root.
    dir: []const u8,
    diag: *Diag,
    where: *[]const u8,
    aspects: *ast.Aspects,

    // Zig tip: `fail` fills the `Diag` like the parser does and returns `error.Syntax`, so a caller
    // writes `return l.fail(n, "...", .{})`; see the tip on `Parser.fail`.
    fn fail(l: *Linker, n: *const Node, comptime fmt: []const u8, args: anytype) Error {
        l.diag.set(n.line, n.col, fmt, args);
        return error.Syntax;
    }

    // Zig tip: `std.fmt.allocPrint(a, fmt, args)` formats into memory taken from `a` and returns
    // the slice. `catch return error.OutOfMemory` turns any allocation error into the one error
    // this function lists in its type.
    fn join(l: *Linker, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(l.a, fmt, args) catch return error.OutOfMemory;
    }

    // Zig tip: `Io.Dir.cwd().readFileAlloc(io, path, a, .limited(n))` reads a whole file, at most
    // `n` bytes. A file that cannot be opened is an error value, not a crash: here it only means
    // "not in this folder", so `catch null` turns it into an optional and the caller tries the next one.
    /// Read the first of the candidate files that exists. `path` gets the one that was found.
    fn read(l: *Linker, candidates: []const []const u8, path: *[]const u8) ?[]const u8 {
        for (candidates) |c| {
            if (Io.Dir.cwd().readFileAlloc(l.io, c, l.a, .limited(16 << 20)) catch null) |src| {
                path.* = c;
                return src;
            }
        }
        return null;
    }

    // Zig tip: `std.mem.lastIndexOfScalar` finds the last position of one byte, or null. The name
    // of the file is what follows the last `/`; `orelse` gives the whole text when there is none.
    /// Find, parse and check the aspect written `path` in an `apply`; remember it in the map.
    fn load(l: *Linker, at: *const Node) Error!*const Node {
        const key = at.text;
        if (l.aspects.get(key)) |known| return known;
        const file = try l.join("{s}.eve", .{key});
        const slash = std.mem.lastIndexOfScalar(u8, key, '/');
        const short = if (slash) |i| key[i + 1 ..] else key;
        // the folder written in the call comes first (D-112), then asp/, then the project root
        // Zig tip: `[2][]const u8 = undefined` is a fixed array of two texts, filled below;
        // `buf[0..n]` is the slice of the part that was filled. The array lives on the stack.
        var buf: [2][]const u8 = undefined;
        var n: usize = 0;
        if (slash == null) {
            buf[n] = try l.join("{s}/asp/{s}", .{ l.dir, file });
            n += 1;
        }
        buf[n] = try l.join("{s}/{s}", .{ l.dir, file });
        n += 1;
        const candidates = buf[0..n];
        var path: []const u8 = "";
        const src = l.read(candidates, &path) orelse {
            const tried = try l.join("{s}", .{candidates[0]});
            return l.fail(at, "aspect '{s}' not found (looked for {s}{s})", .{ key, tried, if (candidates.len > 1) " and the project root" else "" });
        };
        l.where.* = path;
        const tree = try parser.parse(l.a, src, l.diag);
        l.where.* = "";
        if (tree.tag != .aspect) return l.fail(at, "'{s}' is not an aspect: apply runs only aspects", .{path});
        if (!std.mem.eql(u8, tree.text, short)) {
            return l.fail(at, "the file '{s}' declares the aspect '{s}': the names must be equal", .{ path, tree.text });
        }
        try l.aspects.put(l.a, key, tree);
        return tree;
    }

    // Zig tip: `unreachable` tells the compiler (and, in a safe build, traps) that a line can never
    // run. It is for facts another part of the program has already proved, like the parser here.
    /// The `process main` of a parsed aspect.
    fn mainOf(aspect: *const Node) *const Node {
        for (aspect.kids) |k| if (k.tag == .process) return k;
        unreachable; // the parser guarantees one process (Parser.aspect)
    }

    /// The kind of a literal argument: the only types the link can know without running.
    fn literalType(n: *const Node) ?[]const u8 {
        switch (n.tag) {
            .num => {
                for (n.text) |ch| if (ch == '.') return "Real";
                for (n.text) |ch| if (std.ascii.isAlphabetic(ch)) return null;
                return "Integer";
            },
            .str, .interp, .text_lit => return "String",
            else => return null,
        }
    }

    // Zig tip: `comptime names` is a list known while compiling, and `inline for` unrolls the loop over
    // it: the comparison is written out once per name, with no loop left at run time.
    /// Is `name` one of `names`?
    fn isOneOf(name: []const u8, comptime names: []const []const u8) bool {
        inline for (names) |n| if (std.mem.eql(u8, name, n)) return true;
        return false;
    }

    /// Can a literal of type `lit` be given to a parameter declared `want`? Unknown types pass.
    fn fits(lit: []const u8, want: []const u8) bool {
        const number = comptime [_][]const u8{ "Integer", "Natural", "Real" };
        if (isOneOf(want, &number)) {
            if (std.mem.eql(u8, lit, "String")) return false;
            return !(std.mem.eql(u8, lit, "Real") and !std.mem.eql(u8, want, "Real"));
        }
        if (isOneOf(want, &.{ "String", "Text" })) return std.mem.eql(u8, lit, "String");
        if (std.mem.eql(u8, want, "Logic")) return false;
        return true;
    }

    // Zig tip: this walks the arguments the way `Interp.bindParams` binds them at run time: a
    // named argument takes its parameter, the others fill the remaining parameters in order. `used`
    // is a stack array of booleans (`[_]bool{false} ** 32`, see bindParams) that marks the arguments
    // already taken. A spread (`*list`, `*map`) is known only at run time, so with a spread the
    // counts are not checked, only the names that are written.
    /// Match the arguments of one `apply` with the parameters of `main`.
    fn match(l: *Linker, apply: *const Node, aspect: *const Node) Error!void {
        const params = mainOf(aspect).kids[3].kids;
        const args = apply.kids;
        var spread = false;
        var positional: usize = 0;
        for (args) |a| {
            if (a.tag == .spread) {
                spread = true;
            } else if (a.tag == .pair and a.kids[0].tag == .name) {
                var known = false;
                for (params) |prm| {
                    if (std.mem.eql(u8, prm.text, a.kids[0].text)) known = true;
                }
                if (!known) return l.fail(a, "the aspect '{s}' has no parameter '{s}'", .{ aspect.text, a.kids[0].text });
            } else positional += 1;
        }
        var vararg = false;
        for (params) |prm| if (prm.tag == .vararg_param) {
            vararg = true;
        };
        if (!spread and !vararg and positional > params.len) {
            return l.fail(apply, "too many arguments: the aspect '{s}' has {d} parameters, the call gives {d}", .{ aspect.text, params.len, positional });
        }
        var next: usize = 0; // the next positional argument, counted among the positional ones
        var seen_optional = false;
        for (params) |prm| {
            if (prm.tag == .vararg_param) break;
            const optional = prm.kids[0].tag != .none;
            if (optional) seen_optional = true;
            var given: ?*const Node = null;
            for (args) |a| {
                if (a.tag == .pair and a.kids[0].tag == .name and std.mem.eql(u8, a.kids[0].text, prm.text)) given = a.kids[1];
            }
            if (given == null and next < positional) {
                var k: usize = 0;
                for (args) |a| {
                    if (a.tag == .spread or (a.tag == .pair and a.kids[0].tag == .name)) continue;
                    if (k == next) given = a;
                    k += 1;
                }
                next += 1;
                if (!optional and seen_optional) {
                    return l.fail(apply, "the parameter '{s}' follows optional parameters: give it by name, {s}: ... (D-106)", .{ prm.text, prm.text });
                }
            }
            if (given == null) {
                if (!optional and !spread) return l.fail(apply, "the argument '{s}' of the aspect '{s}' is missing", .{ prm.text, aspect.text });
                continue;
            }
            const want = if (prm.ty) |t| t.text else "";
            if (literalType(given.?)) |lit| {
                if (want.len > 0 and !fits(lit, want)) {
                    return l.fail(given.?, "the parameter '{s}' is {s}, the argument is {s}", .{ prm.text, want, lit });
                }
            }
        }
    }

    // Zig tip: a recursive walk over the tree: every node is looked at, then its type and its
    // kids. `anyerror`-free: the only errors are the ones of `Error`, so the recursion can name its
    // own error set (a recursive function needs one written out, see `ast.dump`).
    /// Find every `apply` in the tree, load its aspect and match the arguments.
    fn walk(l: *Linker, n: *const Node) Error!void {
        if (n.tag == .apply_stmt) {
            const aspect = try l.load(n);
            try l.match(n, aspect);
        }
        for (n.kids) |k| try l.walk(k);
    }
};

// Zig tip: `*[]const u8` is a pointer to a slice: the function writes the answer through it, here
// the path of the file in which an error was found. A function returns one value (the error
// union), so extra answers come back this way, through pointers the caller gave.
/// Link a driver: read every aspect it applies into `aspects`. On an error returns `error.Syntax`,
/// fills `diag`, and sets `where` to the aspect file when the problem is inside it (else "").
pub fn link(
    a: std.mem.Allocator,
    io: Io,
    dir: []const u8,
    tree: *const Node,
    diag: *Diag,
    where: *[]const u8,
    aspects: *ast.Aspects,
) Error!void {
    var l: Linker = .{ .a = a, .io = io, .dir = dir, .diag = diag, .where = where, .aspects = aspects };
    where.* = "";
    if (tree.tag == .driver) try l.walk(tree);
}

// Zig tip: a test builds a small project in memory instead of on disk: here the matching of
// arguments is tried on a parsed driver and a parsed aspect, with no file read.
test "an apply is matched with the parameters of main" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diag = .{};
    const asp = try parser.parse(a, "exclusive aspect g is process main(who: String, greeting = \"Hi\" :String) is return; end g;", &d);
    var aspects: ast.Aspects = .empty;
    var where: []const u8 = "";
    var l: Linker = .{ .a = a, .io = undefined, .dir = ".", .diag = &d, .where = &where, .aspects = &aspects };
    const ok = try parser.parse(a, "driver t is process main is apply g(\"Eve\", greeting: \"Yo\"); return; end t;", &d);
    try l.match(ok.kids[0].kids[0].kids[0], asp);
    const bad = try parser.parse(a, "driver t is process main is apply g(42); return; end t;", &d);
    try std.testing.expectError(error.Syntax, l.match(bad.kids[0].kids[0].kids[0], asp));
    try std.testing.expectEqualStrings("the parameter 'who' is String, the argument is Integer", d.message());
}
