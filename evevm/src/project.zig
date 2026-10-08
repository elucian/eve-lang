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
    /// The modules that the imports of the driver, its aspects and its modules reach (modules.md).
    modules: *ast.Modules,
    /// The folders of `$EVE_LIB_PATH`, where external modules are installed (D-128).
    lib_path: []const []const u8 = &.{},

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
        if (tree.tag != .aspect) return l.fail(at, "'{s}' is not an aspect: apply runs only aspects", .{path});
        if (!std.mem.eql(u8, tree.text, short)) {
            return l.fail(at, "the file '{s}' declares the aspect '{s}': the names must be equal", .{ path, tree.text });
        }
        try l.aspects.put(l.a, key, tree);
        try l.imports(tree);
        try l.access(tree);
        if (tree.public) for (tree.kids) |k| try l.concurrentCalls(tree, k);
        l.where.* = "";
        return tree;
    }


    // ---- modules (spec/semantics/modules.md) -----------------------------------------------------

    // Zig tip: `?*const Node` is "a node, or nothing": a module that is not found is not a compile error
    // (it is the run-time error `$err_module`, D-131), so the search answers `null` and the caller
    // decides. `catch null` turns the error of opening a folder into the same "nothing".
    /// The names a module exports, from its `export (...)` declarations.
    fn exportsOf(l: *Linker, m: *const Node) Error![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        for (m.kids) |k| {
            if (k.tag != .export_decl) continue;
            for (k.kids) |nm| try list.append(l.a, nm.text);
        }
        return list.items;
    }

    // Zig tip: a function that only reads its arguments and answers yes or no is declared without `pub` and
    // with a plain `bool`: `for (names) |n| if (...) return true;` stops at the first hit, and the `return
    // false` after the loop is the answer when there was none.
    /// Is `name` one of `names`?
    fn isListed(names: []const []const u8, name: []const u8) bool {
        for (names) |n| if (std.mem.eql(u8, n, name)) return true;
        return false;
    }

    const Member = enum { none, shared, variable };

    // Zig tip: an `enum` names the answers of a question: the member is shared (a function, a procedure,
    // a class or a constant), a variable (which can not be shared, D-068) or not declared at all.
    /// What a module declares under `name`.
    fn memberKind(m: *const Node, name: []const u8) Member {
        for (m.kids) |k| {
            switch (k.tag) {
                .function, .procedure, .class => if (std.mem.eql(u8, k.text, name)) return .shared,
                .set, .var_decl => {
                    for (k.kids[0].kids) |t| {
                        if (t.tag == .name and std.mem.eql(u8, t.text, name)) return if (k.tag == .set) .shared else .variable;
                    }
                },
                else => {},
            }
        }
        return .none;
    }

    // Zig tip: `std.mem.startsWith(u8, text, prefix)` tests the beginning of a text. The longer
    // system variable is tried first, because `$EVE_LIB_PATH` also starts with `$EVE_LIB`.
    /// The folder an import path names: `$EVE_HOME` and `$EVE_LIB` are replaced, a path that starts
    /// with `/` is absolute, any other path is relative to `$EVE_HOME`, the folder of the driver (D-131).
    fn folderOf(l: *Linker, path: []const u8) Error![]const u8 {
        var text = path;
        if (std.mem.startsWith(u8, text, "$EVE_HOME")) {
            text = text["$EVE_HOME".len..];
            if (text.len > 0 and text[0] == '/') text = text[1..];
            return if (text.len == 0) l.dir else l.join("{s}/{s}", .{ l.dir, text });
        }
        if (std.mem.startsWith(u8, text, "$EVE_LIB")) {
            const rest = text["$EVE_LIB".len..];
            return l.join("{s}/lib{s}", .{ l.dir, rest });
        }
        if (text.len > 0 and text[0] == '/') return text;
        return l.join("{s}/{s}", .{ l.dir, text });
    }

    // Zig tip: `std.mem.tokenizeAny(u8, text, "/\\")` walks the pieces of a text between any of the separators
    // and skips the empty ones. `parts.pop()` removes the last piece, which is how `lib/../lib` goes back to
    // `lib`. `std.mem.join(allocator, "/", pieces)` glues the pieces again. Two spellings of one file, `./lib/c.eve`
    // and `lib/c.eve`, give the same text, and so the same module (D-068: a module is loaded once).
    /// The path of a file in one standard spelling: no `.`, no empty part, no `..` that can be resolved, only `/`.
    fn canonical(l: *Linker, path: []const u8) Error![]const u8 {
        var parts: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeAny(u8, path, "/\\");
        while (it.next()) |part| {
            if (std.mem.eql(u8, part, ".")) continue;
            if (std.mem.eql(u8, part, "..") and parts.items.len > 0 and !std.mem.eql(u8, parts.items[parts.items.len - 1], "..")) {
                _ = parts.pop();
                continue;
            }
            try parts.append(l.a, part);
        }
        const joined = try std.mem.join(l.a, "/", parts.items);
        return if (path.len > 0 and path[0] == '/') l.join("/{s}", .{joined}) else joined;
    }

    // Zig tip: `[_][]const u8{ a, b }` is an array whose length the compiler counts. The file of a module is
    // searched in the folder of the import, then in every folder of `$EVE_LIB_PATH`, as `<folder>/<path>/m.eve`,
    // `<folder>/m.eve` and `<folder>/m/m.eve` (a package installed in its own folder).
    /// Find, read, parse and check the module `name` of the import path `path`; remember it. `null`: not found.
    fn loadModule(l: *Linker, at: *const Node, path: []const u8, name: []const u8) Error!?*const Node {
        const key = try l.join("{s}|{s}", .{ path, name });
        if (l.modules.get(key)) |known| return known;
        var cands: std.ArrayList([]const u8) = .empty;
        const folder = try l.folderOf(path);
        try cands.append(l.a, try l.join("{s}/{s}.eve", .{ folder, name }));
        for (l.lib_path) |lp| {
            try cands.append(l.a, try l.join("{s}/{s}/{s}.eve", .{ lp, path, name }));
            try cands.append(l.a, try l.join("{s}/{s}.eve", .{ lp, name }));
            try cands.append(l.a, try l.join("{s}/{s}/{s}.eve", .{ lp, name, name }));
        }
        var file: []const u8 = "";
        const src = l.read(cands.items, &file) orelse return null;
        // the same file reached by another spelling of the path is the same module (singleton)
        const file_key = try l.join("file:{s}", .{try l.canonical(file)});
        if (l.modules.get(file_key)) |same| {
            try l.modules.put(l.a, key, same);
            return same;
        }
        const saved = l.where.*;
        l.where.* = file;
        const tree = try parser.parse(l.a, src, l.diag);
        // these three errors are in the importing script, at the import: `where` goes back to it
        if (tree.tag == .script or tree.tag != .module or !std.mem.eql(u8, tree.text, name)) l.where.* = saved;
        if (tree.tag == .script) return l.fail(at, "'{s}' is a free script: a free script can't export anything and can't be imported (D-126)", .{file});
        if (tree.tag != .module) return l.fail(at, "'{s}' is not a module: from … use imports only modules", .{file});
        if (!std.mem.eql(u8, tree.text, name)) {
            return l.fail(at, "the file '{s}' declares the module '{s}': the names must be equal", .{ file, tree.text });
        }
        for (try l.exportsOf(tree)) |nm| {
            switch (memberKind(tree, nm)) {
                .shared => {},
                .variable => return l.fail(tree, "the module '{s}' exports the variable '{s}': a module has no public variables (D-068)", .{ name, nm }),
                .none => return l.fail(tree, "the module '{s}' exports '{s}', which it does not declare", .{ name, nm }),
            }
        }
        try l.modules.put(l.a, key, tree);
        try l.modules.put(l.a, file_key, tree);
        try l.imports(tree);
        try l.access(tree);
        if (tree.public) try l.checkSafe(tree);
        l.where.* = saved;
        return tree;
    }

    // Zig tip: `std.mem.endsWith(u8, text, suffix)` tests the end of a text; the stem of a file is what
    // comes before the last dot. Every module of a folder is read for the import `use (*)`; a file that
    // is not a module is skipped, so a folder may hold other things.
    /// Load every module of the folder of `path`, for `use (*)`; the key `path|*` holds them all.
    fn loadFolder(l: *Linker, at: *const Node, path: []const u8) Error!void {
        const folder = try l.folderOf(path);
        var dir = Io.Dir.cwd().openDir(l.io, folder, .{ .iterate = true }) catch return;
        defer dir.close(l.io);
        var all: std.ArrayList(*const Node) = .empty;
        var it = dir.iterate();
        while (it.next(l.io) catch null) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".eve")) continue;
            const stem = entry.name[0 .. entry.name.len - 4];
            if (try l.loadModule(at, path, try l.join("{s}", .{stem}))) |m| try all.append(l.a, m);
        }
        const block = try l.a.create(Node);
        block.* = .{ .tag = .block, .line = at.line, .col = at.col, .kids = all.items };
        try l.modules.put(l.a, try l.join("{s}|*", .{path}), block);
    }

    // Zig tip: the names of two lists meet in a double loop. `seen` is the modules that give bare names
    // so far: a name in two of them is a conflict (D-112 a), and the message lists the two modules.
    /// Read the modules of every import of `tree` and check the names they merge.
    fn imports(l: *Linker, tree: *const Node) Error!void {
        var seen: std.ArrayList(*const Node) = .empty;
        for (tree.kids) |decl| {
            if (decl.tag != .import_decl) continue;
            for (decl.kids) |item| {
                const star = std.mem.eql(u8, item.text, "*");
                if (star) {
                    try l.loadFolder(item, decl.text);
                    const set = l.modules.get(try l.join("{s}|*", .{decl.text})) orelse continue;
                    for (set.kids) |m| try l.merge(item, &seen, m);
                } else if (try l.loadModule(item, decl.text, item.text)) |m| {
                    if (item.public) try l.merge(item, &seen, m);
                }
            }
        }
    }

    // Zig tip: `merge` relies on the same Zig feature as `imports` above: see the tip there.
    /// Check that the names of the module `m` do not collide with those of the modules already merged.
    fn merge(l: *Linker, at: *const Node, seen: *std.ArrayList(*const Node), m: *const Node) Error!void {
        const mine = try l.exportsOf(m);
        for (seen.items) |other| {
            if (other == m) return;
            for (try l.exportsOf(other)) |nm| {
                if (isListed(mine, nm)) {
                    return l.fail(at, "the name '{s}' comes from the modules '{s}' and '{s}': list the modules one by one (modules.md)", .{ nm, other.text, m.text });
                }
            }
        }
        try seen.append(l.a, m);
    }

    // Zig tip: `std.StringHashMapUnmanaged([]const u8)`-free: the aliases of a script are found again by a
    // walk over its import declarations, so no table is stored. The module of an alias is looked up by the
    // key of the import. `null` means that the name is not the module of an import.
    /// The module that the name `name` stands for in the imports of `tree` (a module name or an alias).
    fn moduleOf(l: *Linker, tree: *const Node, name: []const u8) ?*const Node {
        for (tree.kids) |decl| {
            if (decl.tag != .import_decl) continue;
            for (decl.kids) |item| {
                if (item.public or std.mem.eql(u8, item.text, "*")) continue;
                const bound = if (item.kids[0].tag == .name) item.kids[0].text else item.text;
                if (!std.mem.eql(u8, bound, name)) continue;
                const key = std.fmt.allocPrint(l.a, "{s}|{s}", .{ decl.text, item.text }) catch return null;
                return l.modules.get(key);
            }
        }
        return null;
    }

    // Zig tip: a recursive function over the tree, like `walk`: `anyerror`-free, its errors are those of `Error`.
    // `m.name` on a module that is not exported is refused at check time, exit 65 (D-112 b, c08).
    /// Every `module.member` of `n` must name an exported member of the module.
    fn accessWalk(l: *Linker, tree: *const Node, n: *const Node) Error!void {
        if (n.tag == .call and n.kids[0].tag == .name) {
            if (l.moduleOf(tree, n.kids[0].text)) |m| {
                return l.fail(n, "'{s}' is a module: a module has no instances, it can't be created or called (D-068)", .{m.text});
            }
        }
        if (n.tag == .field and n.kids[0].tag == .name) {
            if (l.moduleOf(tree, n.kids[0].text)) |m| {
                if (!isListed(try l.exportsOf(m), n.text)) {
                    return l.fail(n, "'{s}' is not exported by the module '{s}'", .{ n.text, m.text });
                }
            }
        }
        for (n.kids) |k| try l.accessWalk(tree, k);
    }

    // Zig tip: `access` relies on the same Zig feature as `accessWalk` above: see the tip there.
    /// Check the members used through a module in a whole script.
    fn access(l: *Linker, tree: *const Node) Error!void {
        for (tree.kids) |k| try l.accessWalk(tree, k);
    }

    // Zig tip: `k.ty` is `?*const Node`, an optional: `if (k.ty) |t|` runs only when the variable has a type
    // hint. `Atomic(:Integer)` was read by the parser as `Integer` with `public` set; a class of the module
    // that is derived from `Atomic(...)` makes its own name atomic too (`class SageInteger <: Atomic(:Integer);`).
    /// Is the variable declaration `k` of the module `m` atomic: typed `Atomic(:T)` or by a class derived from it?
    fn isAtomicVar(m: *const Node, k: *const Node) bool {
        const t = k.ty orelse return false;
        if (t.public) return true;
        for (m.kids) |c| {
            if (c.tag == .class and std.mem.eql(u8, c.text, t.text) and c.kids[1].tag == .name and std.mem.eql(u8, c.kids[1].text, "Atomic")) return true;
        }
        return false;
    }

    // Zig tip: a safe module is checked with two plain rules (D-129): each variable is atomic (`isAtomicVar`),
    // and no call goes to a member of an unsafe module.
    /// Reject a `safe` module that has a plain variable or calls a module that is not safe.
    fn checkSafe(l: *Linker, m: *const Node) Error!void {
        for (m.kids) |k| {
            if (k.tag != .var_decl) continue;
            if (!isAtomicVar(m, k)) {
                return l.fail(k, "the safe module '{s}' has a variable that is not atomic: declare it :Atomic(:Type) (D-129, D-132)", .{m.text});
            }
        }
        for (m.kids) |k| try l.unsafeCalls(m, k, "the safe module");
    }

    fn exportsName(m: *const Node, name: []const u8) bool {
        for (m.kids) |k| {
            if (k.tag != .export_decl) continue;
            for (k.kids) |nm| if (std.mem.eql(u8, nm.text, name)) return true;
        }
        return false;
    }

    // Zig tip: `orelse continue` inside a loop skips to the next item when a lookup finds nothing. A bare name
    // (`poke()` after `use (u(*))`) belongs to the module that exports it; a name that the script declares
    // itself is not looked up, because the local one wins. The thread safety checks use the owner like they
    // use the prefix of `u.poke()`, so `m(*)` and `(*)` can not hide an unsafe call (D-129).
    /// The module that gives the bare name `name` to the script `tree` through `m(*)` or `*`, or null.
    fn bareOwner(l: *Linker, tree: *const Node, name: []const u8) ?*const Node {
        if (memberKind(tree, name) != .none) return null;
        for (tree.kids) |decl| {
            if (decl.tag != .import_decl) continue;
            for (decl.kids) |item| {
                if (std.mem.eql(u8, item.text, "*")) {
                    const key = std.fmt.allocPrint(l.a, "{s}|*", .{decl.text}) catch return null;
                    const set = l.modules.get(key) orelse continue;
                    for (set.kids) |m| if (exportsName(m, name)) return m;
                } else if (item.public) {
                    const key = std.fmt.allocPrint(l.a, "{s}|{s}", .{ decl.text, item.text }) catch return null;
                    const m = l.modules.get(key) orelse continue;
                    if (exportsName(m, name)) return m;
                }
            }
        }
        return null;
    }

    // Zig tip: `unsafeCalls` relies on the same Zig feature as `accessWalk` above: see the tip there.
    /// Reject a call of a member of a module that is not safe, in the tree `n` of the module `tree`.
    fn unsafeCalls(l: *Linker, tree: *const Node, n: *const Node, who: []const u8) Error!void {
        if (n.tag == .call and n.kids[0].tag == .name) {
            if (l.bareOwner(tree, n.kids[0].text)) |other| {
                if (!other.public) return l.fail(n, "{s} '{s}' calls '{s}' of the module '{s}', and the module is not safe (D-129)", .{ who, tree.text, n.kids[0].text, other.text });
            }
        }
        if (n.tag == .field and n.kids[0].tag == .name) {
            if (l.moduleOf(tree, n.kids[0].text)) |other| {
                if (!other.public) return l.fail(n, "{s} '{s}' uses '{s}.{s}', and the module '{s}' is not safe (D-129)", .{ who, tree.text, other.text, n.text, other.text });
            }
        }
        for (n.kids) |k| try l.unsafeCalls(tree, k, who);
    }

    // Zig tip: `visiting` is the list of the members being examined: a function that calls itself would
    // loop for ever, so a name already in the list counts as safe for now. This is the check of a
    // `concurrent` aspect (level 4, D-129): it calls only members that the compiler proves thread safe.
    /// Is the member `name` of the module `m` thread safe? A safe module: yes. Otherwise it must not touch a
    /// variable of the module, nor call an unsafe member.
    fn memberSafe(l: *Linker, m: *const Node, name: []const u8, visiting: *std.ArrayList([]const u8)) Error!bool {
        if (m.public) return true;
        if (isListed(visiting.items, name)) return true;
        try visiting.append(l.a, name);
        defer _ = visiting.pop();
        for (m.kids) |k| {
            if ((k.tag == .function or k.tag == .procedure) and std.mem.eql(u8, k.text, name)) return l.bodySafe(m, k, visiting);
        }
        return true;
    }

    // Zig tip: `bodySafe` relies on the same Zig feature as `memberSafe` above: see the tip there.
    /// Does the code of `n` leave the module `m` thread safe? No variable of the module, no unsafe call.
    fn bodySafe(l: *Linker, m: *const Node, n: *const Node, visiting: *std.ArrayList([]const u8)) Error!bool {
        if (n.tag == .name) {
            if (l.bareOwner(m, n.text)) |other| if (!try l.memberSafe(other, n.text, visiting)) return false;
            if (memberKind(m, n.text) == .variable) return false;
            for (m.kids) |k| {
                if ((k.tag == .function or k.tag == .procedure) and std.mem.eql(u8, k.text, n.text)) {
                    if (!try l.memberSafe(m, n.text, visiting)) return false;
                }
            }
        }
        if (n.tag == .field and n.kids[0].tag == .name) {
            if (l.moduleOf(m, n.kids[0].text)) |other| if (!try l.memberSafe(other, n.text, visiting)) return false;
        }
        for (n.kids) |k| if (!try l.bodySafe(m, k, visiting)) return false;
        return true;
    }

    // Zig tip: `concurrentCalls` relies on the same Zig feature as `accessWalk` above: see the tip there.
    /// Reject the call of a member that is not thread safe, in the tree of a `concurrent` aspect.
    fn concurrentCalls(l: *Linker, tree: *const Node, n: *const Node) Error!void {
        if (n.tag == .call and n.kids[0].tag == .name) {
            if (l.bareOwner(tree, n.kids[0].text)) |m| {
                var visiting: std.ArrayList([]const u8) = .empty;
                if (!try l.memberSafe(m, n.kids[0].text, &visiting)) {
                    return l.fail(n, "the concurrent aspect '{s}' calls '{s}' of the module '{s}', which is not thread safe (D-129)", .{ tree.text, n.kids[0].text, m.text });
                }
            }
        }
        if (n.tag == .field and n.kids[0].tag == .name) {
            if (l.moduleOf(tree, n.kids[0].text)) |m| {
                var visiting: std.ArrayList([]const u8) = .empty;
                if (!try l.memberSafe(m, n.text, &visiting)) {
                    return l.fail(n, "the concurrent aspect '{s}' calls '{s}.{s}', which is not thread safe (D-129)", .{ tree.text, m.text, n.text });
                }
            }
        }
        for (n.kids) |k| try l.concurrentCalls(tree, k);
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

// Zig tip: a `pub var` at file level is a global that other files can read and set. `main` fills it once
// at the start, from the environment variable `EVE_LIB_PATH` (D-128), and the link step reads it. It is
// the only global of this file: a list of folders, empty when the variable is not set.
/// The folders of `$EVE_LIB_PATH`, where external modules are installed.
pub var env_lib_path: []const []const u8 = &.{};

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
    modules: *ast.Modules,
    lib_path: []const []const u8,
) Error!void {
    var l: Linker = .{ .a = a, .io = io, .dir = dir, .diag = diag, .where = where, .aspects = aspects, .modules = modules, .lib_path = lib_path };
    where.* = "";
    if (tree.tag == .driver) {
        try l.imports(tree);
        try l.access(tree);
        try l.walk(tree);
    }
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
    var modules: ast.Modules = .empty;
    var l: Linker = .{ .a = a, .io = undefined, .dir = ".", .diag = &d, .where = &where, .aspects = &aspects, .modules = &modules };
    const ok = try parser.parse(a, "driver t is process main is apply g(\"Eve\", greeting: \"Yo\"); return; end t;", &d);
    try l.match(ok.kids[0].kids[0].kids[0], asp);
    const bad = try parser.parse(a, "driver t is process main is apply g(42); return; end t;", &d);
    try std.testing.expectError(error.Syntax, l.match(bad.kids[0].kids[0].kids[0], asp));
    try std.testing.expectEqualStrings("the parameter 'who' is String, the argument is Integer", d.message());
}
