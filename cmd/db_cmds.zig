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
    const path = try a.dupeZ(u8, args[k]);
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
        var st = db.prepare(try a.dupeZ(u8, stmt_text)) catch {
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
pub fn cmdDb(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
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
        try ctx.out.writeAll("db: usage: db proc list | db sql [-t] [--last] [-f script] <file|:memory:> <statement>\n");
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
