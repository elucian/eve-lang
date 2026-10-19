//! The commands of the database part (`eve db`): `db proc list`.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const Io = std.Io;
const parser = @import("evecp").parser;
const ast = @import("evecm").ast;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const Context = context.Context;
const exit_usage = context.exit_usage;
const exit_syntax = context.exit_syntax;
const exit_no_input = context.exit_no_input;
const exit_cant_create = context.exit_cant_create;

// Zig tip: the VM session is created the first time a command needs it and kept in the Context, so
// Zig tip: a splitter is a small state machine: it walks the bytes once and remembers whether it is inside a quoted
// text or a comment, where a `;` does not end the statement. The pieces are slices of the original text, so nothing is
// copied; `ArrayList.append` needs the allocator because the list grows.
/// Split SQL text at the `;` that are outside quotes and comments.
fn splitStatements(gpa: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '\'' or c == '"') {
            i += 1;
            while (i < text.len and text[i] != c) i += 1;
        } else if (c == '-' and i + 1 < text.len and text[i + 1] == '-') {
            while (i < text.len and text[i] != '\n') i += 1;
        } else if (c == '/' and i + 1 < text.len and text[i + 1] == '*') {
            i += 2;
            while (i + 1 < text.len and !(text[i] == '*' and text[i + 1] == '/')) i += 1;
            i += 1;
        } else if (c == ';') {
            try out.append(gpa, text[start..i]);
            start = i + 1;
        }
    }
    if (start < text.len) try out.append(gpa, text[start..]);
    return out.toOwnedSlice(gpa);
}

// Zig tip: an arena allocator frees everything at once when it is dropped, so the rows and the copies of the cells need
// no `free` of their own. `st.columnText` points into SQLite's memory that changes at the next `step`, so each cell is
// copied with `dupe` before the next row is read. `splatByteAll(' ', n)` writes n spaces: the padding of the columns.
// The options come first: `-t` writes the rows as text with tabs between the cells (for a program to read), `--last` writes
// only the result of the last statement (a script that prepares data and then asks), `-f <script>` reads the statements
// from a file (a script too long for a command line). A writer that discards what is written (`Io.Writer.Discarding`)
// stands in for the output of the statements that must stay silent.
/// `db sql [-t] [--last] [-f <script>] <file|:memory:> [<statement>]`: run the SQL statements on a SQLite file and print
/// each result as a table. The tool of the SQL panel of evetx; the statements end with `;`.
fn sqlCommand(ctx: *Context, args: []const []const u8) !void {
    const sqlite = @import("evedb").sqlite;
    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var tsv = false;
    var last_only = false;
    var script_path: ?[]const u8 = null;
    var k: usize = 0;
    while (k < args.len and args[k].len > 1 and args[k][0] == '-') : (k += 1) {
        if (std.mem.eql(u8, args[k], "-t")) {
            tsv = true;
        } else if (std.mem.eql(u8, args[k], "--last")) {
            last_only = true;
        } else if (std.mem.eql(u8, args[k], "-f") and k + 1 < args.len) {
            k += 1;
            script_path = args[k];
        } else break;
    }
    if (k >= args.len) {
        try ctx.out.writeAll("error: db sql needs a database file\n");
        ctx.status = exit_usage;
        return;
    }
    const path = try a.dupeSentinel(u8, args[k], 0);
    var db = sqlite.Db.open(path) catch {
        try ctx.out.print("error: cannot open {s}\n", .{args[k]});
        ctx.status = exit_no_input;
        return;
    };
    defer db.close();
    const typed = try std.mem.join(a, " ", args[k + 1 ..]);
    const text = if (script_path) |sp| blk: {
        const script = Io.Dir.cwd().readFileAlloc(ctx.io, sp, a, .limited(64 << 20)) catch {
            try ctx.out.print("error: cannot read {s}\n", .{sp});
            ctx.status = exit_no_input;
            return;
        };
        // the script first, then the statements typed after the file name
        break :blk if (typed.len > 0) try std.fmt.allocPrint(a, "{s}\n;\n{s}", .{ script, typed }) else script;
    } else typed;
    ctx.status = 0;
    var pieces: std.ArrayList([]const u8) = .empty;
    for (try splitStatements(a, text)) |piece| {
        const t = std.mem.trim(u8, piece, " \t\r\n");
        if (t.len > 0) try pieces.append(a, t);
    }
    var discard_buf: [64]u8 = undefined;
    var discard = Io.Writer.Discarding.init(&discard_buf);
    const max_rows: usize = if (tsv) 5000 else 1000;
    for (pieces.items, 0..) |stmt_text, idx| {
        const out: *Io.Writer = if (last_only and idx + 1 < pieces.items.len) &discard.writer else ctx.out;
        var st = db.prepare(try a.dupeSentinel(u8, stmt_text, 0)) catch {
            try ctx.out.print("error: {s}\n", .{db.errorMessage()});
            ctx.status = exit_syntax;
            return;
        };
        defer st.finalize();
        const ncols = st.columnCount();
        var rows: std.ArrayList([]const []const u8) = .empty;
        var widths = try a.alloc(usize, ncols);
        for (0..ncols) |c| widths[c] = st.columnName(@intCast(c)).len;
        while (st.step() catch {
            try ctx.out.print("error: {s}\n", .{db.errorMessage()});
            ctx.status = exit_syntax;
            return;
        }) {
            const cells = try a.alloc([]const u8, ncols);
            for (0..ncols) |c| {
                const raw = try a.dupe(u8, if (st.columnKind(@intCast(c)) == .null) (if (tsv) "" else "NULL") else st.columnText(@intCast(c)));
                if (tsv) for (raw) |*ch| {
                    if (ch.* == '\t' or ch.* == '\n' or ch.* == '\r') ch.* = ' ';
                };
                cells[c] = raw;
                widths[c] = @max(widths[c], raw.len);
            }
            try rows.append(a, cells);
            if (rows.items.len >= max_rows) break;
        }
        if (ncols == 0) {
            if (!tsv) try out.print("ok, {d} changes\n", .{db.changes()});
            continue;
        }
        if (tsv) {
            for (0..ncols) |c| {
                if (c > 0) try out.writeAll("\t");
                try out.writeAll(st.columnName(@intCast(c)));
            }
            try out.writeAll("\n");
            for (rows.items) |cells| {
                for (cells, 0..) |cell, c| {
                    if (c > 0) try out.writeAll("\t");
                    try out.writeAll(cell);
                }
                try out.writeAll("\n");
            }
            continue;
        }
        for (0..ncols) |c| {
            const name = st.columnName(@intCast(c));
            try out.writeAll(if (c == 0) "" else " | ");
            try out.writeAll(name);
            try out.splatByteAll(' ', widths[c] - name.len);
        }
        try out.writeAll("\n");
        for (0..ncols) |c| {
            try out.writeAll(if (c == 0) "" else "-+-");
            try out.splatByteAll('-', widths[c]);
        }
        try out.writeAll("\n");
        for (rows.items) |cells| {
            for (cells, 0..) |cell, c| {
                try out.writeAll(if (c == 0) "" else " | ");
                try out.writeAll(cell);
                try out.splatByteAll(' ', widths[c] - cell.len);
            }
            try out.writeAll("\n");
        }
        try out.print("({d} rows{s})\n", .{ rows.items.len, if (rows.items.len >= max_rows) ", cut" else "" });
    }
}

// Zig tip: `cmdDb` relies on the same Zig feature as `cmdDoc`: the work is done by a function with an inferred error
// set, and the handler passes on `WriteFailed` and turns every other error into a message.
/// `db`: the commands of the database part (`eve db ...`, D-163). Today `db proc list`.
// Zig tip: a database object is made or dropped with a statement that the command builds from its words: the name is put
// between double quotes (a name with a quote in it is refused), and the select is what the person typed after the name. The
// statement then goes through `sqlCommand`, like any `db sql`, so the answer and the exit status are the same.
/// `db create view|table <file> <name> <select…>` and `db drop view <file> <name>`.
fn objectCommand(ctx: *Context, args: []const []const u8) !void {
    const create = std.mem.eql(u8, args[0], "create");
    const kind = args[1];
    const is_view = std.mem.eql(u8, kind, "view");
    const is_table = std.mem.eql(u8, kind, "table");
    const ok_shape = if (create) (is_view or is_table) and args.len >= 5 else is_view and args.len == 4;
    if (!ok_shape or std.mem.indexOfScalar(u8, args[3], '"') != null) {
        try ctx.out.writeAll("db: usage: db create view|table <file> <name> <select…> | db drop view <file> <name>\n");
        ctx.status = exit_usage;
        return;
    }
    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const stmt = if (create)
        try std.fmt.allocPrint(a, "create {s} \"{s}\" as {s}", .{ kind, args[3], try std.mem.join(a, " ", args[4..]) })
    else
        try std.fmt.allocPrint(a, "drop view \"{s}\"", .{args[3]});
    const words = [_][]const u8{ args[2], stmt };
    sqlCommand(ctx, &words) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("db {s}: {s}\n", .{ args[0], @errorName(err) });
            ctx.status = exit_no_input;
        },
    };
}

// Zig tip: `db import` reads the whole file, decodes it into a columnar table (the types are found by looking at the values)
// and loads it into the database as a new table, in one transaction: nothing is left half done when a row is bad. `db export`
// does the opposite. The name of the table defaults to the name of the file without its extension, with every character that
// is not a letter or a digit turned into `_`. The answer is one line, so a program (evetx) can show it.
/// `db import <db> <file> [table]` and `db export <db> <table> <file>`.
fn transferCommand(ctx: *Context, args: []const []const u8) !void {
    const evedb = @import("evedb");
    const import_mod = evedb.importer;
    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const is_import = std.mem.eql(u8, args[0], "import");
    if (args.len < 3 or args.len > 4 or (!is_import and args.len != 4)) {
        try ctx.out.writeAll("db: usage: db import <file.db> <file> [table] | db export <file.db> <table> <file>\n");
        ctx.status = exit_usage;
        return;
    }
    const db_path = try a.dupeSentinel(u8, args[1], 0);
    const file = if (is_import) args[2] else args[3];
    const format = import_mod.formatOf(file) orelse {
        try ctx.out.print("error: {s}: the formats are .csv .txt .tsv .json .dbf (save a spreadsheet as CSV)\n", .{file});
        ctx.status = exit_usage;
        return;
    };
    var db = evedb.sqlite.Db.open(db_path) catch {
        try ctx.out.print("error: cannot open {s}\n", .{args[1]});
        ctx.status = exit_no_input;
        return;
    };
    defer db.close();
    ctx.status = 0;
    if (is_import) {
        const bytes = Io.Dir.cwd().readFileAlloc(ctx.io, file, a, .limited(1 << 30)) catch {
            try ctx.out.print("error: cannot read {s}\n", .{file});
            ctx.status = exit_no_input;
            return;
        };
        var name: []u8 = undefined;
        if (args.len == 4) {
            name = try a.dupe(u8, args[3]);
        } else {
            name = try a.dupe(u8, std.fs.path.stem(file));
            for (name) |*ch| {
                if (!std.ascii.isAlphanumeric(ch.*)) ch.* = '_';
            }
        }
        const res = import_mod.importInto(ctx.gpa, &db, bytes, format, name) catch |err| {
            if (err == error.Exec) {
                try ctx.out.print("error: {s}\n", .{db.errorMessage()});
            } else try ctx.out.print("error: {s}: {s}\n", .{ file, @errorName(err) });
            ctx.status = exit_syntax;
            return;
        };
        try ctx.out.print("imported {d} rows, {d} columns into {s}\n", .{ res.rows, res.cols, name });
        return;
    }
    const now = Io.Timestamp.now(ctx.io, .real).toSeconds();
    const es = std.time.epoch.EpochSeconds{ .secs = @intCast(@max(now, 0)) };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const date = [3]u8{ @intCast(@mod(yd.year, 100)), @intFromEnum(md.month), md.day_index + 1 };
    const bytes = import_mod.exportBytes(ctx.gpa, &db, args[2], format, date) catch |err| {
        if (err == error.Prepare) {
            try ctx.out.print("error: {s}\n", .{db.errorMessage()});
        } else try ctx.out.print("error: {s}: {s}\n", .{ args[2], @errorName(err) });
        ctx.status = exit_syntax;
        return;
    };
    defer ctx.gpa.free(bytes);
    Io.Dir.cwd().writeFile(ctx.io, .{ .sub_path = file, .data = bytes }) catch {
        try ctx.out.print("error: cannot write {s}\n", .{file});
        ctx.status = exit_cant_create;
        return;
    };
    try ctx.out.print("exported {s} to {s}\n", .{ args[2], file });
}

// Zig tip: `eve db serve` does not link DuckDB: it starts `evedb` from the folder of `eve` and waits for it, with this terminal as
// its terminal (`.inherit`), so the ready lines and the stop appear here. `Child.Term` is a tagged union: `.exited` carries the exit
// code; any other end (a signal) is reported as 1.
/// `db serve [evedb.cfg]`: run evedb, the database server (README.md of evedb), in the foreground.
fn serveCommand(ctx: *Context, args: []const []const u8) !void {
    const exe = try @import("evevm").service.evedbPath(ctx.io, ctx.gpa);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(ctx.gpa, &.{ exe, "serve" });
    if (args.len >= 1 and std.mem.endsWith(u8, args[0], ".cfg")) {
        try argv.appendSlice(ctx.gpa, &.{ "--config", args[0] });
        try argv.appendSlice(ctx.gpa, args[1..]);
    } else try argv.appendSlice(ctx.gpa, args);
    try ctx.out.flush();
    var child = std.process.spawn(ctx.io, .{ .argv = argv.items, .stdin = .inherit, .stdout = .inherit, .stderr = .inherit }) catch |err| {
        try ctx.out.print("eve: cannot start {s}: {s} (build it: ./run.sh build evedb)\n", .{ exe, @errorName(err) });
        ctx.status = 69;
        return;
    };
    const term = try child.wait(ctx.io);
    ctx.status = switch (term) {
        .exited => |code| code,
        else => 1,
    };
}

pub fn cmdDb(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (args.len >= 1 and std.mem.eql(u8, args[0], "serve")) {
        serveCommand(ctx, args[1..]) catch |err| switch (err) {
            error.WriteFailed => |e| return e,
            else => {
                try ctx.out.print("db serve: {s}\n", .{@errorName(err)});
                ctx.status = 69;
            },
        };
        return;
    }
    if (args.len >= 4 and (std.mem.eql(u8, args[0], "create") or std.mem.eql(u8, args[0], "drop"))) {
        objectCommand(ctx, args) catch |err| switch (err) {
            error.WriteFailed => |e| return e,
            else => {
                try ctx.out.print("db {s}: {s}\n", .{ args[0], @errorName(err) });
                ctx.status = exit_no_input;
            },
        };
        return;
    }
    if (args.len >= 3 and (std.mem.eql(u8, args[0], "import") or std.mem.eql(u8, args[0], "export"))) {
        transferCommand(ctx, args) catch |err| switch (err) {
            error.WriteFailed => |e| return e,
            else => {
                try ctx.out.print("db {s}: {s}\n", .{ args[0], @errorName(err) });
                ctx.status = exit_no_input;
            },
        };
        return;
    }
    if (args.len >= 3 and std.mem.eql(u8, args[0], "sql")) {
        sqlCommand(ctx, args[1..]) catch |err| switch (err) {
            error.WriteFailed => |e| return e,
            else => {
                try ctx.out.print("db sql: {s}\n", .{@errorName(err)});
                ctx.status = exit_no_input;
            },
        };
        return;
    }
    if (!(args.len == 2 and std.mem.eql(u8, args[0], "proc") and std.mem.eql(u8, args[1], "list"))) {
        try ctx.out.writeAll("db: usage: db proc list | db sql [-t] [--last] [-f script] <file|:memory:> <statement> | db create view|table <file> <name> <select…> | db drop view <file> <name> | db import <file.db> <file> [table] | db export <file.db> <table> <file>\n");
        ctx.status = exit_usage;
        return;
    }
    procList(ctx) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("db proc list: {s}\n", .{@errorName(err)});
            ctx.status = exit_no_input;
        },
    };
}

// Zig tip: `std.mem.sort` sorts a slice in place with a comparison function; `{}` is the empty context the function
// receives. `std.crypto.hash.sha2.Sha256.hash` fills a 32-byte array with the hash of the source, and
// `std.fmt.bytesToHex` writes bytes as hexadecimal text: the first 4 bytes are the short hash printed.
/// `db proc list`: each module of the folder `proc/`, sorted, with the hash of its source, and its exported procedures
/// and functions with their signatures (database.md#stored-procedures, D-166).
pub fn procList(ctx: *Context) !void {
    const io = ctx.io;
    var dir = Io.Dir.cwd().openDir(io, "proc", .{ .iterate = true }) catch {
        try ctx.out.writeAll("db proc list: there is no folder proc/ here\n");
        ctx.status = exit_no_input;
        return;
    };
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var entries = dir.iterate();
    while (try entries.next(io)) |e| {
        if (e.kind == .file and std.mem.endsWith(u8, e.name, ".eve")) try names.append(ctx.gpa, try ctx.gpa.dupe(u8, e.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessName);
    ctx.status = 0;
    for (names.items) |name| {
        const src = try dir.readFileAlloc(io, name, ctx.gpa, .limited(16 << 20));
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(src, &hash, .{});
        var diag: parser.Diag = .{};
        const tree = parser.parse(ctx.gpa, src, &diag) catch {
            try ctx.out.print("proc/{s}:{d}:{d}: error: {s}\n", .{ name, diag.line, diag.col, diag.message() });
            ctx.status = exit_syntax;
            continue;
        };
        if (tree.tag != .module) {
            try ctx.out.print("proc/{s}: not a module: a stored procedure lives in a module\n", .{name});
            ctx.status = exit_syntax;
            continue;
        }
        try ctx.out.print("{s} {s}\n", .{ tree.text, &std.fmt.bytesToHex(hash[0..4], .lower) });
        for (tree.kids) |ex| if (ex.tag == .export_decl) for (ex.kids) |n| {
            for (tree.kids) |d| if ((d.tag == .procedure or d.tag == .function) and std.mem.eql(u8, d.text, n.text)) {
                try writeSignature(ctx.out, d);
            };
        };
    }
}

// Zig tip: the first parameter of a comparison for `std.mem.sort` is the context (`void` here: none); `_` names a
// parameter that is not used, which Zig would otherwise report as an error. `std.mem.lessThan` orders bytes.
pub fn lessName(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

// Zig tip: `for (list, 0..) |q, i|` counts while it walks, so the separator `, ` goes before every item but the first.
/// One line: `  procedure archive(before: String, @moved: Integer)` or `  sql function f(x: T) => (@r: T)`.
pub fn writeSignature(w: *Io.Writer, d: *const ast.Node) Io.Writer.Error!void {
    try w.print("  {s}{s} {s}(", .{ if (d.is_sql) "sql " else "", @tagName(d.tag), d.text });
    try writeParams(w, d.kids[0].kids);
    try w.writeAll(")");
    if (d.tag == .function) {
        try w.writeAll(" => (");
        try writeParams(w, d.kids[2].kids);
        try w.writeAll(")");
    }
    try w.writeAll("\n");
}

// Zig tip: `writeParams` relies on the same Zig feature as `writeSignature` above: see the tip there. `if (q.ty) |t|`
// unwraps the optional type of a parameter: a parameter without a type prints its name alone.
pub fn writeParams(w: *Io.Writer, params: []const *const ast.Node) Io.Writer.Error!void {
    for (params, 0..) |q, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("{s}{s}", .{ if (q.tag == .ref_param) "@" else "", q.text });
        if (q.ty) |t| try w.print(": {s}", .{t.text});
    }
}
