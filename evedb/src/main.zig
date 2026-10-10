//! `evedb`: the Eve test database (README.md). For now it only reports its version and checks
//! that the DuckDB library loads and answers; the server and its commands come next (§7, §9).
const std = @import("std");
const Io = std.Io;

const duckdb = @import("duckdb.zig");

/// The version of evedb itself (README.md §9).
pub const version = "0.0.1";

// Zig tip: in Zig 0.16 `main` may take a `std.process.Init`, filled by the runtime: `init.io`
// is the handle for input and output. Output goes through a `Writer` with a buffer we own;
// `flush` sends what is left in the buffer before the program ends.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    // A self-check: open an in-memory database and ask it a question.
    var db = try duckdb.Database.open(null);
    defer db.close();
    var conn = try db.connect();
    defer conn.close();
    var res = try conn.query("select 40 + 2");
    defer res.deinit();

    try stdout.print("evedb {s}, DuckDB {s}, self-check {d}\n", .{ version, duckdb.libVersion(), res.int(0, 0) });
    try stdout.flush();
}

// Zig tip: tests live only in files the compiler reaches; `_ = duckdb;` in an unnamed test
// block makes `zig build test` run the tests of duckdb.zig too.
test {
    _ = duckdb;
}
