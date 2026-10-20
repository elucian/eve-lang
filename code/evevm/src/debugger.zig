//! The debugger of the VM (F-TLS-04): `eve debug <file.eve>` runs a script and stops before its statements, so that a
//! person, or a program such as `evetx`, can drive it with commands, one per line on the standard input:
//!
//!   run         start the execution, or go on until the next breakpoint
//!   halt        stop the program at once (the run ends as stopped)
//!   next        execute the current statement without going down into the calls it makes
//!   step        go to the next statement, down into the function that the line calls
//!   exit        finish the current subprogram and stop in its caller
//!   trace       go on automatically, writing each statement, until the next breakpoint
//!   break <n>   set a breakpoint on line n;  clear <n|all>  remove one or all of them
//!   delay <ms>  the wait after each statement of trace (400 at first)
//!
//! What the debugger writes are lines that begin with `@debug `, on the standard output between the lines of the
//! program: `@debug paused <line> <depth> <text of the line>` each time it stops, `@debug trace <line> <depth>`
//! in trace mode, `@debug break <n>`, `@debug clear <n>`, `@debug error <message>`, and `@debug end <exit status>`
//! when the program ends. Only the main task is debugged: the tasks of `parallel` and `spawn` run free.
const std = @import("std");
const Io = std.Io;
const interp = @import("interp.zig");
const Interp = interp.Interp;
const Node = interp.Node;
const Signal = interp.Signal;

/// What the debugger does when it resumes.
pub const Mode = enum { start, run, step, next, exit, trace };

/// One debugging session.
pub const Debugger = struct {
    out: *Io.Writer,
    in: *Io.Reader,
    io: Io,
    gpa: std.mem.Allocator,
    /// Trace goes slowly, so that a person can follow it: this many milliseconds after each statement.
    trace_ms: u32 = 400,
    /// The text of the script, to show the line where the program stops.
    src: []const u8 = "",
    mode: Mode = .start,
    /// The depth of the call stack when `next` or `exit` was given (`Interp.frames`).
    ref_depth: u32 = 0,
    breaks: std.ArrayList(u32) = .empty,
    halted: bool = false,
    /// The commands ended (the input is closed): the program goes on to its end without stopping.
    detached: bool = false,

    /// The hook to give to the interpreter (`Interp.dbg`).
    pub fn hook(self: *Debugger) interp.DebugHook {
        return .{ .ctx = self, .before = before };
    }

    fn hasBreak(self: *const Debugger, line: u32) bool {
        return std.mem.indexOfScalar(u32, self.breaks.items, line) != null;
    }

    /// Does the debugger stop before this node? Declarations and blocks are not statements to stop on.
    fn isStatement(n: *const Node) bool {
        return switch (n.tag) {
            .block, .process, .class, .trait, .function, .procedure, .method, .generator => false,
            else => true,
        };
    }

    /// Called before each statement of the main task: decide whether to stop, and stop.
    fn before(ctx: *anyopaque, it: *Interp, n: *const Node) Signal!void {
        const self: *Debugger = @ptrCast(@alignCast(ctx));
        if (self.halted) return error.Stop;
        if (self.detached or !isStatement(n) or n.line == 0) return;
        const line = n.line;
        const depth: u32 = @intCast(it.frames.items.len);
        const stop_here = switch (self.mode) {
            .start, .step => true,
            .next => depth <= self.ref_depth,
            .exit => depth < self.ref_depth,
            .run, .trace => false,
        } or self.hasBreak(line);
        if (self.mode == .trace and !stop_here) {
            self.out.print("@debug trace {d} {d}\n", .{ line, depth }) catch return error.WriteFailed;
            self.out.flush() catch return error.WriteFailed;
            self.io.sleep(.fromMilliseconds(self.trace_ms), .awake) catch {};
        }
        if (stop_here) try self.pause(it, line, depth);
    }

    /// The text of line `n` (from 1) of the script, or "" when there is no such line.
    fn lineText(self: *const Debugger, n: u32) []const u8 {
        var it = std.mem.splitScalar(u8, self.src, '\n');
        var k: u32 = 1;
        while (it.next()) |l| : (k += 1) {
            if (k == n) return std.mem.trim(u8, l, " \t\r");
        }
        return "";
    }

    /// Stop before a statement: write where, then read commands until one of them resumes the program.
    fn pause(self: *Debugger, it: *Interp, line: u32, depth: u32) Signal!void {
        it.out.flush() catch {};
        self.writeVars(it);
        self.out.print("@debug paused {d} {d} {s}\n", .{ line, depth, self.lineText(line) }) catch return error.WriteFailed;
        self.out.flush() catch return error.WriteFailed;
        while (true) {
            const raw = (self.in.takeDelimiter('\n') catch null) orelse {
                self.detached = true;
                return;
            };
            const cmd = std.mem.trim(u8, raw, " \t\r");
            if (cmd.len == 0) continue;
            if (try self.command(cmd, depth)) return;
        }
    }

    /// Write the variables that the program can see (`@debug vars`, then one `@debug var name=value` each).
    fn writeVars(self: *Debugger, it: *Interp) void {
        self.out.writeAll("@debug vars\n") catch return;
        var cur: ?*interp.Scope = it.scope;
        while (cur) |sc| : (cur = sc.parent) {
            if (it.prelude) |p| {
                if (sc == p) break;
            }
            for (sc.binds.items) |b| {
                // the names that the language adds (`$epsilon`, `_`, `jobs`) are not the program's variables
                if (b.name.len == 0 or b.name[0] == '$' or std.mem.eql(u8, b.name, "_") or std.mem.eql(u8, b.name, "jobs")) continue;
                var buf: std.ArrayList(u8) = .empty;
                it.show(&buf, b.v.value, true) catch continue;
                if (buf.items.len > 0 and buf.items[0] == '<') continue; // a function, a procedure, a class
                for (buf.items) |*ch| {
                    if (ch.* == '\n' or ch.* == '\r') ch.* = ' ';
                }
                const shown = buf.items[0..@min(buf.items.len, 200)];
                self.out.print("@debug var {s}={s}\n", .{ b.name, shown }) catch return;
            }
        }
    }

    /// Run one command of the person who debugs. True when the program resumes.
    fn command(self: *Debugger, cmd: []const u8, depth: u32) Signal!bool {
        var words = std.mem.tokenizeScalar(u8, cmd, ' ');
        const verb = words.next() orelse return false;
        const eql = std.mem.eql;
        if (eql(u8, verb, "run")) {
            self.mode = .run;
        } else if (eql(u8, verb, "trace")) {
            self.mode = .trace;
        } else if (eql(u8, verb, "step")) {
            self.mode = .step;
        } else if (eql(u8, verb, "next")) {
            self.mode = .next;
            self.ref_depth = depth;
        } else if (eql(u8, verb, "exit")) {
            self.mode = .exit;
            self.ref_depth = depth;
        } else if (eql(u8, verb, "halt")) {
            self.halted = true;
            return error.Stop;
        } else if (eql(u8, verb, "delay")) {
            // `delay <ms>`: the wait after each statement of `trace`
            const ms = std.fmt.parseInt(u32, words.next() orelse "", 10) catch {
                self.out.writeAll("@debug error delay needs a number of milliseconds\n") catch return error.WriteFailed;
                self.out.flush() catch return error.WriteFailed;
                return false;
            };
            self.trace_ms = @min(ms, 10000);
            return false;
        } else if (eql(u8, verb, "break") or eql(u8, verb, "clear")) {
            try self.breakCommand(verb, words.next());
            return false;
        } else {
            self.out.print("@debug error unknown command {s}\n", .{verb}) catch return error.WriteFailed;
            self.out.flush() catch return error.WriteFailed;
            return false;
        }
        return true;
    }

    /// `break <n>`, `clear <n>` and `clear all`.
    fn breakCommand(self: *Debugger, verb: []const u8, arg: ?[]const u8) Signal!void {
        const text = arg orelse {
            self.out.print("@debug error {s} needs a line number\n", .{verb}) catch return error.WriteFailed;
            self.out.flush() catch return error.WriteFailed;
            return;
        };
        if (std.mem.eql(u8, verb, "clear") and std.mem.eql(u8, text, "all")) {
            self.breaks.clearRetainingCapacity();
            self.out.writeAll("@debug clear all\n") catch return error.WriteFailed;
        } else if (std.fmt.parseInt(u32, text, 10)) |n| {
            if (std.mem.eql(u8, verb, "break")) {
                if (!self.hasBreak(n)) try self.breaks.append(self.gpa, n);
            } else if (std.mem.indexOfScalar(u32, self.breaks.items, n)) |i| {
                _ = self.breaks.orderedRemove(i);
            }
            self.out.print("@debug {s} {d}\n", .{ verb, n }) catch return error.WriteFailed;
        } else |_| {
            self.out.print("@debug error {s}: {s} is not a line number\n", .{ verb, text }) catch return error.WriteFailed;
        }
        self.out.flush() catch return error.WriteFailed;
    }
};
