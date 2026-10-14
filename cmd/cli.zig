//! Command line and REPL of the `eve` command (manual/usage.md).
//!
//! Every REPL command is one entry of the jump table `commands`. The same table serves the command
//! line: `eve --check script.eve` runs the `check` entry once and exits, without the REPL.
// Zig tip: `@import` returns a whole file as a struct (a namespace). Nothing is global: a file
// sees only what it imports. `@import("std")` is the standard library; `@import("evecm").version`
// is a file next to this one. `const` binds a name once; `var` would allow reassignment.
// `std.Io` is the input/output part of the library (Zig 0.16): readers, writers, files.
const std = @import("std");
const Io = std.Io;
const version = @import("evecm").version;
// Zig tip: Zig forbids a name that hides another one in an outer scope (shadowing). The file-level
// import is called `editor`, not `line`, because several functions below have a parameter `line`.
const editor = @import("evecm").line;
const parser = @import("evecp").parser;
const ast = @import("evecm").ast;
const doc = @import("evecp").doc;
const scaffold = @import("evecp").scaffold;
const vm = @import("evevm").vm;
const client = @import("evevm").client;
const daemon = @import("evevm").daemon;
const screen = @import("evevm").screen;
const tui = @import("evevm").tui;
const helptext = @import("evevm").helptext;

// Zig tip: `pub` makes a declaration visible to other files (main.zig uses `cli.exit_usage`).
// Without it the name is private to this file. A `const` number without a type is a
// `comptime_int`: it has no size until it is used (here as the `u8` exit status).
// `///` documents the next declaration, `//!` documents the file; tools show both.
/// Exit status: bad command line (EX_USAGE).
pub const exit_usage = 64;
/// Exit status: the script has syntax errors (EX_DATAERR), reported by `check`.
pub const exit_syntax = 65;
/// Exit status: not implemented, outside the Eve range (EX_SOFTWARE).
pub const exit_not_implemented = 70;
/// The input file cannot be read (EX_NOINPUT of sysexits.h).
pub const exit_no_input = 66;
/// A file or folder cannot be created (EX_CANTCREAT of sysexits.h).
pub const exit_cant_create = 73;

// Zig tip: a string literal is a pointer to a constant array of bytes; there is no string type.
// Text is `[]const u8`: a slice (pointer + length) of read-only bytes, in UTF-8.
pub const prompt = "eve:> ";

// Zig tip: a `struct` is a record. Fields can have default values (`= false`), so
// `.{ .out = w }` builds a Context and fills the rest. Types are written after the name:
//   `*Io.Writer`    pointer to one Writer (the struct does not own it, it only borrows it)
//   `?[]const u8`   optional: either a string or `null` (no -s option given)
//   `u8`            unsigned 8-bit integer, 0 to 255, exactly what a process exit code is
/// State shared by the command handlers.
pub const Context = struct {
    out: *Io.Writer,
    /// For reading files, and the allocator the commands use for the file and its tokens.
    io: Io,
    gpa: std.mem.Allocator,
    /// `-d`: `halt` statements stop the script; otherwise they are ignored.
    debug: bool = false,
    /// `-s file.cfg` (the same file `setup` loads)
    config: ?[]const u8 = null,
    /// `-m size`
    memory: ?[]const u8 = null,
    /// `-i file`: the slot, a file where other programs append commands while the VM runs.
    slot: ?[]const u8 = null,
    /// `-t seconds`: how long serve mode waits without a command before it stops.
    idle_ms: u64 = 30_000,
    /// The VM session, created by the first command that needs it.
    machine: ?*vm.Session = null,
    /// Set by `quit` and `exit`: the REPL ends.
    quit: bool = false,
    /// Exit status of the last command.
    status: u8 = 0,
    /// A person is at the terminal: boxes in UTF-8 and colors (set by `main`), else plain ASCII.
    fancy: bool = false,
    /// The full-screen REPL, when there is one: `out` writes into its upper part.
    tui: ?*tui.Tui = null,
    /// The width of the help table and texts: EVE_WIDTH, or `eve_width` of eve.cfg, or 100.
    width: usize = screen.default_width,
};

// Zig tip: types are ordinary values, so `const Handler = ...` names a type. This one is a
// pointer to a function (`*const fn`): the jump table stores handlers in it and calls them.
// `Io.Writer.Error!void` is an error union: the function returns either `void` (nothing) or
// one of the errors of Io.Writer. The caller must handle it: `try` (pass it up) or `catch`.
// `[]const []const u8` is a slice of strings: the words after the command name.
pub const Handler = *const fn (ctx: *Context, args: []const []const u8) Io.Writer.Error!void;

pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    run: Handler,
    /// Extension of the file the command takes (Tab completes such files); "" when it takes none.
    file: []const u8 = "",
};

// Zig tip: `comptime` parameters are known while compiling. `stub("check")` is evaluated by the
// compiler, which generates a separate small function for each name. A function cannot capture
// local variables, so the trick is to return a function declared inside an anonymous struct,
// whose `name` is a constant the compiler fills in. `_` as a parameter name means "unused":
// Zig reports unused parameters and variables as errors. `try x` means: if `x` is an error,
// return it from this function at once; otherwise use the value. `.{name}` is a tuple of the
// values for the `{s}` placeholder (`s` = string) of `print`.
/// A branch that is not written yet: it echoes its name.
fn stub(comptime name: []const u8) Handler {
    return struct {
        fn run(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
            try ctx.out.print("{s} command, not yet implemented\n", .{name});
            ctx.status = exit_not_implemented;
        }
    }.run;
}

// Zig tip: `ctx` is a pointer, so `ctx.quit = true` changes the caller's Context. Zig has no
// hidden copies: a struct passed by value is copied, a pointer lets the callee modify it.
// Fields are reached with `.` for both a struct and a pointer to it.
fn cmdQuit(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    ctx.quit = true;
}

// Zig tip: `catch return error.WriteFailed` turns the errors of the stop (out of memory, a failed write) into the one
// error that a handler of this table may return. The text is written before the call is made, and flushed, so that the
// screen shows it even if the stop takes a moment.
/// `stop`: close the doors this process opened (ipc and http together), tell the running scripts to stop, and stay at
/// the prompt. With no door open here, it stops the machine of another process (the one `evevm` started).
fn cmdStop(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    try ctx.out.flush();
    ctx.status = daemon.stopMachines(ctx.io, ctx.gpa, ctx.out, ctx.config orelse "eve.cfg") catch return error.WriteFailed;
}

// Zig tip: the same command does the right thing in each of the three kinds of screen: the scrollback of the
// full-screen REPL is emptied, a plain terminal gets the escape codes that erase the window and move the cursor home,
// and a pipe gets nothing (an escape code in a file is noise).
/// `clear`: clear the upper part of the screen.
fn cmdClear(ctx: *Context, _: []const []const u8) Io.Writer.Error!void {
    if (ctx.tui) |t| {
        t.clear();
    } else if (ctx.fancy) {
        try ctx.out.writeAll("\x1b[2J\x1b[H");
    }
}

// Zig tip: the same function serves the full-screen REPL and the plain prompt. With a screen, the text is added as a
// *block* (`addBlock`), which the screen draws again when the window changes size; without one the text is written at
// once, at the width of `eve_width`. `orelse { ... return; }` leaves the function with a message when the optional
// is null: here, a command that has no help.
/// `help` and `?`: the table of the commands; `help <command>`: the page of one command.
fn cmdHelp(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const style: screen.Style = .{ .fancy = ctx.fancy };
    if (args.len == 0) {
        if (ctx.tui) |t| t.addBlock(.help_table, 0) else try screen.writeHelpTable(ctx.out, style, ctx.width);
        return;
    }
    const index = helptext.indexOf(args[0]) orelse {
        try ctx.out.print("help: no help for {s} (type help for the list)\n", .{args[0]});
        ctx.status = exit_usage;
        return;
    };
    if (ctx.tui) |t| t.addBlock(.help_command, index) else try screen.writeDetail(ctx.out, style, helptext.entries[index], ctx.width);
}

// Zig tip: a `switch` on an enum must cover every tag; `catch {}` drops the write error because the writer here is a
// block in memory that cannot fail in a way the screen could use.
/// The function that the full-screen REPL calls to draw a block again for a new width.
fn renderBlock(kind: tui.BlockKind, arg: usize, width: usize, w: *Io.Writer) void {
    const style: screen.Style = .{ .fancy = true };
    switch (kind) {
        .help_table => screen.writeHelpTable(w, style, width) catch {},
        .help_command => screen.writeDetail(w, style, helptext.entries[arg], width) catch {},
    }
}

// Zig tip: `Dir.cwd().readFileAlloc(io, path, gpa, limit)` reads a whole file into memory that
// `gpa` provides, and fails with an error if it is missing or longer than the limit
// (`.limited(n)` is a size limit in bytes). The caller frees it with `defer gpa.free(src)`.
// `catch |err| { ... continue; }` handles an error in place and goes on with the next file.
// `@errorName(err)` is the name of an error value as text. `worst` keeps the highest status.
// The message format `file:line:col: error: text` is the one editors and CI tools understand.
/// `check`: parse each file without executing it. Status 65 if any has a syntax error.
fn cmdCheck(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (args.len == 0) {
        try ctx.out.writeAll("check: file name missing\n");
        ctx.status = exit_usage;
        return;
    }
    var worst: u8 = 0;
    for (args) |path| {
        const src = Io.Dir.cwd().readFileAlloc(ctx.io, path, ctx.gpa, .limited(16 << 20)) catch |err| {
            try ctx.out.print("{s}: cannot read: {s}\n", .{ path, @errorName(err) });
            worst = @max(worst, exit_no_input);
            continue;
        };
        defer ctx.gpa.free(src);
        var diag: parser.Diag = .{};
        if (parser.check(ctx.gpa, src, &diag)) {
            try ctx.out.print("{s}: ok\n", .{path});
        } else |err| switch (err) {
            error.Syntax => {
                try ctx.out.print("{s}:{d}:{d}: error: {s}\n", .{ path, diag.line, diag.col, diag.message() });
                worst = @max(worst, exit_syntax);
            },
            error.OutOfMemory => {
                try ctx.out.print("{s}: out of memory\n", .{path});
                worst = @max(worst, exit_no_input);
            },
        }
    }
    ctx.status = worst;
}

// Zig tip: `doc.generate(...) catch |err| switch (err) { ... }` handles the error union in place.
// `error.WriteFailed => |e| return e` passes on the one error this handler may return (its
// type is `Io.Writer.Error!void`); `else =>` covers every other error of the inferred set of
// `generate` (missing folder, unreadable file, out of memory) with one branch.
/// `doc`: write the Markdown documentation of a `.eve` file, or of the `.eve` files of a folder.
fn cmdDoc(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (args.len == 0 or args.len > 2) {
        try ctx.out.writeAll("doc: usage: doc <folder | file.eve> [output folder, default doc]\n");
        ctx.status = exit_usage;
        return;
    }
    const out_path = if (args.len == 2) args[1] else "doc";
    const pages = doc.generate(ctx.io, ctx.gpa, args[0], out_path, ctx.out) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("doc: {s}: {s}\n", .{ args[0], @errorName(err) });
            ctx.status = exit_no_input;
            return;
        },
    };
    if (pages == 0) try ctx.out.print("doc: no .eve file in {s}\n", .{args[0]});
    ctx.status = 0;
}

// Zig tip: a subcommand is read from the first word of `args`. `std.mem.eql` compares the text
// (see `find`). `scaffold.init` returns an error union; `catch |err| switch (err)` passes on the
// one error of this handler's type (`WriteFailed`) and reports every other one as a message.
// `init` and `new` differ in one test only, so `is_new` is a plain bool and not two functions.
/// `project init <folder>` and `project new <folder>`: make a project with the standard layout
/// (plan/design-project-layout.md). `init` also works on an existing project and keeps its files;
/// `new` fails when the folder exists and is not empty.
fn cmdProject(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const is_new = args.len == 2 and std.mem.eql(u8, args[0], "new");
    if (args.len != 2 or !(is_new or std.mem.eql(u8, args[0], "init"))) {
        try ctx.out.writeAll("project: usage: project init <folder> | project new <folder>\n");
        ctx.status = exit_usage;
        return;
    }
    if (is_new) {
        const free = scaffold.isEmptyOrAbsent(ctx.io, Io.Dir.cwd(), args[1]) catch false;
        if (!free) {
            try ctx.out.print("project: {s} exists and is not empty (project init keeps its files)\n", .{args[1]});
            ctx.status = exit_cant_create;
            return;
        }
    }
    const result = scaffold.init(ctx.io, ctx.gpa, Io.Dir.cwd(), args[1], true, ctx.out) catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => {
            try ctx.out.print("project: {s}: {s}\n", .{ args[1], @errorName(err) });
            ctx.status = exit_cant_create;
            return;
        },
    };
    try ctx.out.print("project {s}: {s}: {d} created, {d} kept\n", .{ args[0], args[1], result.created, result.kept });
    ctx.status = 0;
}

// Zig tip: the VM session is created the first time a command needs it and kept in the Context, so
// Zig tip: `cmdDb` relies on the same Zig feature as `cmdDoc`: the work is done by a function with an inferred error
// set, and the handler passes on `WriteFailed` and turns every other error into a message.
/// `db`: the commands of the database part (`eve db ...`, D-163). Today `db proc list`.
fn cmdDb(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    if (!(args.len == 2 and std.mem.eql(u8, args[0], "proc") and std.mem.eql(u8, args[1], "list"))) {
        try ctx.out.writeAll("db: usage: db proc list\n");
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
fn procList(ctx: *Context) !void {
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
fn lessName(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

// Zig tip: `for (list, 0..) |q, i|` counts while it walks, so the separator `, ` goes before every item but the first.
/// One line: `  procedure archive(before: String, @moved: Integer)` or `  sql function f(x: T) => (@r: T)`.
fn writeSignature(w: *Io.Writer, d: *const ast.Node) Io.Writer.Error!void {
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
fn writeParams(w: *Io.Writer, params: []const *const ast.Node) Io.Writer.Error!void {
    for (params, 0..) |q, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("{s}{s}", .{ if (q.tag == .ref_param) "@" else "", q.text });
        if (q.ty) |t| try w.print(": {s}", .{t.text});
    }
}

// the next command finds the script the previous one loaded. `gpa.create(T)` allocates one `T` and
// returns a pointer; `s.* = .{ ... }` fills it. A `?*T` field is null until then, and `orelse`
// would also do: `if (ctx.machine) |s| return s;` is the early-return form. The slot is created
// with the session, because the interpreter polls it between statements.
/// The session of this run of `eve`.
fn session(ctx: *Context) Io.Writer.Error!*vm.Session {
    if (ctx.machine) |s| return s;
    const s = ctx.gpa.create(vm.Session) catch return error.WriteFailed;
    s.* = .{ .io = ctx.io, .gpa = ctx.gpa, .out = ctx.out, .debug = ctx.debug };
    if (ctx.slot) |p| {
        const sl = ctx.gpa.create(vm.Slot) catch return error.WriteFailed;
        sl.* = .{ .io = ctx.io, .gpa = ctx.gpa, .path = p };
        s.slot = sl;
    }
    ctx.machine = s;
    return s;
}

// Zig tip: `viaSession("load")` is a comptime function like `stub`: it returns a handler for one
// session command. `std.mem.join(gpa, " ", args)` glues the words back into one string (the
// `log` command takes the rest of the line). `ctx.status = s.status` copies the exit status of the
// command, and a `stop` from the session ends the REPL too.
/// A REPL command that is implemented by the session (vm.zig): `load`, `parse`, `ast`, ...
fn viaSession(comptime name: []const u8) Handler {
    return struct {
        fn run(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
            const s = try session(ctx);
            const rest = std.mem.join(ctx.gpa, " ", args) catch return error.WriteFailed;
            _ = try s.exec(name, args, rest);
            ctx.status = s.status;
            if (s.stopping) ctx.quit = true;
        }
    }.run;
}

// Zig tip: `comptime listen: bool` makes two handlers from one function, `door(true)` for `listen` and `door(false)`
// for `serve`, as `viaSession` does for the session commands. The words are read in any order: `start`, `stop`,
// `restart` or `status` is the action, and the other door's name adds that door (`listen serve` opens both).
/// `listen [word]` and `serve [word]` in the REPL: the same as `--listen` and `--serve`, but the doors open in this
/// process and the prompt stays.
fn door(comptime listen: bool) Handler {
    return struct {
        fn run(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
            var cmd: client.Cmd = .{ .listen = listen, .serve = !listen, .config = ctx.config };
            for (args) |w| {
                if (std.mem.eql(u8, w, "listen")) {
                    cmd.listen = true;
                } else if (std.mem.eql(u8, w, "serve")) {
                    cmd.serve = true;
                } else if (cmd.word.len == 0) {
                    cmd.word = w;
                } else {
                    try ctx.out.print("{s}: unexpected word: {s}\n", .{ if (listen) "listen" else "serve", w });
                    ctx.status = exit_usage;
                    return;
                }
            }
            const known = [_][]const u8{ "", "start", "stop", "restart", "status" };
            for (known) |k| if (std.mem.eql(u8, k, cmd.word)) break else {} else {
                try ctx.out.print("{s}: expected start, stop, restart or status, not {s}\n", .{ if (listen) "listen" else "serve", cmd.word });
                ctx.status = exit_usage;
                return;
            }
            try ctx.out.flush();
            const code = client.handle(ctx.io, ctx.gpa, ctx.out, cmd, true) catch return error.WriteFailed;
            ctx.status = code orelse 0;
        }
    }.run;
}

// Zig tip: a handler ignores the arguments it does not need with `_ = args;`: Zig reports an unused parameter as an
// error, so this line says "not used, on purpose". The report is only text written to `ctx.out`; it opens no door.
/// `status`: the machine in one page. The process (version, script, folder of the reports), then the configuration,
/// the doors and what a machine on them is doing. The line of the script in `summary.log` is still added.
fn cmdStatus(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    _ = args;
    const s = try session(ctx);
    _ = try s.logStatus();
    try ctx.out.print("{s}\nthis process: command line, it opens no door itself\n", .{version.title});
    try s.writeState(ctx.out);
    try ctx.out.flush();
    client.machineStatus(ctx.io, ctx.gpa, ctx.out, ctx.config orelse "eve.cfg") catch return error.WriteFailed;
}

// Zig tip: parse first, run second: the session's `run` parses the file when it was not parsed,
// and returns early on a syntax error, so a script with errors never starts. With no file name
// and a slot (`eve -x -i file.vmc`) the machine does not run a script: it serves the commands
// of the slot until `stop` (a workflow). Unhandled errors go to stderr, so the standard
// output stays what the script printed.
/// `execute`: parse the script (as `check` does) and, only if it is correct, run its main process.
fn cmdExecute(ctx: *Context, args: []const []const u8) Io.Writer.Error!void {
    const s = try session(ctx);
    if (args.len == 0) {
        if (s.slot == null) {
            try ctx.out.writeAll("execute: file name missing\n");
            ctx.status = exit_usage;
            return;
        }
        try s.serve(ctx.idle_ms);
        ctx.status = s.status;
        return;
    }
    s.quiet = true;
    s.capture = false;
    s.script_args = args[1..];
    try s.load(args[0]);
    if (s.arena == null) {
        ctx.status = s.status;
        return;
    }
    try s.run();
    ctx.status = s.status;
    if (s.outcome) |o| {
        if (o.stopped) try ctx.out.print("{s}: stopped by a command from the slot\n", .{args[0]});
        if (o.code != 0 and s.machine != null) {
            try ctx.out.flush();
            for (s.machine.?.reports.items) |r| {
                if (!r.handled) {
                    const fmt = "{s}:{d}: error {d}: {s}\n{s}{s}";
                    const parts = .{ args[0], r.line, r.code, r.message, r.trace, r.details };
                    // on the full-screen REPL the error goes to the upper part, not under the bars (stderr)
                    if (ctx.tui != null) try ctx.out.print(fmt, parts) else std.debug.print(fmt, parts);
                }
            }
        }
    }
}

// Zig tip: the jump table is a plain array. `[_]Command{ ... }` lets the compiler count the
// elements. `.{ .name = "x", ... }` is an anonymous struct literal: the type `Command` is taken
// from the array, so it need not be repeated. `.run = cmdHelp` stores the function itself (a
// function name without `()` is a value); `stub("check")` calls a comptime function that
// returns one. The whole table is a constant, built by the compiler and stored in the program.
/// The jump table. Order is the order of the menu.
pub const commands = [_]Command{
    .{ .name = "check", .summary = "check the syntax of a script, do not execute it", .file = ".eve", .run = cmdCheck },
    .{ .name = "compile", .summary = "compile a script to bytecode", .file = ".eve", .run = stub("compile") },
    .{ .name = "doc", .summary = "write Markdown documentation of a .eve file or folder", .file = ".eve", .run = cmdDoc },
    .{ .name = "debug", .summary = "execute the main process in debug mode", .file = ".eve", .run = stub("debug") },
    .{ .name = "execute", .summary = "execute the main process in production mode", .file = ".eve", .run = cmdExecute },
    .{ .name = "project", .summary = "project init|new <folder>: make a project with the standard layout", .run = cmdProject },
    .{ .name = "db", .summary = "db proc list: the database part (eve db ...)", .run = cmdDb },
    .{ .name = "begin", .summary = "start the step by step execution", .run = stub("begin") },
    .{ .name = "enter", .summary = "execute the next step", .run = stub("enter") },
    .{ .name = "run", .summary = "execute the loaded script, or the file given (parsed first)", .file = ".eve", .run = viaSession("run") },
    .{ .name = "load", .summary = "load a script, forget the previous one", .file = ".eve", .run = viaSession("load") },
    .{ .name = "parse", .summary = "parse the loaded script, report syntax errors", .file = ".eve", .run = viaSession("parse") },
    .{ .name = "ast", .summary = "write the syntax tree to <outdir>/<name>.ast", .run = viaSession("ast") },
    .{ .name = "inspect", .summary = "write the introspection report <outdir>/<name>.inspect", .run = viaSession("inspect") },
    .{ .name = "errors", .summary = "report the errors of the script (<outdir>/<name>.err)", .run = viaSession("errors") },
    .{ .name = "status", .summary = "the state of the machine: script, configuration, doors, what it is doing", .run = cmdStatus },
    .{ .name = "listen", .summary = "listen [start|stop|restart|status]: the IPC door, the prompt stays", .run = door(true) },
    .{ .name = "serve", .summary = "serve [start|stop|restart|status]: the HTTP door, the prompt stays", .run = door(false) },
    .{ .name = "outdir", .summary = "set the folder of the report files", .run = viaSession("outdir") },
    .{ .name = "capture", .summary = "capture on|off: keep the script output in <outdir>/<name>.out", .run = viaSession("capture") },
    .{ .name = "log", .summary = "add a line of text to summary.log", .run = viaSession("log") },
    .{ .name = "print", .summary = "display the value of a global variable", .run = stub("print") },
    .{ .name = "resume", .summary = "run until the next halt statement", .run = stub("resume") },
    .{ .name = "report", .summary = "report the system state", .run = viaSession("report") },
    .{ .name = "stop", .summary = "stop the doors (ipc and http) and the scripts; the prompt stays", .run = cmdStop },
    .{ .name = "clear", .summary = "clear the upper part of the screen (the output); the command line stays", .run = cmdClear },
    .{ .name = "setup", .summary = "load the configuration file", .file = ".cfg", .run = stub("setup") },
    .{ .name = "help", .summary = "display this menu", .run = cmdHelp },
    .{ .name = "quit", .summary = "exit from the REPL", .run = cmdQuit },
    .{ .name = "exit", .summary = "same as quit", .run = cmdQuit },
};

// Zig tip: `?*const Command` is "a pointer to a Command, or null". There are no null pointers
// in other types: absence must be written in the type with `?`. `for (&commands) |*c|`
// walks the array by pointer (`&` takes the address, `|*c|` captures each element by
// pointer, so nothing is copied). `std.mem.eql(u8, a, b)` compares two slices of bytes; `==`
// on slices does not compare contents. `return` inside the loop leaves the function.
pub fn find(name: []const u8) ?*const Command {
    for (&commands) |*c| {
        if (std.mem.eql(u8, c.name, name)) return c;
    }
    return null;
}

// Zig tip: lines that start with `\\` form a multi-line string literal. There are no escapes
// inside; each line ends with a newline and the text starts right after the `\\`. The last
// line `\\` followed by nothing adds an empty line.
pub const quick_help =
    \\Usage: eve [options]                      start the REPL
    \\       eve [options] <script.eve> [args]  execute a script (same as -x)
    \\       eve [options] <command> [args]     run one command and exit, no REPL (same as --<command>)
    \\       evevm [start|stop|restart|status]  the machine in a new process (listen and serve), the prompt returns
    \\
    \\Quick help:
    \\  -x                execute the script now, in this process (parsed first): no IPC or
    \\                    HTTP lookup, the fast way to run a script; same as --execute
    \\  -u                open the user interface (the web page of the machine) if it is not open; with a
    \\                    command, open it and then run the command
    \\  -d                debug mode: halt statements stop the script (ignored otherwise)
    \\  -s <file.cfg>     setup: load the configuration file
    \\  -m <size>         memory for the process
    \\  -i <file>         slot: commands (report, stop) that other programs append to the file
    \\  -t <seconds>      slot without a script: stop after this long without a command
    \\  -v, --version     display the version and exit
    \\  -h, --help        display this help and exit
    \\
    \\The machine (an eve that stays active and answers requests):
    \\  --listen [word]   the IPC door (this computer): start (the default), stop, restart or status
    \\  --serve [word]    the HTTP door: start (the default), stop, restart or status
    \\                    --listen --serve opens both doors; the ports are ipc_port and http_port of eve.cfg
    \\  -loc [port]       --local: run the command in the machine through IPC, or in
    \\                    this process when none listens; never the network
    \\  -rem [host:port]  --remote: run the command in a remote machine through HTTP;
    \\                    fails when nobody answers (no address: remote of eve.cfg)
    \\
;

pub const more_prompt = "-- press enter for more --";

const commands_head =
    \\Commands (REPL, or --<command> on the command line):
    \\
    \\
;

// Zig tip: `w.print("{s}\n\n", .{version.title})` formats like printf, checked by the compiler:
// the number and types of the values must match the placeholders. `{s}` is a string, `{d}` a
// number. `{s: <9}` (see below) pads a string with spaces on the right to 9 characters.
// `version.title` is built with `++` at compile time (see version.zig).
/// Page 1 of the help: the title and the short options.
pub fn writeQuickHelp(w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{s}\n\n", .{version.title});
    try w.writeAll(quick_help);
}

// Zig tip: `for (&commands) |c|` here captures each element by value (a copy); the one-line
// body after `)` needs no braces. `'\n'` in single quotes is one byte (a `u8`), not a string.
/// Page 2 of the help: the same title and the `--<command>` list.
pub fn writeCommandsHelp(w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{s}\n\n", .{version.title});
    try w.writeAll(commands_head);
    for (&commands) |c| try w.print("  --{s: <9}{s}\n", .{ c.name, c.summary });
}

/// Both pages in a row (the REPL `help` command).
pub fn writeMenu(w: *Io.Writer) Io.Writer.Error!void {
    try writeQuickHelp(w);
    try w.writeByte('\n');
    try writeCommandsHelp(w);
}

// Zig tip: `!void` without an error set means "any error": the compiler works out which ones
// from the body. `in: ?*Io.Reader` is an optional pointer; `if (in) |r| { ... }` runs the block
// only when it is not null, and `r` is the unwrapped pointer. `_ = expr;` explicitly throws a
// result away (Zig refuses to ignore values silently). `w.flush()` matters: a Writer keeps
// text in a buffer and sends it to the screen only on flush, so flush before waiting for input.
/// The paged help of `eve -h`: the quick page, then, after Enter, the commands page. Without `in`
/// (output is not a terminal) both pages are written without waiting.
pub fn writeHelp(w: *Io.Writer, in: ?*Io.Reader) !void {
    try writeQuickHelp(w);
    try w.writeByte('\n');
    if (in) |r| {
        try w.writeAll(more_prompt);
        try w.flush();
        _ = try r.takeDelimiter('\n');
        try w.writeByte('\n');
    }
    try writeCommandsHelp(w);
}

// Zig tip: a struct can group the result of parsing. Every field has a default, so
// `var o: Options = .{};` is the all-defaults value. `&.{}` is an empty slice literal, the
// default of `args`.
pub const Options = struct {
    help: bool = false,
    version: bool = false,
    debug: bool = false,
    config: ?[]const u8 = null,
    memory: ?[]const u8 = null,
    slot: ?[]const u8 = null,
    idle: ?[]const u8 = null,
    /// `-x`: execute the script in this process (implies the `execute` command); it never looks for a machine.
    execute: bool = false,
    /// Command chosen with `--<command>` or implied by a script path.
    command: ?*const Command = null,
    /// Positional arguments after the command.
    args: []const []const u8 = &.{},
    /// The options of the machine (`--listen`, `--serve`, `-loc`, `-rem`; spec/library/machine.md).
    machine: client.Cmd = .{},
    /// `-u`: open the user interface (the web page of the machine) when it is not open.
    ui: bool = false,
};

// Zig tip: a small function with no state can be tested alone. `isPort` is true for a text of digits, which is how
// `-loc 4195` tells a port from the next option or a file. `for (text) |c|` visits each byte; `std.ascii.isDigit` is
// the test for one byte. An empty text is not a port.
/// True when `text` is a port number (digits only).
fn isPort(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

// Zig tip: the value of `-rem` is optional, so the parser looks at the next word: an option (starts with `-`) or a
// script (ends in `.eve`) is not an address. `std.mem.endsWith` is a test on the end of a slice.
/// True when `text` can be the address after `-rem`.
fn isAddress(text: []const u8) bool {
    return text.len > 0 and text[0] != '-' and !std.mem.endsWith(u8, text, ".eve");
}

// Zig tip: `error{ A, B }` is a set of error names. Errors are values, not exceptions: a
// function that can fail says so in its return type (`ParseError!Options`) and the caller must
// deal with it. Errors cannot carry data, so the bad argument is returned through the pointer
// parameter `bad` of parseArgs.
pub const ParseError = error{ MissingValue, UnknownOption, BadWord, OutOfMemory };

// Zig tip: memory is never allocated behind your back. A function that needs memory receives
// an `std.mem.Allocator` (`gpa`) from the caller, who decides where it comes from (here an
// arena that frees everything at once at the end of the program). `std.ArrayList(T)` is a
// growable array; `.empty` starts it with nothing and `append(gpa, x)` needs the allocator.
// `bad.* = a` writes through the pointer (`.*` dereferences). `orelse` gives a fallback when an
// optional is null, here by leaving the function with `return error.UnknownOption`.
// `while (cond) : (i += 1)` has a continue-expression that runs after each pass.
// `a[1] == 's'` compares a byte of the string with a character literal.

// Zig tip: `gpa.dupe(T, slice)` copies a slice into new memory, so one element can be changed without touching
// the caller's array (`argv` is `[]const`, read only). Returning a sub-slice, `argv[1..]`, copies nothing.
/// The first word of the command line may name a part of `eve` (D-163): `vm` (the runtime) and `cp` (the compiler)
/// select what the options already do, `cp project` is `--project`, `ux` (the UI) is `--serve`, `db` (the database
/// part) is the command `--db`. Gives the line the rest of `parseArgs` reads.
fn partWords(gpa: std.mem.Allocator, argv: []const []const u8) ParseError![]const []const u8 {
    if (argv.len == 0) return argv;
    const first = argv[0];
    const eql = std.mem.eql;
    if (eql(u8, first, "vm")) return argv[1..];
    if (eql(u8, first, "cp")) {
        if (argv.len > 1 and eql(u8, argv[1], "project")) {
            const copy = try gpa.dupe([]const u8, argv[1..]);
            copy[0] = "--project";
            return copy;
        }
        return argv[1..];
    }
    if (eql(u8, first, "ux") or eql(u8, first, "db")) {
        const copy = try gpa.dupe([]const u8, argv);
        copy[0] = if (eql(u8, first, "ux")) "--serve" else "--db";
        return copy;
    }
    return try commandWord(gpa, argv);
}

// Zig tip: the loop skips the options in front of the first word: the ones that take a value (`-s file`) are skipped
// together with it, the others alone. The first word left is a command if it names one, and then `check f.eve` is
// read as `--check f.eve`: the same command, one-shot, with no prompt. A word that ends in `.eve` is a script and a
// word that is no command is left alone (it is a script name or a mistake, as before).
/// `eve check file.eve` is `eve --check file.eve`: the first word that is a command is the command.
fn commandWord(gpa: std.mem.Allocator, argv: []const []const u8) ParseError![]const []const u8 {
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "-s") or std.mem.eql(u8, a, "-m") or std.mem.eql(u8, a, "-i") or std.mem.eql(u8, a, "-t")) {
            i += 1;
        } else if (std.mem.eql(u8, a, "-loc") and i + 1 < argv.len and isPort(argv[i + 1])) {
            i += 1;
        } else if (std.mem.eql(u8, a, "-rem") and i + 1 < argv.len and std.mem.indexOfScalar(u8, argv[i + 1], ':') != null) {
            i += 1;
        } else if (std.mem.eql(u8, a, "--listen") or std.mem.eql(u8, a, "--serve")) {
            // the word after a door (`--serve status`) belongs to the door, even though `status` is also a command
            for ([_][]const u8{ "start", "stop", "restart", "status" }) |w| {
                if (i + 1 < argv.len and std.mem.eql(u8, argv[i + 1], w)) i += 1;
            }
        } else if (a.len > 0 and a[0] != '-') {
            if (std.mem.endsWith(u8, a, ".eve") or find(a) == null) return argv;
            const copy = try gpa.dupe([]const u8, argv);
            copy[i] = try std.fmt.allocPrint(gpa, "--{s}", .{a});
            return copy;
        }
    }
    return argv;
}

/// Parse the command line (without the program name). On error `bad` names the argument.
pub fn parseArgs(
    gpa: std.mem.Allocator,
    argv: []const []const u8,
    bad: *[]const u8,
) ParseError!Options {
    var o: Options = .{};
    var rest: std.ArrayList([]const u8) = .empty;
    const line = try partWords(gpa, argv);
    var i: usize = 0;
    while (i < line.len) : (i += 1) {
        const a = line[i];
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            o.help = true;
        } else if (std.mem.eql(u8, a, "-v") or std.mem.eql(u8, a, "--version")) {
            o.version = true;
        } else if (std.mem.eql(u8, a, "-d")) {
            o.debug = true;
        } else if (std.mem.eql(u8, a, "-x")) {
            o.execute = true;
        } else if (std.mem.eql(u8, a, "-u")) {
            o.ui = true;
        } else if (std.mem.eql(u8, a, "-s") or std.mem.eql(u8, a, "-m") or std.mem.eql(u8, a, "-i") or std.mem.eql(u8, a, "-t")) {
            i += 1;
            if (i >= line.len) {
                bad.* = a;
                return error.MissingValue;
            }
            switch (a[1]) {
                's' => o.config = line[i],
                'm' => o.memory = line[i],
                't' => o.idle = line[i],
                else => o.slot = line[i],
            }
        } else if (std.mem.eql(u8, a, "--listen") or std.mem.eql(u8, a, "--serve")) {
            // Zig tip: `break` leaves the `for` at the first match. Without it the loop would go on comparing
            // `argv[i + 1]` after `i` moved, and read past the end of the slice (a panic in a safe build).
            // `--listen` (the IPC door) and `--serve` (the HTTP door) take the same words (D-169).
            if (std.mem.eql(u8, a, "--listen")) o.machine.listen = true else o.machine.serve = true;
            const words = [_][]const u8{ "start", "stop", "restart", "status" };
            if (i + 1 < line.len) for (words) |w| if (std.mem.eql(u8, line[i + 1], w)) {
                i += 1;
                o.machine.word = w;
                break;
            };
            // a plain word after the door that is none of the four is a mistake, not a script (D-169)
            if (o.machine.word.len == 0 and i + 1 < line.len and line[i + 1].len > 0 and line[i + 1][0] != '-') {
                bad.* = line[i + 1];
                return error.BadWord;
            }
        } else if (std.mem.eql(u8, a, "-loc") or std.mem.eql(u8, a, "--local")) {
            o.machine.local = true;
            if (i + 1 < line.len and isPort(line[i + 1])) {
                i += 1;
                o.machine.local_port = line[i];
            }
        } else if (std.mem.eql(u8, a, "-rem") or std.mem.eql(u8, a, "--remote")) {
            o.machine.remote = true;
            if (i + 1 < line.len and isAddress(line[i + 1])) {
                i += 1;
                o.machine.remote_addr = line[i];
            }
        } else if (std.mem.startsWith(u8, a, "--") and a.len > 2) {
            const c = find(a[2..]) orelse {
                bad.* = a;
                return error.UnknownOption;
            };
            if (o.command == null) o.command = c else try rest.append(gpa, a);
        } else if (a.len > 1 and a[0] == '-') {
            bad.* = a;
            return error.UnknownOption;
        } else {
            if (o.command == null) o.command = find("execute");
            try rest.append(gpa, a);
        }
    }
    if (o.execute and o.command == null) o.command = find("execute");
    o.args = try rest.toOwnedSlice(gpa);
    o.machine.config = o.config;
    if (o.command == find("execute") and o.args.len > 0) {
        o.machine.script = o.args[0];
        o.machine.script_args = o.args[1..];
    }
    return o;
}

// Zig tip: `var words: [16][]const u8 = undefined;` is an array of 16 slices whose content is
// not initialised on purpose (`undefined`): it lives on the stack, no allocator needed, and
// only the first `n` are used. `words[1..n]` is a slice of the array from index 1 up to n (n
// excluded), a view without copying. `while (it.next()) |w|` repeats while `next()` returns a
// value (an optional) and ends on null. `std.mem.tokenizeAny` splits on any of the characters
// of the delimiter string and skips empty pieces. `if (opt) |c| {...} else {...}` unwraps an
// optional. Arrays and slices are bounds-checked: a wrong index stops the program in Debug.
/// Run one line typed at the prompt. Blank lines are ignored.
pub fn dispatch(ctx: *Context, line: []const u8) Io.Writer.Error!void {
    var words: [16][]const u8 = undefined;
    var n: usize = 0;
    var it = std.mem.tokenizeAny(u8, line, " \t\r");
    while (it.next()) |w| {
        if (n == words.len) break;
        words[n] = w;
        n += 1;
    }
    if (n == 0) return;
    // `?` is `help`, `? <command>` is `help <command>`, and `<command> ?` is the page of that command
    if (std.mem.eql(u8, words[0], "?")) return cmdHelp(ctx, words[1..n]);
    if (n >= 2 and std.mem.eql(u8, words[n - 1], "?") and find(words[0]) != null) return cmdHelp(ctx, words[0..1]);
    if (find(words[0])) |c| {
        try c.run(ctx, words[1..n]);
    } else {
        try ctx.out.print("unknown command: {s} (type help or ?)\n", .{words[0]});
    }
}

// Zig tip: the REPL takes any `*Io.Reader`, not the keyboard itself. Real code passes stdin;
// the tests pass a string (`Io.Reader.fixed("quit\n")`). Writing code against an interface
// like this is how Zig programs are made testable. `(try in.takeDelimiter('\n')) orelse break`
// reads up to the newline; the result is null at the end of the input, and `orelse break`
// leaves the loop then. The slice points into the reader's own buffer and is valid only
// until the next read, so `dispatch` uses it at once and does not keep it.
// Zig tip: a function can return an optional slice: `?[]const u8` is a string or null. The line
// editor does not know the commands (line.zig must not import cli.zig, two files that import each
// other are hard to follow), so the REPL hands it this function: "which file extension does Tab
// complete here?". `std.mem.trimEnd` cuts the listed characters from the end of a slice. `orelse`
// gives a default for the null of `indexOfAny`. `return if (cond) a else null` is an `if` expression.
/// The extension Tab completes for the last word of `line`: `.cfg` after `-s`, otherwise what the
/// command takes (`.eve` for check, debug, execute and compile; `.cfg` for setup), else null.
pub fn completionExt(line: []const u8) ?[]const u8 {
    const head = std.mem.trimEnd(u8, line[0..editor.lastWordStart(line)], " \t");
    const c = find(head[0 .. std.mem.indexOfAny(u8, head, " \t") orelse head.len]) orelse return null;
    if (std.mem.eql(u8, head[editor.lastWordStart(head)..], "-s")) return ".cfg";
    if (std.mem.eql(u8, head[editor.lastWordStart(head)..], "-i")) return ".vmc";
    return if (c.file.len > 0) c.file else null;
}

/// What the line editor needs: the `Io` for reading folders and an allocator for the candidates.
pub const Edit = struct {
    io: Io,
    gpa: std.mem.Allocator,
};

/// The read, execute, print, loop. Ends on `quit`, `exit` or end of input. With `edit` the line
/// is read key by key (Tab completes file names, the terminal must be in raw mode); without it
/// the line is read as a whole, for pipes and tests.
pub fn repl(ctx: *Context, in: *Io.Reader, edit: ?Edit) !void {
    var comp: ?editor.Completer = if (edit) |e| editor.Completer.init(e.gpa) else null;
    defer if (comp) |*c| c.deinit();
    var buf: [editor.max_line]u8 = undefined;
    if (ctx.tui) |t| {
        t.eve_width = ctx.width;
        t.renderer = renderBlock;
    }
    while (!ctx.quit) {
        // Zig tip: `if (ctx.tui) |t| { ... continue; }` runs the full-screen branch when there is a screen and goes
        // back to the top of the loop; the code after it is the older line-by-line prompt, still used for pipes and
        // for a terminal whose size is unknown. The clock is read before and after the command for the status bar.
        if (ctx.tui) |t| {
            const text = (try t.readLine(in, &comp.?, &buf, completionExt)) orelse break;
            var words = std.mem.tokenizeAny(u8, text, " \t");
            const word = words.next() orelse continue;
            const started = Io.Timestamp.now(ctx.io, .awake).toMilliseconds();
            t.setRunning(if (std.mem.eql(u8, word, "?")) "help" else word);
            try dispatch(ctx, text);
            try ctx.out.flush();
            if (!ctx.quit) t.setReady(Io.Timestamp.now(ctx.io, .awake).toMilliseconds() - started);
            continue;
        }
        try ctx.out.writeAll(prompt);
        try ctx.out.flush();
        const text = if (edit) |e|
            (try editor.readLine(e.io, in, ctx.out, prompt, &comp.?, &buf, completionExt)) orelse break
        else
            (try in.takeDelimiter('\n')) orelse break;
        try dispatch(ctx, text);
    }
    try ctx.out.flush();
}

// Zig tip: `test "name" { }` blocks are compiled only by `zig build test` (./run.sh unit) and
// live next to the code they check. `std.testing.expect(cond)` and `expectEqual(expected,
// actual)` fail the test with an error. `.?` unwraps an optional and stops with an error if it
// is null. `expectEqual(c, find(c.name).?)` compares two pointers: the same table element.
// Zig tip: a test can keep two tables in step: the jump table and the help texts must name the same commands in the
// same order, or `help` would miss one or show one that does not exist. `inline for` is not needed: the arrays are
// walked at run time and `try` fails the test with the position of the first difference.
test "the help texts cover the commands of the jump table, in the same order" {
    try std.testing.expectEqual(commands.len, helptext.entries.len);
    for (&commands, &helptext.entries) |c, e| try std.testing.expectEqualStrings(c.name, e.name);
}

// Zig tip: an arena allocator frees everything at once with `deinit`, which suits a test that parses a few lines and
// looks at the result. `&.{ "a", "b" }` is a slice of texts written in place. The three cases are the ones that were
// confused once: a word after a door belongs to the door, a command word is the command, and `-u` is an option.
test "a command word is the command, a door word stays with its door, -u is an option" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";

    const served = try parseArgs(arena.allocator(), &.{ "--serve", "status" }, &bad);
    try std.testing.expect(served.command == null and served.machine.serve);
    try std.testing.expectEqualStrings("status", served.machine.word);

    const check = try parseArgs(arena.allocator(), &.{ "check", "a.eve" }, &bad);
    try std.testing.expectEqualStrings("check", check.command.?.name);
    try std.testing.expectEqualStrings("a.eve", check.args[0]);

    const stop = try parseArgs(arena.allocator(), &.{"stop"}, &bad);
    try std.testing.expectEqualStrings("stop", stop.command.?.name);

    const ui = try parseArgs(arena.allocator(), &.{ "-u", "status" }, &bad);
    try std.testing.expect(ui.ui);
    try std.testing.expectEqualStrings("status", ui.command.?.name);

    const only_ui = try parseArgs(arena.allocator(), &.{"-u"}, &bad);
    try std.testing.expect(only_ui.ui and only_ui.command == null);

    const script = try parseArgs(arena.allocator(), &.{"status.eve"}, &bad);
    try std.testing.expectEqualStrings("execute", script.command.?.name);

    const listen = try parseArgs(arena.allocator(), &.{ "listen", "status" }, &bad);
    try std.testing.expect(listen.machine.listen and listen.command == null);
    try std.testing.expectEqualStrings("status", listen.machine.word);
}

test "every command is found by name" {
    for (&commands) |*c| try std.testing.expectEqual(c, find(c.name).?);
    try std.testing.expect(find("nope") == null);
}

// Zig tip: `var buf: [128]u8 = undefined;` is a byte array on the stack; `Io.Writer.fixed(&buf)`
// makes a writer that writes into it and `w.buffered()` returns what was written, so the test
// reads the output without a terminal. `.fixed(...)` is shorthand for `Io.Writer.fixed(...)`:
// with a declared type on the left, `.name` looks the function up in that type.
// `@as(u8, x)` gives x an explicit type; a builtin like it always starts with `@`.
test "a stub echoes its name" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    try dispatch(&ctx, "  resume  a.eve ");
    try std.testing.expectEqualStrings("resume command, not yet implemented\n", w.buffered());
    try std.testing.expectEqual(@as(u8, exit_not_implemented), ctx.status);
}

// Zig tip: this test relies on the same features as the test above: see the tip there.
test "doc without a path is a usage error" {
    var buf: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    try dispatch(&ctx, "doc");
    try std.testing.expectEqual(@as(u8, exit_usage), ctx.status);
}

// Zig tip: `defer arena.deinit();` runs at the end of the scope, however it ends: the usual way
// to pair a resource with its release on the next line. The testing allocator reports memory
// that is never freed as a test failure. An ArenaAllocator frees everything in one `deinit`,
// so the parser's `append`s need no individual `free`. `&.{ "-d", "a.eve" }` is an inline
// array of strings, passed as a slice. `expectError(error.X, call)` checks that a call fails.
// Zig tip: `expectEqualStrings` compares two texts and prints both when they differ. The last word of a command line
// is the edge case of a parser that looks ahead: `--serve stop` must not read past the end of `argv`.
test "options of the machine: --listen, --serve, -loc, -rem" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    for ([_][]const u8{ "start", "stop", "restart", "status" }) |w| {
        const o = try parseArgs(arena.allocator(), &.{ "--serve", w }, &bad);
        try std.testing.expect(o.machine.serve);
        try std.testing.expectEqualStrings(w, o.machine.word);
        const l = try parseArgs(arena.allocator(), &.{ "--listen", w }, &bad);
        try std.testing.expect(l.machine.listen and !l.machine.serve);
        try std.testing.expectEqualStrings(w, l.machine.word);
    }
    try std.testing.expectError(error.BadWord, parseArgs(arena.allocator(), &.{ "--listen", "nope" }, &bad));
    try std.testing.expectEqualStrings("nope", bad);
    const both = try parseArgs(arena.allocator(), &.{ "--listen", "--serve" }, &bad);
    try std.testing.expect(both.machine.listen and both.machine.serve);
    try std.testing.expectEqualStrings("", both.machine.word);
    const remote = try parseArgs(arena.allocator(), &.{ "-rem", "localhost:8095", "-x", "a.eve", "x" }, &bad);
    try std.testing.expectEqualStrings("localhost:8095", remote.machine.remote_addr.?);
    try std.testing.expectEqualStrings("a.eve", remote.machine.script.?);
    try std.testing.expectEqual(@as(usize, 1), remote.machine.script_args.len);
    const local = try parseArgs(arena.allocator(), &.{ "-loc", "-x", "a.eve" }, &bad);
    try std.testing.expect(local.machine.local and local.machine.local_port == null);
    const long = try parseArgs(arena.allocator(), &.{ "--local", "4043", "--remote", "--listen" }, &bad);
    try std.testing.expect(long.machine.local and long.machine.remote and long.machine.listen);
    try std.testing.expectEqualStrings("4043", long.machine.local_port.?);
}

// Zig tip: a `for` over an array literal checks several inputs with one body. The old two-letter names of the
// machine options (`-lo`, `-r`, `-ls`) and `-lsn` (replaced by `--listen`, D-169) are unknown now, and `bad` names the
// word that was refused.
test "-x alone touches no machine; the old names are refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    const x = try parseArgs(arena.allocator(), &.{ "-x", "a.eve" }, &bad);
    const m = x.machine;
    try std.testing.expect(!(m.listen or m.serve or m.local or m.remote));
    for ([_][]const u8{ "-lo", "-r", "-ls", "-lsn" }) |old| {
        try std.testing.expectError(error.UnknownOption, parseArgs(arena.allocator(), &.{ old, "-x", "a.eve" }, &bad));
        try std.testing.expectEqualStrings(old, bad);
    }
}

test "options: flags, command and script" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bad: []const u8 = "";
    const o = try parseArgs(arena.allocator(), &.{ "-d", "-s", "f.cfg", "--check", "a.eve" }, &bad);
    try std.testing.expect(o.debug);
    try std.testing.expectEqualStrings("f.cfg", o.config.?);
    try std.testing.expectEqualStrings("check", o.command.?.name);
    try std.testing.expectEqual(@as(usize, 1), o.args.len);

    const s = try parseArgs(arena.allocator(), &.{"a.eve"}, &bad);
    try std.testing.expectEqualStrings("execute", s.command.?.name);

    const x = try parseArgs(arena.allocator(), &.{ "-x", "-i", "cmds.txt", "a.eve" }, &bad);
    try std.testing.expect(x.execute);
    try std.testing.expectEqualStrings("execute", x.command.?.name);
    try std.testing.expectEqualStrings("cmds.txt", x.slot.?);

    try std.testing.expectError(error.UnknownOption, parseArgs(arena.allocator(), &.{"--bogus"}, &bad));
    try std.testing.expectEqualStrings("--bogus", bad);
    try std.testing.expectError(error.MissingValue, parseArgs(arena.allocator(), &.{"-s"}, &bad));
}

test "completion extension follows the command and -s" {
    try std.testing.expectEqualStrings(".eve", completionExt("check te").?);
    try std.testing.expectEqualStrings(".eve", completionExt("compile ").?);
    try std.testing.expectEqualStrings(".cfg", completionExt("setup c").?);
    try std.testing.expectEqualStrings(".cfg", completionExt("debug a.eve -s c").?);
    try std.testing.expect(completionExt("print x") == null);
    try std.testing.expect(completionExt("che") == null);
}

// Zig tip: `inline for` is unrolled by the compiler: the body is compiled once per element,
// so `word` is a compile-time known string and `"..." ++ word ++ "..."` (compile-time
// concatenation) is allowed. A plain `for` could not do that.
test "repl ends on quit and on exit" {
    inline for (.{ "quit", "exit" }) |word| {
        var buf: [256]u8 = undefined;
        var w: Io.Writer = .fixed(&buf);
        var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
        var in: Io.Reader = .fixed("\nresume\n" ++ word ++ "\nprint x\n");
        try repl(&ctx, &in, null);
        try std.testing.expect(ctx.quit);
        try std.testing.expectEqualStrings(
            prompt ++ prompt ++ "resume command, not yet implemented\n" ++ prompt,
            w.buffered(),
        );
    }
}

test "repl ends at end of input and reports unknown commands" {
    var buf: [256]u8 = undefined;
    var w: Io.Writer = .fixed(&buf);
    var ctx: Context = .{ .out = &w, .io = std.testing.io, .gpa = std.testing.allocator };
    var in: Io.Reader = .fixed("frob\n");
    try repl(&ctx, &in, null);
    try std.testing.expect(!ctx.quit);
    try std.testing.expect(std.mem.indexOf(u8, w.buffered(), "unknown command: frob") != null);
}
