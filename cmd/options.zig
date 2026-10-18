//! The command line: the options, the part words `vm`, `cp`, `db`, `ux` (D-163) and the command words.
//! Part of the `eve` command (cli.zig holds the table of the commands and the REPL loop).
const std = @import("std");
const version = @import("evecm").version;
const parser = @import("evecp").parser;
const vm = @import("evevm").vm;
const client = @import("evevm").client;
const context = @import("context.zig");
const cli = @import("cli.zig");
// Zig tip: the shared names come from context.zig under short local names (`const Context = context.Context;`):
// the same type, not a copy. Files of one module may import each other, also in a circle.
const Command = context.Command;
const prompt = context.prompt;

// Zig tip: a struct can group the result of parsing. Every field has a default, so
// `var o: Options = .{};` is the all-defaults value. `&.{}` is an empty slice literal, the
// default of `args`.
pub const Options = struct {
    help: bool = false,
    version: bool = false,
    debug: bool = false,
    config: ?[]const u8 = null,
    memory: ?[]const u8 = null,
    /// `-x`: execute the script in this process (implies the `execute` command); it never looks for a machine.
    execute: bool = false,
    /// Command chosen with `--<command>` or implied by a script path.
    command: ?*const Command = null,
    /// Positional arguments after the command.
    args: []const []const u8 = &.{},
    /// The options of the machine (`--listen`, `--serve`, `-loc`, `-rem`; spec/library/machine.md).
    machine: client.Cmd = .{},
    /// `-ux`: start the native workbench, eveux, with the rest of the line (D-193; D-172 made it the web page, now `eve ux start`).
    ux: bool = false,
    ux_args: []const []const u8 = &.{},
    /// `-tx`: start the terminal IDE, evetx, with the rest of the line (D-172).
    tx: bool = false,
    /// `-s [file.cfg]`: start the machine as a service, silent (D-185); nothing else may come with it but `-db` (D-188).
    service: bool = false,
    /// `--stdio`: a machine whose door is the standard input and output, for an IDE that starts it (evetx, `ssh host eve --stdio`).
    stdio: bool = false,
    /// `--kill`: stop every other eve program that runs from the same `bin/` folder (eve, evetx, evedb), so a build can replace the files.
    kill: bool = false,
    tx_args: []const []const u8 = &.{},
};

// Zig tip: a small function with no state can be tested alone. `isPort` is true for a text of digits, which is how
// `-loc 4195` tells a port from the next option or a file. `for (text) |c|` visits each byte; `std.ascii.isDigit` is
// the test for one byte. An empty text is not a port.
/// True when `text` is a port number (digits only).
pub fn isPort(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

// Zig tip: the value of `-s` is optional (D-188): `-s` starts the service, and the word after it is its configuration only
// when it ends in `.cfg`. A configuration for anything else is `-e file.cfg` (`--setup file.cfg`).
/// True when `text` is a configuration file name (ends in `.cfg`).
pub fn isConfig(text: []const u8) bool {
    return std.mem.endsWith(u8, text, ".cfg");
}

// Zig tip: the value of `-rem` is optional, so the parser looks at the next word: an option (starts with `-`) or a
// script (ends in `.eve`) is not an address. `std.mem.endsWith` is a test on the end of a slice.
/// True when `text` can be the address after `-rem`.
pub fn isAddress(text: []const u8) bool {
    return text.len > 0 and text[0] != '-' and !std.mem.endsWith(u8, text, ".eve");
}

// Zig tip: `error{ A, B }` is a set of error names. Errors are values, not exceptions: a
// function that can fail says so in its return type (`ParseError!Options`) and the caller must
// deal with it. Errors cannot carry data, so the bad argument is returned through the pointer
// parameter `bad` of parseArgs.
pub const ParseError = error{ MissingValue, UnknownOption, BadWord, ServiceAlone, OutOfMemory };

// Zig tip: `gpa.dupe(T, slice)` copies a slice into new memory, so one element can be changed without touching
// the caller's array (`argv` is `[]const`, read only). Returning a sub-slice, `argv[1..]`, copies nothing.
/// The first word of the command line may name a part of `eve` (D-163): `vm` (the runtime) and `cp` (the compiler)
/// select what the options already do, `cp project` is `--project`, `ux` (the UI) is `--serve`, `db` (the database
/// part) is the command `--db`, `tx` (the terminal IDE) is `-tx`. Gives the line the rest of `parseArgs` reads.
pub fn partWords(gpa: std.mem.Allocator, argv_in: []const []const u8) ParseError![]const []const u8 {
    // `-db --serve file.cfg` is the spelling of `db serve file.cfg` that goes with `-s` (D-186): `eve -s -db --serve evedb.cfg`
    var argv = argv_in;
    for (argv_in, 0..) |a, i| {
        if (std.mem.eql(u8, a, "-db")) {
            const copy = try gpa.dupe([]const u8, argv_in);
            copy[i] = "--db";
            if (i + 1 < copy.len and std.mem.eql(u8, copy[i + 1], "--serve")) copy[i + 1] = "serve";
            argv = copy;
            break;
        }
    }
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
    if (eql(u8, first, "tx") or eql(u8, first, "kill")) {
        const copy = try gpa.dupe([]const u8, argv);
        copy[0] = if (eql(u8, first, "tx")) "-tx" else "--kill";
        return copy;
    }
    if (eql(u8, first, "ux")) {
        // `eve ux start|stop|restart|status` stays the web door (D-163, test e95_test4); any other rest starts eveux (D-193)
        const door = argv.len > 1 and for ([_][]const u8{ "start", "stop", "restart", "status" }) |w| {
            if (eql(u8, argv[1], w)) break true;
        } else false;
        const copy = try gpa.dupe([]const u8, argv);
        copy[0] = if (door) "--serve" else "-ux";
        return copy;
    }
    if (eql(u8, first, "db")) {
        const copy = try gpa.dupe([]const u8, argv);
        copy[0] = "--db";
        return copy;
    }
    return try commandWord(gpa, argv);
}

// Zig tip: the loop skips the options in front of the first word: the ones that take a value (`-s file`) are skipped
// together with it, the others alone. The first word left is a command if it names one, and then `check f.eve` is
// read as `--check f.eve`: the same command, one-shot, with no prompt. A word that ends in `.eve` is a script and a
// word that is no command is left alone (it is a script name or a mistake, as before).
/// `eve check file.eve` is `eve --check file.eve`: the first word that is a command is the command.
pub fn commandWord(gpa: std.mem.Allocator, argv: []const []const u8) ParseError![]const []const u8 {
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (std.mem.eql(u8, a, "--db")) {
            // the words after the database part are its own (`db serve evedb.cfg`): none of them is a command of eve
            return argv;
        } else if (std.mem.eql(u8, a, "-s")) {
            // the service: a configuration file may follow
            if (i + 1 < argv.len and isConfig(argv[i + 1])) i += 1;
        } else if (std.mem.eql(u8, a, "-e") or std.mem.eql(u8, a, "--setup") or std.mem.eql(u8, a, "-m")) {
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
            if (std.mem.endsWith(u8, a, ".eve") or cli.find(a) == null) return argv;
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
        // everything after the command `db` belongs to it (`eve db sql -t file "select ..."`), options included
        if (o.command != null and o.command == cli.find("db")) {
            try rest.append(gpa, a);
            continue;
        }
        if (std.mem.eql(u8, a, "-h") or std.mem.eql(u8, a, "--help")) {
            o.help = true;
        } else if (std.mem.eql(u8, a, "-v") or std.mem.eql(u8, a, "--version")) {
            o.version = true;
        } else if (std.mem.eql(u8, a, "-d")) {
            o.debug = true;
        } else if (std.mem.eql(u8, a, "-x")) {
            o.execute = true;
        } else if (std.mem.eql(u8, a, "-ux")) {
            // everything after `-ux` belongs to eveux (a project folder), so the parse stops here
            o.ux = true;
            o.ux_args = line[i + 1 ..];
            break;
        } else if (std.mem.eql(u8, a, "--kill")) {
            o.kill = true;
        } else if (std.mem.eql(u8, a, "--stdio")) {
            o.stdio = true;
        } else if (std.mem.eql(u8, a, "-tx")) {
            // everything after `-tx` belongs to evetx (a project folder), so the parse stops here
            o.tx = true;
            o.tx_args = line[i + 1 ..];
            break;
        } else if (std.mem.eql(u8, a, "-s")) {
            // `-s` is the service and only the service (D-185, D-188); a `.cfg` after it is its configuration
            o.service = true;
            if (i + 1 < line.len and isConfig(line[i + 1])) {
                i += 1;
                o.config = line[i];
            }
        } else if (std.mem.eql(u8, a, "-e") or std.mem.eql(u8, a, "--setup") or std.mem.eql(u8, a, "-m")) {
            // `-e file.cfg` (`--setup file.cfg`): the configuration file; `-m size`: the memory (D-188)
            i += 1;
            if (i >= line.len) {
                bad.* = a;
                return error.MissingValue;
            }
            if (a[1] == 'm') o.memory = line[i] else o.config = line[i];
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
            const c = cli.find(a[2..]) orelse {
                bad.* = a;
                return error.UnknownOption;
            };
            if (o.command == null) o.command = c else try rest.append(gpa, a);
        } else if (a.len > 1 and a[0] == '-') {
            bad.* = a;
            return error.UnknownOption;
        } else {
            if (o.command == null) o.command = cli.find("execute");
            try rest.append(gpa, a);
        }
    }
    if (o.execute and o.command == null) o.command = cli.find("execute");
    o.args = try rest.toOwnedSlice(gpa);
    // the service takes nothing else (D-188), except the database part: `eve -s -db --serve evedb.cfg` (D-186)
    if (o.service and o.command != cli.find("db") and (o.command != null or o.args.len > 0 or o.execute or o.ux or o.tx or o.kill or o.stdio or
        o.machine.listen or o.machine.serve or o.machine.local or o.machine.remote))
    {
        bad.* = "-s";
        return error.ServiceAlone;
    }
    o.machine.config = o.config;
    if (o.command == cli.find("execute") and o.args.len > 0) {
        o.machine.script = o.args[0];
        o.machine.script_args = o.args[1..];
    }
    return o;
}
