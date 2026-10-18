//! The texts of `help`: one short line per command for the table, and for `help <command>` the syntax, a free text,
//! the options (sub-commands) and examples. Only data: the layout (width, wrapping, colors) is in screen.zig, so the
//! same text is drawn again when the window changes size.
const std = @import("std");

/// One option or sub-command of a command, with its explanation.
pub const Opt = struct { word: []const u8, text: []const u8 };

// Zig tip: a struct whose fields have defaults (`= &.{}`, an empty slice) lets each entry below name only what it has.
// `[]const []const u8` is a slice of texts. In `text`, a `\n` starts a new paragraph; the layout wraps each paragraph to
// the width of the screen.
/// What `help` knows about one command.
pub const Entry = struct {
    name: []const u8,
    /// The row of the table: short, one line at the default width.
    short: []const u8,
    syntax: []const []const u8,
    text: []const u8,
    options: []const Opt = &.{},
    examples: []const []const u8 = &.{},
};

/// The commands of the prompt, in the order of the jump table of cli.zig (a test keeps the two in step).
pub const entries = [_]Entry{
    .{
        .name = "check",
        .short = "check the syntax of a script, do not execute it",
        .syntax = &.{"check <file.eve> [<file.eve> ...]"},
        .text = "Parses each file and prints every syntax error as file:line:col: error: text. Nothing is executed.\n" ++
            "The exit status is 65 when a file has a syntax error, 66 when a file cannot be read and 64 when no name is given. Right (at the end of the line) completes the name of the file.",
        .examples = &.{"check hello.eve"},
    },
    .{
        .name = "compile",
        .short = "compile a script to bytecode (not implemented yet)",
        .syntax = &.{"compile <file.eve>"},
        .text = "Reserved for the bytecode compiler. Today it only prints that the command is not yet implemented and sets the exit status to 70.",
    },
    .{
        .name = "doc",
        .short = "write Markdown documentation of a .eve file or folder",
        .syntax = &.{"doc <folder | file.eve> [<output folder>]"},
        .text = "Writes the Markdown documentation of one .eve file, or of the .eve files of a folder, into the output folder (default: doc).\n" ++
            "It says so when the folder holds no .eve file; the exit status is 66 when the path cannot be read.",
        .examples = &.{ "doc src", "doc src/main.eve pages" },
    },
    .{
        .name = "debug",
        .short = "execute the main process under the debugger",
        .syntax = &.{"debug <file.eve>"},
        .text = "Runs the script and stops before its first statement. The commands are read from the standard input, one per line: run (go on to the next breakpoint, or start), halt (stop the program at once), next (execute the statement without going into the calls), step (go into the call of the line), exit (finish the subprogram and stop in its caller), trace (go on, writing each statement, until the next breakpoint), break <line> and clear <line|all>.\n" ++
            "The debugger writes lines that begin with @debug: @debug paused <line> <depth> <text>, @debug trace, @debug break, @debug end <status>. Only the main task is debugged.",
    },
    .{
        .name = "execute",
        .short = "run the main process of a script, parsed first",
        .syntax = &.{"execute <file.eve> [<argument> ...]"},
        .text = "Parses the file as check does and, only if it is correct, runs its main process. The words after the file are the arguments of process main.\n" ++
            "A script with a syntax error does not start (exit status 65). The errors that the script does not recover from are shown after the run, and the exit status is the one of the script.",
        .examples = &.{ "execute etl.eve", "execute report.eve 2026-10 csv" },
    },
    .{
        .name = "project",
        .short = "make a project with the standard layout",
        .syntax = &.{ "project init <folder>", "project new <folder>" },
        .text = "Makes the standard layout of a project in the folder (the layout is described in plan/design-project-layout.md) and says how many files it created and how many it kept.",
        .options = &.{
            .{ .word = "init", .text = "works on a new or an existing folder and keeps every file that is already there." },
            .{ .word = "new", .text = "the same, but it refuses (exit status 73) when the folder exists and is not empty." },
        },
        .examples = &.{"project new sales"},
    },
    .{
        .name = "db",
        .short = "database: sql, views and tables, proc list",
        .syntax = &.{ "db sql [-t] <file> <statement>", "db create view <file> <name> <select…>", "db create table <file> <name> <select…>", "db drop view <file> <name>", "db import <file.db> <file> [table]", "db export <file.db> <table> <file>", "db serve [evedb.cfg]", "db proc list" },
        .text = "db sql runs SQL statements on a SQLite file. db create makes a view or a table from a select; db drop view removes a view. " ++
            "db serve starts evedb, the database server that answers as PostgreSQL on port 5432, with its configuration file; eve -s -db --serve evedb.cfg starts it as a service. " ++
            "db import reads a .csv, .txt, .tsv, .json or .dbf file into a new table of the database (the types are found from the values; a DBF file declares them); db export writes a table as .csv, .txt, .json or .dbf. A spreadsheet is saved as CSV first. " ++
            "db proc list lists each module of the folder proc/ of the project, in order, with the hash of its source and the procedures and functions it exports with their signatures. " ++
            "It says so when there is no folder proc/ here (exit status 66).",
        .options = &.{
            .{ .word = "sql", .text = "run a statement on the database file." },
            .{ .word = "create view", .text = "make the view <name> as the <select>." },
            .{ .word = "create table", .text = "make the table <name> from the <select>." },
            .{ .word = "drop view", .text = "remove the view <name>." },
            .{ .word = "import", .text = "load a CSV, TXT, JSON or DBF file as a new table." },
            .{ .word = "export", .text = "write a table as CSV, TXT, JSON or DBF." },
            .{ .word = "serve", .text = "run evedb (PostgreSQL protocol, DuckDB inside) with a configuration file." },
            .{ .word = "proc list", .text = "the stored procedures written in Eve." },
        },
    },
    .{
        .name = "begin",
        .short = "start the step by step execution (not implemented yet)",
        .syntax = &.{"begin"},
        .text = "Reserved for the debugger, with enter and resume. Today it only prints that the command is not yet implemented.",
    },
    .{
        .name = "enter",
        .short = "execute the next step (not implemented yet)",
        .syntax = &.{"enter"},
        .text = "Reserved for the debugger, with begin and resume. Today it only prints that the command is not yet implemented.",
    },
    .{
        .name = "run",
        .short = "run the loaded script, or the file given",
        .syntax = &.{"run [<file.eve>]"},
        .text = "Runs the loaded script, or loads and runs the file given. A script that was not parsed is parsed first, and a syntax error stops the run.\n" ++
            "Without capture on, what the script prints appears here; the status bar shows the time of the run.",
        .examples = &.{ "run", "run hello.eve" },
    },
    .{
        .name = "load",
        .short = "load a script, forget the previous one",
        .syntax = &.{"load <file.eve>"},
        .text = "Reads the file as the current script and forgets the previous one; it says '<name>: loaded'. The other commands (parse, run, ast, inspect, errors, status) work on this script. The exit status is 66 when the file cannot be read.",
        .examples = &.{"load hello.eve"},
    },
    .{
        .name = "parse",
        .short = "parse the loaded script, report syntax errors",
        .syntax = &.{"parse [<file.eve>]"},
        .text = "Parses the loaded script, or loads and parses the file given. It prints '<name>: parse ok, <n> nodes', or the syntax error as file:line:col: error: text (exit status 65).",
    },
    .{
        .name = "ast",
        .short = "write the syntax tree to <outdir>/<name>.ast",
        .syntax = &.{"ast [<depth>]"},
        .text = "Writes the syntax tree of the loaded script, one node per line, to <outdir>/<name>.ast. Nodes deeper than the depth (default 64) are shown as '... n more'. The folder is set by outdir.",
    },
    .{
        .name = "inspect",
        .short = "write the introspection report <outdir>/<name>.inspect",
        .syntax = &.{"inspect"},
        .text = "Writes <outdir>/<name>.inspect: the node count by kind, the depth, the declarations, the result of the run, the global variables and the variables of the last process with their type and value.",
    },
    .{
        .name = "errors",
        .short = "report the errors of the script",
        .syntax = &.{"errors"},
        .text = "Writes the errors of the loaded script to <outdir>/<name>.err: the syntax error, the errors raised while it ran and the expectations that failed, also those that a recover handled. It prints how many there are.",
    },
    .{
        .name = "status",
        .short = "the state of the machine: script, configuration, doors",
        .syntax = &.{"status"},
        .text = "Shows, in one page: the version; the script (loaded, parsed, running or finished, errors); the folder of the reports; the configuration file (loaded, or the defaults); the ports of the two doors; and, when a machine answers on them, what it is doing (idle, or the script it runs and for how long), its requests, its uptime and its parts.\n" ++
            "It also adds one line for the script to <outdir>/summary.log. When nothing listens on the HTTP port the probe can take about two seconds on Windows.",
    },
    .{
        .name = "listen",
        .short = "open, stop or ask the IPC door of the machine; the prompt stays",
        .syntax = &.{ "listen [start|stop|restart|status]", "listen serve" },
        .text = "The IPC door is the way for other programs on this computer to talk to the machine: a socket named eve-<domain>-<ipc_port>.sock in the runtime folder; the port number comes from eve.cfg.\n" ++
            "The door runs in a thread of this program, so the prompt stays and the next command can already use it. The requests it answers appear in the upper part. quit closes the door with the program. When another machine already holds the door, it prints 'already running' (exit status 75); stop and status print 'no local machine' when nobody answers (69).",
        .options = &.{
            .{ .word = "start", .text = "open the door (the default when no word is given)." },
            .{ .word = "stop", .text = "close the door; the prompt goes on." },
            .{ .word = "restart", .text = "stop the machine that holds the door and start it again, with the same doors." },
            .{ .word = "status", .text = "show the doors, the scripts run, the requests, the uptime and what the machine is doing." },
            .{ .word = "serve", .text = "as a second word, open the HTTP door in the same machine (listen serve)." },
        },
        .examples = &.{ "listen", "listen serve", "listen status", "listen stop" },
    },
    .{
        .name = "serve",
        .short = "open, stop or ask the HTTP door of the machine; the prompt stays",
        .syntax = &.{ "serve [start|stop|restart|status]", "serve listen" },
        .text = "The HTTP door serves the files of the web folder and answers JSON-RPC messages sent with POST /rpc, at http_host:http_port of eve.cfg. It is also the door of other computers (-rem).\n" ++
            "It works as listen does: it runs in a thread, the prompt stays, the requests appear in the upper part, and quit closes it. stop and status try the IPC door first and then the HTTP door.",
        .options = &.{
            .{ .word = "start", .text = "open the door (the default when no word is given)." },
            .{ .word = "stop", .text = "close the door; the prompt goes on." },
            .{ .word = "restart", .text = "stop the machine and start it again." },
            .{ .word = "status", .text = "show the doors, the scripts run, the requests, the uptime and what the machine is doing." },
            .{ .word = "listen", .text = "as a second word, open the IPC door in the same machine (serve listen)." },
        },
        .examples = &.{ "serve", "serve status" },
    },
    .{
        .name = "outdir",
        .short = "set the folder of the report files",
        .syntax = &.{"outdir [<folder>]"},
        .text = "Sets the folder where ast, inspect, errors and status write their files (default: temp/output). The folder is created when it is missing. Without a name it shows the current folder.",
        .examples = &.{"outdir temp/reports"},
    },
    .{
        .name = "capture",
        .short = "keep the script output in a file: capture on|off",
        .syntax = &.{"capture [on|off]"},
        .text = "With capture on, what a script prints is kept in <outdir>/<name>.out instead of appearing here, and run reports '<name>: run, exit <code>'. capture off writes it here again. Without a word it means on.",
        .options = &.{
            .{ .word = "on", .text = "keep the output in a file." },
            .{ .word = "off", .text = "show the output here." },
        },
    },
    .{
        .name = "log",
        .short = "add a line of text to summary.log",
        .syntax = &.{"log <text>"},
        .text = "Adds the text as a line of <outdir>/summary.log, a marker between scripts. status adds the line of the script to the same file.",
        .examples = &.{"log start of the nightly batch"},
    },
    .{
        .name = "print",
        .short = "display the value of a global variable (not implemented yet)",
        .syntax = &.{"print <variable>"},
        .text = "Reserved for the debugger. Today it only prints that the command is not yet implemented.",
    },
    .{
        .name = "resume",
        .short = "run until the next halt statement (not implemented yet)",
        .syntax = &.{"resume"},
        .text = "Reserved for the debugger, with begin and enter. Today it only prints that the command is not yet implemented.",
    },
    .{
        .name = "report",
        .short = "report the state of the running script",
        .syntax = &.{"report"},
        .text = "Prints 'report: pc <line of the last statement>, <n> steps, idle' (or running). It is also the command that a program can append to a slot file to watch a script that runs.",
    },
    .{
        .name = "stop",
        .short = "stop the doors (ipc and http) and the scripts; the prompt stays",
        .syntax = &.{ "stop", "eve stop" },
        .text = "Closes the IPC door and the HTTP door at the same time, and tells every script that runs in the machine to stop at its next statement. The prompt stays: the program does not exit, and listen or serve open the doors again.\n" ++
            "When this program has no door open, it stops the machine of another process that answers on the doors of eve.cfg, such as the one that evevm started; that machine then ends. From the system prompt, eve stop does the same and ends.\n" ++
            "In a slot file (-i) stop ends the script that runs, or serve mode. quit leaves the prompt.",
        .examples = &.{ "stop", "listen serve", "stop" },
    },
    .{
        .name = "clear",
        .short = "clear the upper part of the screen",
        .syntax = &.{"clear"},
        .text = "Empties the upper part, the output and its scrollback, and keeps the command line and the status bar.",
    },
    .{
        .name = "setup",
        .short = "load the configuration file (not implemented yet)",
        .syntax = &.{"setup <file.cfg>"},
        .text = "Reserved. Today the option -e <file.cfg> (--setup <file.cfg>) names the configuration file when eve starts, and status shows which file it looks for.",
    },
    .{
        .name = "help",
        .short = "this table, or the syntax and options of one command",
        .syntax = &.{ "help [<command>]", "? [<command>]", "<command> ?" },
        .text = "Without a word it draws the table of the commands, with a line between the commands. With a command it shows the syntax, an explanation, the options and examples of that command.\n" ++
            "? is an ordinary key: type it and press Enter, alone for the table, before a command (? listen) or after it (listen ?) for the page of that command.\n" ++
            "The width of the table and of the texts is 100 characters by default, and never more than the window. Set another width with the variable EVE_WIDTH in the environment or with eve_width in eve.cfg (the environment wins). The layout is drawn again when the window is resized.",
        .examples = &.{ "help", "help listen", "check ?" },
    },
    .{
        .name = "shell",
        .short = "run a command of the system; the prompt stays in eve",
        .syntax = &.{ "shell <command>", "!<command>" },
        .text = "Gives the rest of the line, as it was typed, to the shell of the system (the one that started eve: SHELL, else cmd.exe on Windows), in the current folder. Its output and its errors are shown as they come, and the prompt of eve comes back when the command ends: there is no need to leave eve and start it again. The command gets no input: a program that asks a question gets the end of its input. To leave eve for the shell, type exit.\n" ++
            "Over the machine API the same is vm.shell, and a session of vm.eval takes shell <command> and !<command> too (the IPC and stdio doors only).",
        .examples = &.{ "shell dir", "!git status", "!zig build -p ." },
    },
    .{
        .name = "quit",
        .short = "leave the prompt; the doors close with it",
        .syntax = &.{"quit"},
        .text = "Leaves the prompt and ends the program, and with it the doors opened by listen or serve. Ctrl-D on an empty line does the same.",
    },
    .{
        .name = "exit",
        .short = "same as quit",
        .syntax = &.{"exit"},
        .text = "The same as quit.",
    },
};

// Zig tip: `for (&entries) |*e|` walks the array by pointer, so the result of `find` points at the entry itself and
// nothing is copied. The function answers an optional: the entry, or null for a name that has no help.
/// The entry of a command, or null.
pub fn find(name: []const u8) ?*const Entry {
    for (&entries) |*e| if (std.mem.eql(u8, e.name, name)) return e;
    return null;
}

/// The position of a command in `entries` (the argument of a help block), or null.
pub fn indexOf(name: []const u8) ?usize {
    for (&entries, 0..) |*e, i| if (std.mem.eql(u8, e.name, name)) return i;
    return null;
}

test "every entry has a short line that fits a row of the default table" {
    for (&entries) |*e| {
        try std.testing.expect(e.short.len > 0 and e.short.len <= 68);
        try std.testing.expect(e.syntax.len > 0 and e.text.len > 0);
    }
    try std.testing.expect(find("listen") != null and find("nope") == null);
}
