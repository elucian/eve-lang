//! The project of a run: the aspects its `apply` and `start` statements call (D-066, D-112, D-179). Eve is a
//! compiler first (D-110): before the run starts, every aspect it calls is found, read,
//! parsed and checked, and every `apply` is matched with the parameters of the `main` of that
//! aspect. A missing aspect, a wrong argument, a bad aspect file: all exit 65, and nothing runs.
//! The interpreter then finds the parsed aspect in the map built here and only runs it.
const std = @import("std");
const Io = std.Io;
const ast = @import("evecm").ast;
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

const Node = ast.Node;
pub const Diag = lexer.Diag;
pub const Error = lexer.Error;

const Linker = struct {
    a: std.mem.Allocator,
    io: Io,
    /// The folder of the aspect that is run: the project root.
    dir: []const u8,
    diag: *Diag,
    where: *[]const u8,
    aspects: *ast.Aspects,
    /// The modules that the imports of the root aspect, its aspects and its modules reach (modules.md).
    modules: *ast.Modules,
    /// The folders of `$EVE_LIB_PATH`, where external modules are installed (D-128).
    lib_path: []const []const u8 = &.{},
    /// The file of each aspect that was read, by the name written in the call: an error found while walking the calls
    /// of that aspect is reported in its file.
    paths: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn fail(l: *Linker, n: *const Node, comptime fmt: []const u8, args: anytype) Error {
        l.diag.set(n.line, n.col, fmt, args);
        return error.Syntax;
    }

    fn join(l: *Linker, comptime fmt: []const u8, args: anytype) Error![]const u8 {
        return std.fmt.allocPrint(l.a, fmt, args) catch return error.OutOfMemory;
    }

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

    /// Find, parse and check the aspect written `path` in an `apply`; remember it in the map.
    fn load(l: *Linker, at: *const Node) Error!*const Node {
        const key = at.text;
        if (l.aspects.get(key)) |known| return known;
        const file = try l.join("{s}.eve", .{key});
        const slash = std.mem.lastIndexOfScalar(u8, key, '/');
        const short = if (slash) |i| key[i + 1 ..] else key;
        // the folder written in the call comes first (D-112), then asp/, then the project root
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
        const tree = try parser.parseFile(l.a, src, l.diag, path);
        try l.paths.put(l.a, key, path);
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

    // @decision D-131
    /// The names a module exports, from its `export (...)` declarations.
    fn exportsOf(l: *Linker, m: *const Node) Error![]const []const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        for (m.kids) |k| {
            if (k.tag != .export_decl) continue;
            for (k.kids) |nm| try list.append(l.a, nm.text);
        }
        return list.items;
    }

    /// Is `name` one of `names`?
    fn isListed(names: []const []const u8, name: []const u8) bool {
        for (names) |n| if (std.mem.eql(u8, n, name)) return true;
        return false;
    }

    const Member = enum { none, shared, variable };

    // @decision D-068
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

    /// The folder an import path names: `$EVE_HOME` and `$EVE_LIB` are replaced, a path that starts
    /// with `/` is absolute, any other path is relative to `$EVE_HOME`, the folder of the root aspect (D-131).
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

    // @decision D-068
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
        const tree = try parser.parseFile(l.a, src, l.diag, file);
        // these three errors are in the importing script, at the import: `where` goes back to it
        if (tree.tag != .module or !std.mem.eql(u8, tree.text, name)) l.where.* = saved;
        if (tree.tag == .aspect) return l.fail(at, "'{s}' is an aspect: an aspect can't be imported, only a module can (D-126, D-179)", .{file});
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

    // @decision D-112
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

    // @decision D-112
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

    /// Check the members used through a module in a whole script.
    fn access(l: *Linker, tree: *const Node) Error!void {
        for (tree.kids) |k| try l.accessWalk(tree, k);
    }

    /// Is the variable declaration `k` of the module `m` atomic: typed `Atomic(:T)` or by a class derived from it?
    fn isAtomicVar(m: *const Node, k: *const Node) bool {
        const t = k.ty orelse return false;
        if (t.public) return true;
        for (m.kids) |c| {
            if (c.tag == .class and std.mem.eql(u8, c.text, t.text) and c.kids[1].tag == .name and std.mem.eql(u8, c.kids[1].text, "Atomic")) return true;
        }
        return false;
    }

    // @decision D-129
    /// Reject a `managed` module that has a plain variable or calls a module that is not managed.
    fn checkSafe(l: *Linker, m: *const Node) Error!void {
        for (m.kids) |k| {
            if (k.tag != .var_decl) continue;
            if (!isAtomicVar(m, k)) {
                return l.fail(k, "the managed module '{s}' has a variable that is not atomic: declare it :Atomic(:Type) (D-129, D-132)", .{m.text});
            }
        }
        for (m.kids) |k| try l.unsafeCalls(m, k, "the managed module");
    }

    fn exportsName(m: *const Node, name: []const u8) bool {
        for (m.kids) |k| {
            if (k.tag != .export_decl) continue;
            for (k.kids) |nm| if (std.mem.eql(u8, nm.text, name)) return true;
        }
        return false;
    }

    // @decision D-129
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

    /// Reject a call of a member of a module that is not managed, in the tree `n` of the module `tree`.
    fn unsafeCalls(l: *Linker, tree: *const Node, n: *const Node, who: []const u8) Error!void {
        if (n.tag == .call and n.kids[0].tag == .name) {
            if (l.bareOwner(tree, n.kids[0].text)) |other| {
                if (!other.public) return l.fail(n, "{s} '{s}' calls '{s}' of the module '{s}', and the module is not managed (D-129)", .{ who, tree.text, n.kids[0].text, other.text });
            }
        }
        if (n.tag == .field and n.kids[0].tag == .name) {
            if (l.moduleOf(tree, n.kids[0].text)) |other| {
                if (!other.public) return l.fail(n, "{s} '{s}' uses '{s}.{s}', and the module '{s}' is not managed (D-129)", .{ who, tree.text, other.text, n.text, other.text });
            }
        }
        for (n.kids) |k| try l.unsafeCalls(tree, k, who);
    }

    // @decision D-129
    /// Is the member `name` of the module `m` thread safe? A managed module: yes. Otherwise it must not touch a
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

    /// The `process main` of a parsed aspect.
    fn mainOf(aspect: *const Node) *const Node {
        for (aspect.kids) |k| if (k.tag == .process and std.mem.eql(u8, k.text, "main")) return k;
        unreachable; // the parser guarantees a process main (Parser.aspect)
    }

    // @decision D-179
    /// The process `name` of the aspect `cur`, or null.
    fn processOf(cur: *const Node, name: []const u8) ?*const Node {
        for (cur.kids) |k| if (k.tag == .process and std.mem.eql(u8, k.text, name)) return k;
        return null;
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

    /// Match the arguments of one `apply` with the parameters of `main`.
    fn match(l: *Linker, apply: *const Node, aspect: *const Node) Error!void {
        return l.matchParams(apply, aspect.text, mainOf(aspect).kids[3].kids);
    }

    // @decision D-179
    /// Match the arguments of one `apply` or `start` with the parameters `params` of the unit called `name`.
    fn matchParams(l: *Linker, apply: *const Node, name: []const u8, params: []const *const Node) Error!void {
        const aspect = .{ .text = name };
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

    // @decision D-179
    /// Walk the calls of the aspect `cur`, which is level `chain.len + 1` of the chain of calls (the first is level 1).
    fn walkAspect(l: *Linker, cur: *const Node, chain: *std.ArrayList(*const Node)) Error!void {
        try chain.append(l.a, cur);
        defer _ = chain.pop();
        for (cur.kids) |k| try l.walkNode(cur, k, chain);
    }

    // @decision D-140
    /// Find every `apply` and `start` under `n`; check each parallel group on the way.
    fn walkNode(l: *Linker, cur: *const Node, n: *const Node, chain: *std.ArrayList(*const Node)) Error!void {
        if (n.tag == .aspect) return;
        if (n.tag == .apply_stmt or n.tag == .start_stmt) try l.callOf(cur, n, chain);
        for (n.kids) |k| try l.walkNode(cur, k, chain);
        if (n.tag == .parallel) {
            try l.groupRules(cur, n, chain.items.len);
            try l.owners(n);
        }
    }

    /// One `apply` or `start`: a private process of `cur`, or another aspect to load, check and walk (D-179 to D-183).
    fn callOf(l: *Linker, cur: *const Node, n: *const Node, chain: *std.ArrayList(*const Node)) Error!void {
        const is_start = n.tag == .start_stmt;
        if (std.mem.indexOfScalar(u8, n.text, '/') == null) {
            if (processOf(cur, n.text)) |prc| {
                if (is_start and !cur.public) {
                    return l.fail(n, "{s} is serial: apply '{s}' instead of starting it, only a concurrent aspect starts its private processes (D-181)", .{ if (cur.primary) "a primary aspect" else "an exclusive aspect", n.text });
                }
                try l.matchParams(n, n.text, prc.kids[3].kids);
                @constCast(n).sel = prc;
                return;
            }
        }
        const aspect = try l.load(n);
        if (aspect.primary) {
            return l.fail(n, "a primary aspect is run by a command: it can't be applied or started ('{s}', D-181)", .{n.text});
        }
        if (is_start and !aspect.public) {
            return l.fail(n, "the aspect '{s}' can not be started: {s} is exclusive, start needs a concurrent aspect (D-130, D-140)", .{ n.text, aspect.text });
        }
        if (aspect.public and cur.public) {
            return l.fail(n, "a concurrent aspect is called from a primary or an exclusive aspect: '{s}' is called from the concurrent aspect '{s}' (D-183)", .{ aspect.text, cur.text });
        }
        // no cycle: an aspect already in the chain would be called again (D-179)
        for (chain.items, 0..) |c, i| {
            if (!std.mem.eql(u8, c.text, aspect.text)) continue;
            if (i == chain.items.len - 1) return l.fail(n, "{s} calls itself: an aspect can't call itself (D-179)", .{aspect.text});
            var text: std.ArrayList(u8) = .empty;
            for (chain.items[i..]) |m| try text.print(l.a, "{s} calls ", .{m.text});
            try text.appendSlice(l.a, aspect.text);
            return l.fail(n, "{s}: no chain of calls may come back to an aspect (D-179)", .{text.items});
        }
        if (chain.items.len >= 3) {
            return l.fail(n, "'{s}' is more than three levels deep: the chain of aspects is at most three levels (D-179)", .{aspect.text});
        }
        try l.match(n, aspect);
        const saved = l.where.*;
        l.where.* = l.paths.get(n.text) orelse saved;
        try l.walkAspect(aspect, chain);
        l.where.* = saved;
    }

    // @decision D-140
    // @decision D-179
    /// The rules of one parallel group, by the level of its aspect.
    fn groupRules(l: *Linker, cur: *const Node, group: *const Node, level: usize) Error!void {
        if (level >= 3) {
            return l.fail(group, "parallel is allowed only in an aspect of the first two levels: {s} is a leaf (D-140, D-179)", .{cur.text});
        }
        if (level == 2) {
            var count: usize = 0;
            var looped = false;
            countStarts(group, false, &count, &looped);
            if (count > 2 or looped) {
                return l.fail(group, "{s} starts more than 2 aspects: an aspect of the second level starts at most 2, none in a loop (D-081, D-140)", .{cur.text});
            }
        }
    }

    /// Count the `start` statements under `n`; `looped` becomes true when one of them sits in a loop.
    fn countStarts(n: *const Node, in_loop: bool, count: *usize, looped: *bool) void {
        if (n.tag == .start_stmt) {
            count.* += 1;
            if (in_loop) looped.* = true;
        }
        const loop = in_loop or n.tag == .for_ or n.tag == .while_ or n.tag == .repeat_;
        for (n.kids) |k| countStarts(k, loop, count, looped);
    }

    // @decision D-140
    /// Refuse the same output variable, or the same constant element, given to two starts of a group.
    fn owners(l: *Linker, group: *const Node) Error!void {
        var seen: std.ArrayList([]const u8) = .empty;
        try l.ownersIn(group.kids[1], false, &seen);
    }

    /// Is the parameter that receives the argument `a` (the `i`-th of the call) a `Channel`?
    fn sharedParam(params: []const *const Node, a: *const Node, i: usize) bool {
        var prm: ?*const Node = null;
        if (a.tag == .pair and a.kids[0].tag == .name) {
            for (params) |q| if (std.mem.eql(u8, q.text, a.kids[0].text)) {
                prm = q;
            };
        } else if (i < params.len) prm = params[i];
        const ty = (prm orelse return false).ty orelse return false;
        return std.mem.eql(u8, ty.text, "Channel");
    }

    /// The recursive part of `owners`: one `start` at a time, in the order of the source.
    fn ownersIn(l: *Linker, n: *const Node, in_loop: bool, seen: *std.ArrayList([]const u8)) Error!void {
        if (n.tag == .parallel) return;
        if (n.tag == .start_stmt) {
            const params = if (n.sel) |prc| prc.kids[3].kids else if (l.aspects.get(n.text)) |asp| mainOf(asp).kids[3].kids else &.{};
            for (n.kids, 0..) |a, i| {
                const r = if (a.tag == .pair) a.kids[1] else a;
                if (r.tag != .ref) continue;
                if (sharedParam(params, a, i)) continue; // a channel is the one object tasks share (D-141)
                var key: ?[]const u8 = null;
                if (r.kids.len == 0) {
                    key = r.text;
                } else if (r.kids[0].tag == .index and r.kids[0].kids.len == 2 and r.kids[0].kids[1].tag == .num) {
                    key = try l.join("{s}[{s}]", .{ r.text, r.kids[0].kids[1].text });
                }
                const k = key orelse continue;
                var twice = in_loop and r.kids.len == 0;
                for (seen.items) |s| if (std.mem.eql(u8, s, k)) {
                    twice = true;
                };
                if (twice) return l.fail(r, "Output {s} is given to two tasks of the group (D-140)", .{r.text});
                try seen.append(l.a, k);
            }
            return;
        }
        const loop = in_loop or n.tag == .for_ or n.tag == .while_ or n.tag == .repeat_;
        for (n.kids) |k| try l.ownersIn(k, loop, seen);
    }
};

// @decision D-128
/// The folders of `$EVE_LIB_PATH`, where external modules are installed.
pub var env_lib_path: []const []const u8 = &.{};

/// Link the aspect that is run: read every aspect it calls into `aspects`. On an error returns `error.Syntax`,
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
    if (tree.tag == .aspect) {
        if (tree.public) {
            return l.fail(tree, "a concurrent aspect is called from a primary or an exclusive aspect: a command does not run '{s}' (D-183)", .{tree.text});
        }
        // the aspects written in the macro are searched before asp/ and the project root (D-152)
        if (tree.macro) for (tree.kids) |k| if (k.tag == .aspect) {
            // an aspect of the macro with the name of a file of the project would be ambiguous (D-152)
            const in_asp = try l.join("{s}/asp/{s}.eve", .{ dir, k.text });
            const in_root = try l.join("{s}/{s}.eve", .{ dir, k.text });
            if (Io.Dir.cwd().access(io, in_asp, .{})) |_| {
                return l.fail(k, "aspect {s} is declared in the macro and in asp/{s}.eve", .{ k.text, k.text });
            } else |_| {}
            if (Io.Dir.cwd().access(io, in_root, .{})) |_| {
                return l.fail(k, "aspect {s} is declared in the macro and in {s}.eve", .{ k.text, k.text });
            } else |_| {}
            try aspects.put(a, k.text, k);
        };
        try l.imports(tree);
        try l.access(tree);
        var chain: std.ArrayList(*const Node) = .empty;
        try l.walkAspect(tree, &chain);
    }
}

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
    const ok = try parser.parse(a, "primary aspect t is process main is apply g(\"Eve\", greeting: \"Yo\"); return; end t;", &d);
    try l.match(ok.kids[0].kids[0].kids[0], asp);
    const bad = try parser.parse(a, "primary aspect t is process main is apply g(42); return; end t;", &d);
    try std.testing.expectError(error.Syntax, l.match(bad.kids[0].kids[0].kids[0], asp));
    try std.testing.expectEqualStrings("the parameter 'who' is String, the argument is Integer", d.message());
}

// @decision D-179
// @decision D-181
// @decision D-183
test "the calls between aspects: a primary aspect, a cycle, itself, a fourth level and a concurrent caller are refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diag = .{};
    var aspects: ast.Aspects = .empty;
    var where: []const u8 = "";
    var modules: ast.Modules = .empty;
    var l: Linker = .{ .a = a, .io = undefined, .dir = ".", .diag = &d, .where = &where, .aspects = &aspects, .modules = &modules };
    const sources = [_][2][]const u8{
        .{ "boss", "primary aspect boss is process main is return; end boss;" },
        .{ "ping", "exclusive aspect ping is process main is apply pong(); return; end ping;" },
        .{ "pong", "exclusive aspect pong is process main is apply ping(); return; end pong;" },
        .{ "again", "exclusive aspect again is process main is apply again(); return; end again;" },
        .{ "one", "exclusive aspect one is process main is apply two(); return; end one;" },
        .{ "two", "exclusive aspect two is process main is apply three(); return; end two;" },
        .{ "three", "exclusive aspect three is process main is apply four(); return; end three;" },
        .{ "four", "exclusive aspect four is process main is return; end four;" },
        .{ "work", "concurrent aspect work is process main is apply four(); return; end work;" },
        .{ "fine", "exclusive aspect fine is process main is apply four(); return; end fine;" },
    };
    for (sources) |s| try aspects.put(a, s[0], try parser.parse(a, s[1], &d));
    const cases = [_][2][]const u8{
        .{ "apply boss();", "a primary aspect is run by a command" },
        .{ "apply ping();", "ping calls pong calls ping" },
        .{ "apply again();", "again calls itself" },
        .{ "apply one();", "more than three levels" },
        .{ "apply work();", "" },
        .{ "apply fine();", "" },
    };
    for (cases) |c| {
        const src = try std.fmt.allocPrint(a, "primary aspect t is process main is {s} return; end t;", .{c[0]});
        const root = try parser.parse(a, src, &d);
        var chain: std.ArrayList(*const Node) = .empty;
        if (c[1].len == 0) {
            try l.walkAspect(root, &chain);
        } else {
            try std.testing.expectError(error.Syntax, l.walkAspect(root, &chain));
            try std.testing.expect(std.mem.indexOf(u8, d.message(), c[1]) != null);
        }
    }
    // a concurrent aspect that applies another concurrent aspect
    try aspects.put(a, "inner", try parser.parse(a, "concurrent aspect inner is process main is return; end inner;", &d));
    try aspects.put(a, "outer", try parser.parse(a, "concurrent aspect outer is process main is apply inner(); return; end outer;", &d));
    const root = try parser.parse(a, "primary aspect t is process main is apply outer(); return; end t;", &d);
    var chain: std.ArrayList(*const Node) = .empty;
    try std.testing.expectError(error.Syntax, l.walkAspect(root, &chain));
    try std.testing.expect(std.mem.indexOf(u8, d.message(), "a concurrent aspect is called from a primary or an exclusive aspect") != null);
}

// @decision D-179
// @decision D-181
test "a private process is called by its bare name, and only a concurrent aspect starts one" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d: Diag = .{};
    var aspects: ast.Aspects = .empty;
    var where: []const u8 = "";
    var modules: ast.Modules = .empty;
    var l: Linker = .{ .a = a, .io = undefined, .dir = ".", .diag = &d, .where = &where, .aspects = &aspects, .modules = &modules };
    const ok = try parser.parse(a, "primary aspect t is process work(n: Integer) is return; process main is apply work(1); return; end t;", &d);
    var chain: std.ArrayList(*const Node) = .empty;
    try l.walkAspect(ok, &chain);
    const bad = try parser.parse(a, "primary aspect t is process work is return; process main is parallel do start work(); done; return; end t;", &d);
    try std.testing.expectError(error.Syntax, l.walkAspect(bad, &chain));
    try std.testing.expect(std.mem.indexOf(u8, d.message(), "a primary aspect is serial") != null);
    const wrong = try parser.parse(a, "primary aspect t is process work(n: Integer) is return; process main is apply work(\"x\"); return; end t;", &d);
    try std.testing.expectError(error.Syntax, l.walkAspect(wrong, &chain));
}
