//! Reading the cells of a DuckDB result through its data chunks (README.md section 7).
//!
//! The old `duckdb_value_*` functions are deprecated and cannot be trusted: they answer NULL for a UUID, a list or an enum, and
//! the wrong value for a timestamp with a zone (the tests of `script/evedb_check.py` found this). The chunk API gives the
//! vectors themselves: one array of the real type for each column, and a bitmap of the cells that are not NULL.
const std = @import("std");
const duckdb = @import("duckdb.zig");
const protocol = @import("ewp_protocol");
const ewp = protocol.ewp;
const batch = protocol.batch;
const c = @import("duckdb_c");

// Zig tip: a plain function: the types of the parameters and of the result are written out, and Zig has no default
// arguments, so a call always passes every parameter.
fn id(comptime name: []const u8) c_uint {
    return @field(c, "DUCKDB_TYPE_" ++ name);
}

// Zig tip: the binary layout of the C types is described to Zig with `extern struct`, which has the order and the padding of
// C. A HUGEINT is two 64-bit halves, the low one first.
const HugeInt = extern struct { lower: u64, upper: i64 };
// Zig tip: `UHugeInt` relies on the same Zig feature as `HugeInt` above: see the tip there.
const UHugeInt = extern struct { lower: u64, upper: u64 };
// Zig tip: `Interval` relies on the same Zig feature as `HugeInt` above: see the tip there.
const Interval = extern struct { months: i32, days: i32, micros: i64 };

pub const Error = error{ Unsupported, OutOfMemory };

// Zig tip: `supportedType` relies on the same Zig feature as `HugeInt` above: see the tip there.
/// Which DuckDB types this reader turns into protocol values (the others are refused with `error.Unsupported`).
pub fn supportedType(ty: c_uint) bool {
    return switch (ty) {
        id("BOOLEAN"), id("TINYINT"), id("SMALLINT"), id("INTEGER"), id("BIGINT"), id("UTINYINT"), id("USMALLINT"), id("UINTEGER"), id("UBIGINT"), id("HUGEINT"), id("UHUGEINT"), id("FLOAT"), id("DOUBLE"), id("DECIMAL"), id("DATE"), id("TIME"), id("TIMESTAMP"), id("TIMESTAMP_S"), id("TIMESTAMP_MS"), id("TIMESTAMP_NS"), id("TIMESTAMP_TZ"), id("INTERVAL"), id("VARCHAR"), id("BLOB"), id("UUID"), id("ENUM"), id("SQLNULL") => true,
        else => false,
    };
}

// Zig tip: `Cells` relies on the same Zig feature as `HugeInt` above: see the tip there.
pub const Cells = struct {
    gpa: std.mem.Allocator,
    ncols: usize,
    chunks: []c.duckdb_data_chunk,
    /// The first row of each chunk (and, at the end, the number of rows).
    starts: []u64,
    types: []c_uint,
    scales: []u8,
    internal: []c_uint,
    ltypes: []c.duckdb_logical_type,
    /// `data[chunk * ncols + col]`: the array of the vector, and its validity bitmap (null: every cell is valid).
    data: []?*anyopaque,
    validity: []?[*]u64,

    // Zig tip: the result type `!T` (or `Error!T`) is an error union: a value or an error. `try f()` passes the error to
    // the caller; `f() catch …` handles it in place.
    pub fn init(gpa: std.mem.Allocator, res: *duckdb.Result) Error!Cells {
        const ncols: usize = @intCast(res.columnCount());
        const nch: usize = @intCast(c.duckdb_result_chunk_count(res.raw));
        var s: Cells = .{
            .gpa = gpa,
            .ncols = ncols,
            .chunks = try gpa.alloc(c.duckdb_data_chunk, nch),
            .starts = try gpa.alloc(u64, nch + 1),
            .types = try gpa.alloc(c_uint, ncols),
            .scales = try gpa.alloc(u8, ncols),
            .internal = try gpa.alloc(c_uint, ncols),
            .ltypes = try gpa.alloc(c.duckdb_logical_type, ncols),
            .data = try gpa.alloc(?*anyopaque, nch * ncols),
            .validity = try gpa.alloc(?[*]u64, nch * ncols),
        };
        for (0..ncols) |k| {
            const lt = c.duckdb_column_logical_type(&res.raw, k);
            s.ltypes[k] = lt;
            s.types[k] = c.duckdb_get_type_id(lt);
            s.scales[k] = 0;
            s.internal[k] = 0;
            if (s.types[k] == id("DECIMAL")) {
                s.scales[k] = c.duckdb_decimal_scale(lt);
                s.internal[k] = c.duckdb_decimal_internal_type(lt);
            }
        }
        var rows: u64 = 0;
        for (0..nch) |ci| {
            const ch = c.duckdb_result_get_chunk(res.raw, ci);
            s.chunks[ci] = ch;
            s.starts[ci] = rows;
            rows += c.duckdb_data_chunk_get_size(ch);
            for (0..ncols) |k| {
                const vec = c.duckdb_data_chunk_get_vector(ch, k);
                s.data[ci * ncols + k] = c.duckdb_vector_get_data(vec);
                s.validity[ci * ncols + k] = c.duckdb_vector_get_validity(vec);
            }
        }
        s.starts[nch] = rows;
        return s;
    }

    // Zig tip: a function declared inside a struct whose first parameter is the struct (`self: *T`) is a method: `x.f()`
    // calls `f(&x)`.
    pub fn deinit(self: *Cells) void {
        for (self.chunks) |*ch| c.duckdb_destroy_data_chunk(ch);
        for (self.ltypes) |*lt| c.duckdb_destroy_logical_type(lt);
        self.gpa.free(self.chunks);
        self.gpa.free(self.starts);
        self.gpa.free(self.types);
        self.gpa.free(self.scales);
        self.gpa.free(self.internal);
        self.gpa.free(self.ltypes);
        self.gpa.free(self.data);
        self.gpa.free(self.validity);
    }

    // Zig tip: the result type `?T` is an optional: a value or `null`. The caller must unwrap it (`if (x) |v|`, `orelse`),
    // so a missing value can never be used by accident.
    /// The columns whose type this reader does not handle: the number of the first, or null.
    pub fn firstUnsupported(self: *const Cells) ?usize {
        for (self.types, 0..) |t, k| if (!supportedType(t)) return k;
        return null;
    }

    // Zig tip: a cast is written with a builtin: `@intCast` checks (in safe builds) that the number fits the smaller type,
    // `@bitCast` keeps the bits and changes the type, `@truncate` keeps the low bits.
    fn locate(self: *const Cells, row: u64) struct { chunk: usize, off: usize } {
        var lo: usize = 0;
        var hi: usize = self.chunks.len;
        while (hi - lo > 1) {
            const mid = (lo + hi) / 2;
            if (self.starts[mid] <= row) lo = mid else hi = mid;
        }
        return .{ .chunk = lo, .off = @intCast(row - self.starts[lo]) };
    }

    // Zig tip: `a orelse b` unwraps an optional: the value when there is one, else `b` (which may be `return` or
    // `continue`, leaving the function or the loop).
    pub fn isNull(self: *const Cells, col: usize, row: u64) bool {
        const at = self.locate(row);
        const v = self.validity[at.chunk * self.ncols + col] orelse return false;
        return !c.duckdb_validity_row_is_valid(v, at.off);
    }

    // Zig tip: `array` relies on the same Zig feature as `locate` above: see the tip there.
    fn array(self: *const Cells, comptime T: type, col: usize, row: u64) T {
        const at = self.locate(row);
        const p: [*]const T = @ptrCast(@alignCast(self.data[at.chunk * self.ncols + col].?));
        return p[at.off];
    }

    // Zig tip: `append` relies on the same Zig feature as `Cells` above: see the tip there.
    /// Append the cell to a payload as a value of section 5.2.
    pub fn append(self: *const Cells, b: *ewp.Builder, col: usize, row: u64) !void {
        if (self.types[col] == id("SQLNULL") or self.isNull(col, row)) return b.value(.null);
        var buf: [64]u8 = undefined;
        switch (self.types[col]) {
            id("BOOLEAN") => try b.value(.{ .boolean = self.array(u8, col, row) != 0 }),
            id("TINYINT") => try b.value(.{ .int = self.array(i8, col, row) }),
            id("SMALLINT") => try b.value(.{ .int = self.array(i16, col, row) }),
            id("INTEGER") => try b.value(.{ .int = self.array(i32, col, row) }),
            id("BIGINT") => try b.value(.{ .int = self.array(i64, col, row) }),
            id("UTINYINT") => try b.value(.{ .int = self.array(u8, col, row) }),
            id("USMALLINT") => try b.value(.{ .int = self.array(u16, col, row) }),
            id("UINTEGER") => try b.value(.{ .int = self.array(u32, col, row) }),
            id("UBIGINT") => {
                const u = self.array(u64, col, row);
                if (u <= std.math.maxInt(i64)) {
                    try b.value(.{ .int = @intCast(u) });
                } else try b.value(.{ .huge = std.fmt.bufPrint(&buf, "{d}", .{u}) catch unreachable });
            },
            id("HUGEINT") => {
                const h = self.array(HugeInt, col, row);
                const v: i128 = (@as(i128, h.upper) << 64) | h.lower;
                try b.value(.{ .huge = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable });
            },
            id("UHUGEINT") => {
                const h = self.array(UHugeInt, col, row);
                const v: u128 = (@as(u128, h.upper) << 64) | h.lower;
                try b.value(.{ .huge = std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable });
            },
            id("FLOAT") => try b.value(.{ .real = self.array(f32, col, row) }),
            id("DOUBLE") => try b.value(.{ .real = self.array(f64, col, row) }),
            id("DECIMAL") => {
                const v: i128 = switch (self.internal[col]) {
                    id("SMALLINT") => self.array(i16, col, row),
                    id("INTEGER") => self.array(i32, col, row),
                    id("BIGINT") => self.array(i64, col, row),
                    else => blk: {
                        const h = self.array(HugeInt, col, row);
                        break :blk (@as(i128, h.upper) << 64) | h.lower;
                    },
                };
                try b.value(.{ .decimal = formatDecimal(&buf, v, self.scales[col]) });
            },
            id("DATE") => try b.value(.{ .date = self.array(i32, col, row) }),
            id("TIMESTAMP"), id("TIMESTAMP_TZ") => try b.value(.{ .instant = self.array(i64, col, row) }),
            id("TIMESTAMP_S") => try b.value(.{ .instant = self.array(i64, col, row) * 1_000_000 }),
            id("TIMESTAMP_MS") => try b.value(.{ .instant = self.array(i64, col, row) * 1_000 }),
            id("TIMESTAMP_NS") => try b.value(.{ .instant = @divFloor(self.array(i64, col, row), 1_000) }),
            id("TIME") => {
                const us = self.array(i64, col, row);
                const secs = @divFloor(us, 1_000_000);
                const frac: u64 = @intCast(us - secs * 1_000_000);
                const s: u64 = @intCast(secs);
                const text = if (frac == 0)
                    std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ s / 3600, s % 3600 / 60, s % 60 }) catch unreachable
                else
                    std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{ s / 3600, s % 3600 / 60, s % 60, frac }) catch unreachable;
                try b.value(.{ .string = text });
            },
            id("INTERVAL") => {
                const iv = self.array(Interval, col, row);
                try b.value(.{ .string = std.fmt.bufPrint(&buf, "{d} months {d} days {d} us", .{ iv.months, iv.days, iv.micros }) catch unreachable });
            },
            id("VARCHAR") => try b.value(.{ .string = self.stringAt(col, row) }),
            id("BLOB") => try b.value(.{ .bytes = self.stringAt(col, row) }),
            id("UUID") => {
                const h = self.array(HugeInt, col, row);
                // DuckDB stores a UUID as a hugeint with the top bit flipped
                const raw: i128 = (@as(i128, h.upper) << 64) | h.lower;
                const v: u128 = @as(u128, @bitCast(raw)) ^ (@as(u128, 1) << 127);
                var out: [16]u8 = undefined;
                std.mem.writeInt(u128, &out, v, .big);
                try b.value(.{ .uuid = out });
            },
            id("ENUM") => {
                const index: u32 = switch (self.internal_enum(col)) {
                    id("UTINYINT") => self.array(u8, col, row),
                    id("USMALLINT") => self.array(u16, col, row),
                    else => self.array(u32, col, row),
                };
                const word = c.duckdb_enum_dictionary_value(self.ltypes[col], index);
                defer c.duckdb_free(word);
                try b.value(.{ .string = std.mem.span(word) });
            },
            else => return error.Unsupported,
        }
    }

    // Zig tip: the PostgreSQL wire protocol sends every value as text in its default format (`DataRow`, format 0), so this
    // writes a cell the way PostgreSQL prints it: `t` and `f` for a boolean, `YYYY-MM-DD` for a date, `YYYY-MM-DD HH:MM:SS[.ffffff]`
    // for a timestamp (with `+00` when the column has a zone), `\x` and hexadecimal digits for bytes. A NULL is answered with `false`
    // and nothing written; the caller sends the length -1.
    /// Write the PostgreSQL text of a cell into `out`; false for NULL.
    pub fn appendPgText(self: *const Cells, out: *std.ArrayList(u8), gpa: std.mem.Allocator, col: usize, row: u64) !bool {
        if (self.types[col] == id("SQLNULL") or self.isNull(col, row)) return false;
        var buf: [96]u8 = undefined;
        switch (self.types[col]) {
            id("BOOLEAN") => try out.append(gpa, if (self.array(u8, col, row) != 0) 't' else 'f'),
            id("TINYINT") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(i8, col, row)}) catch unreachable),
            id("SMALLINT") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(i16, col, row)}) catch unreachable),
            id("INTEGER") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(i32, col, row)}) catch unreachable),
            id("BIGINT") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(i64, col, row)}) catch unreachable),
            id("UTINYINT") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(u8, col, row)}) catch unreachable),
            id("USMALLINT") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(u16, col, row)}) catch unreachable),
            id("UINTEGER") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(u32, col, row)}) catch unreachable),
            id("UBIGINT") => try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{self.array(u64, col, row)}) catch unreachable),
            id("HUGEINT") => {
                const h = self.array(HugeInt, col, row);
                const v: i128 = (@as(i128, h.upper) << 64) | h.lower;
                try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable);
            },
            id("UHUGEINT") => {
                const h = self.array(UHugeInt, col, row);
                const v: u128 = (@as(u128, h.upper) << 64) | h.lower;
                try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable);
            },
            id("FLOAT") => try out.appendSlice(gpa, fmtReal(&buf, self.array(f32, col, row))),
            id("DOUBLE") => try out.appendSlice(gpa, fmtReal(&buf, self.array(f64, col, row))),
            id("DECIMAL") => {
                const v: i128 = switch (self.internal[col]) {
                    id("SMALLINT") => self.array(i16, col, row),
                    id("INTEGER") => self.array(i32, col, row),
                    id("BIGINT") => self.array(i64, col, row),
                    else => blk: {
                        const h = self.array(HugeInt, col, row);
                        break :blk (@as(i128, h.upper) << 64) | h.lower;
                    },
                };
                try out.appendSlice(gpa, formatDecimal(&buf, v, self.scales[col]));
            },
            id("DATE") => try out.appendSlice(gpa, fmtDate(&buf, self.array(i32, col, row))),
            id("TIMESTAMP") => try out.appendSlice(gpa, fmtTimestamp(&buf, self.array(i64, col, row), false)),
            id("TIMESTAMP_TZ") => try out.appendSlice(gpa, fmtTimestamp(&buf, self.array(i64, col, row), true)),
            id("TIMESTAMP_S") => try out.appendSlice(gpa, fmtTimestamp(&buf, self.array(i64, col, row) * 1_000_000, false)),
            id("TIMESTAMP_MS") => try out.appendSlice(gpa, fmtTimestamp(&buf, self.array(i64, col, row) * 1_000, false)),
            id("TIMESTAMP_NS") => try out.appendSlice(gpa, fmtTimestamp(&buf, @divFloor(self.array(i64, col, row), 1_000), false)),
            id("TIME") => {
                const us = self.array(i64, col, row);
                const secs: u64 = @intCast(@divFloor(us, 1_000_000));
                const frac: u64 = @intCast(us - @as(i64, @intCast(secs)) * 1_000_000);
                const text = if (frac == 0)
                    std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ secs / 3600, secs % 3600 / 60, secs % 60 }) catch unreachable
                else
                    std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{ secs / 3600, secs % 3600 / 60, secs % 60, frac }) catch unreachable;
                try out.appendSlice(gpa, text);
            },
            id("INTERVAL") => {
                const iv = self.array(Interval, col, row);
                const secs = @divFloor(iv.micros, 1_000_000);
                const frac: u64 = @intCast(iv.micros - secs * 1_000_000);
                const s: u64 = @intCast(@abs(secs));
                const sign: []const u8 = if (iv.micros < 0) "-" else "";
                const text = std.fmt.bufPrint(&buf, "{d} mons {d} days {s}{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{ iv.months, iv.days, sign, s / 3600, s % 3600 / 60, s % 60, frac }) catch unreachable;
                try out.appendSlice(gpa, text);
            },
            id("VARCHAR") => try out.appendSlice(gpa, self.stringAt(col, row)),
            id("BLOB") => {
                try out.appendSlice(gpa, "\\x");
                for (self.stringAt(col, row)) |byte| try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{x:0>2}", .{byte}) catch unreachable);
            },
            id("UUID") => {
                const h = self.array(HugeInt, col, row);
                const raw: i128 = (@as(i128, h.upper) << 64) | h.lower;
                const v: u128 = @as(u128, @bitCast(raw)) ^ (@as(u128, 1) << 127);
                var u: [16]u8 = undefined;
                std.mem.writeInt(u128, &u, v, .big);
                try out.appendSlice(gpa, std.fmt.bufPrint(&buf, "{x:0>2}{x:0>2}{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}-{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15] }) catch unreachable);
            },
            id("ENUM") => {
                const index: u32 = switch (self.internal_enum(col)) {
                    id("UTINYINT") => self.array(u8, col, row),
                    id("USMALLINT") => self.array(u16, col, row),
                    else => self.array(u32, col, row),
                };
                const word = c.duckdb_enum_dictionary_value(self.ltypes[col], index);
                defer c.duckdb_free(word);
                try out.appendSlice(gpa, std.mem.span(word));
            },
            else => return error.Unsupported,
        }
        return true;
    }

    // Zig tip: `internal_enum` relies on the same Zig feature as `deinit` above: see the tip there.
    // Zig tip: each DuckDB type has one wire type; the integers of any width travel as 64 bits, the floats as 64 bits, and the
    // types with no fixed form (a decimal, a huge number, a uuid, a time, an interval) as their text.
    /// The wire type of a column (section 5.5).
    pub fn wireOf(self: *const Cells, col: usize) batch.Wire {
        return switch (self.types[col]) {
            id("BOOLEAN") => .boolean,
            id("TINYINT"), id("SMALLINT"), id("INTEGER"), id("BIGINT"), id("UTINYINT"), id("USMALLINT"), id("UINTEGER") => .int,
            id("FLOAT"), id("DOUBLE") => .real,
            id("DATE") => .date,
            id("TIMESTAMP"), id("TIMESTAMP_TZ"), id("TIMESTAMP_S"), id("TIMESTAMP_MS"), id("TIMESTAMP_NS") => .timestamp,
            id("DECIMAL"), id("HUGEINT"), id("UHUGEINT"), id("UBIGINT") => .decimal,
            id("BLOB") => .blob,
            else => .text,
        };
    }

    // Zig tip: `chunkCount` relies on the same Zig feature as `deinit` above: see the tip there.
    /// How many data chunks the result has, and how many rows chunk `ci` holds.
    pub fn chunkCount(self: *const Cells) usize {
        return self.chunks.len;
    }

    // Zig tip: `chunkRows` relies on the same Zig feature as `locate` above: see the tip there.
    pub fn chunkRows(self: *const Cells, ci: usize) usize {
        return @intCast(self.starts[ci + 1] - self.starts[ci]);
    }

    // Zig tip: `std.mem.sliceAsBytes` sees an array of numbers as its bytes, so a whole vector of BIGINT (or DOUBLE, or
    // TIMESTAMP) goes into the payload with one `appendSlice`: the fast path of the protocol. A narrower integer is widened in a
    // loop. The validity of DuckDB is a bitmap of 64-bit words, least significant bit first, which on a little-endian computer is
    // byte for byte the bitmap of the wire.
    /// Append the chunk `ci` to a payload as one batch (the frame `BATCH` of section 5.5).
    pub fn encodeChunk(self: *const Cells, b: *ewp.Builder, ci: usize) !void {
        const n = self.chunkRows(ci);
        const base = self.starts[ci];
        try b.u32_(@intCast(n));
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(b.gpa);
        for (0..self.ncols) |k| {
            const v = self.validity[ci * self.ncols + k];
            if (v) |bits| {
                try b.u8_(1);
                const bytes: [*]const u8 = @ptrCast(bits);
                try b.buf.appendSlice(b.gpa, bytes[0..batch.validityBytes(n)]);
            } else try b.u8_(0);
            const ptr = self.data[ci * self.ncols + k];
            const ty = self.types[k];
            const little = @import("builtin").cpu.arch.endian() == .little;
            switch (self.wireOf(k)) {
                .boolean => {
                    const p: [*]const u8 = @ptrCast(ptr.?);
                    try b.buf.appendSlice(b.gpa, p[0..n]);
                },
                .int => {
                    if (ty == id("BIGINT") and little) {
                        const p: [*]const u8 = @ptrCast(ptr.?);
                        try b.buf.appendSlice(b.gpa, p[0 .. n * 8]);
                    } else for (0..n) |r| {
                        const v64: i64 = switch (ty) {
                            id("TINYINT") => self.array(i8, k, base + r),
                            id("SMALLINT") => self.array(i16, k, base + r),
                            id("INTEGER") => self.array(i32, k, base + r),
                            id("BIGINT") => self.array(i64, k, base + r),
                            id("UTINYINT") => self.array(u8, k, base + r),
                            id("USMALLINT") => self.array(u16, k, base + r),
                            else => self.array(u32, k, base + r),
                        };
                        try b.i64_(v64);
                    }
                },
                .real => {
                    if (ty == id("DOUBLE") and little) {
                        const p: [*]const u8 = @ptrCast(ptr.?);
                        try b.buf.appendSlice(b.gpa, p[0 .. n * 8]);
                    } else for (0..n) |r| try b.u64_(@bitCast(@as(f64, if (ty == id("FLOAT")) self.array(f32, k, base + r) else self.array(f64, k, base + r))));
                },
                .date => for (0..n) |r| try b.i64_(self.array(i32, k, base + r)),
                .timestamp => {
                    if ((ty == id("TIMESTAMP") or ty == id("TIMESTAMP_TZ")) and little) {
                        const p: [*]const u8 = @ptrCast(ptr.?);
                        try b.buf.appendSlice(b.gpa, p[0 .. n * 8]);
                    } else for (0..n) |r| {
                        const raw = self.array(i64, k, base + r);
                        try b.i64_(switch (ty) {
                            id("TIMESTAMP_S") => raw * 1_000_000,
                            id("TIMESTAMP_MS") => raw * 1_000,
                            id("TIMESTAMP_NS") => @divFloor(raw, 1_000),
                            else => raw,
                        });
                    }
                },
                .text, .decimal, .blob => {
                    text.clearRetainingCapacity();
                    var offs = try b.gpa.alloc(u32, n + 1);
                    defer b.gpa.free(offs);
                    for (0..n) |r| {
                        offs[r] = @intCast(text.items.len);
                        const row = base + r;
                        if (self.isNull(k, row)) continue;
                        if (ty == id("VARCHAR") or ty == id("BLOB")) {
                            try text.appendSlice(b.gpa, self.stringAt(k, row));
                        } else _ = try self.appendPgText(&text, b.gpa, k, row);
                    }
                    offs[n] = @intCast(text.items.len);
                    for (offs) |o| try b.u32_(o);
                    try b.buf.appendSlice(b.gpa, text.items);
                },
            }
        }
    }

    // Zig tip: `internal_enum` relies on the same Zig feature as `deinit` above: see the tip there.
    fn internal_enum(self: *const Cells, col: usize) c_uint {
        return c.duckdb_enum_internal_type(self.ltypes[col]);
    }

    // Zig tip: a DuckDB string is 16 bytes: a length and then either the bytes themselves (12 or fewer) or a prefix and a
    // pointer to the rest. The two C helper functions hide that, and the slice we answer points into DuckDB's memory, which
    // stays valid until the result is destroyed; the caller copies it into the payload at once.
    fn stringAt(self: *const Cells, col: usize, row: u64) []const u8 {
        // the string must be read where it is: a short string is stored inside the 16 bytes of the vector, and a copy on the
        // stack would be gone when this function returns
        const at = self.locate(row);
        const base: [*]c.duckdb_string_t = @ptrCast(@alignCast(self.data[at.chunk * self.ncols + col].?));
        const sp: *c.duckdb_string_t = &base[at.off];
        const len = c.duckdb_string_t_length(sp.*);
        if (len == 0) return "";
        const p = c.duckdb_string_t_data(sp);
        return p[0..len];
    }
};

// Zig tip: `f() catch x` uses `x` when `f` fails; `catch {}` drops the error on purpose. Zig refuses to compile an error
// that nobody handles.
fn fmtReal(buf: []u8, x: anytype) []const u8 {
    if (std.math.isNan(x)) return "NaN";
    if (std.math.isInf(x)) return if (x > 0) "Infinity" else "-Infinity";
    return std.fmt.bufPrint(buf, "{d}", .{x}) catch "0";
}

// Zig tip: `civil` relies on the same Zig feature as `locate` above: see the tip there.
fn civil(days: i64) struct { y: i64, m: u8, d: u8 } {
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const d: u8 = @intCast(doy - @divFloor(153 * mp + 2, 5) + 1);
    const m: u8 = @intCast(if (mp < 10) mp + 3 else mp - 9);
    return .{ .y = yoe + era * 400 + @as(i64, if (m <= 2) 1 else 0), .m = m, .d = d };
}

// Zig tip: `fmtDate` relies on the same Zig feature as `fmtReal` above: see the tip there.
fn fmtDate(buf: []u8, days: i64) []const u8 {
    const c3 = civil(days);
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ @as(u64, @intCast(@max(c3.y, 0))), c3.m, c3.d }) catch "";
}

// Zig tip: `fmtTimestamp` relies on the same Zig feature as `fmtReal` above: see the tip there.
fn fmtTimestamp(buf: []u8, micros: i64, zone: bool) []const u8 {
    const secs = @divFloor(micros, 1_000_000);
    const frac: u64 = @intCast(micros - secs * 1_000_000);
    const days = @divFloor(secs, 86400);
    const rem: u64 = @intCast(secs - days * 86400);
    const c3 = civil(days);
    const tz: []const u8 = if (zone) "+00" else "";
    if (frac == 0) return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}{s}", .{ @as(u64, @intCast(@max(c3.y, 0))), c3.m, c3.d, rem / 3600, rem % 3600 / 60, rem % 60, tz }) catch "";
    return std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}{s}", .{ @as(u64, @intCast(@max(c3.y, 0))), c3.m, c3.d, rem / 3600, rem % 3600 / 60, rem % 60, frac, tz }) catch "";
}

// Zig tip: `pgOid` relies on the same Zig feature as `HugeInt` above: see the tip there.
/// The number of the PostgreSQL type that stands for a DuckDB type (the `oid` of `RowDescription`).
pub fn pgOid(ty: c_uint) u32 {
    return switch (ty) {
        id("BOOLEAN") => 16,
        id("TINYINT"), id("SMALLINT") => 21,
        id("INTEGER") => 23,
        id("BIGINT"), id("UTINYINT"), id("USMALLINT"), id("UINTEGER") => 20,
        id("UBIGINT"), id("HUGEINT"), id("UHUGEINT"), id("DECIMAL") => 1700,
        id("FLOAT") => 700,
        id("DOUBLE") => 701,
        id("DATE") => 1082,
        id("TIME") => 1083,
        id("TIMESTAMP"), id("TIMESTAMP_S"), id("TIMESTAMP_MS"), id("TIMESTAMP_NS") => 1114,
        id("TIMESTAMP_TZ") => 1184,
        id("INTERVAL") => 1186,
        id("BLOB") => 17,
        id("UUID") => 2950,
        else => 25,
    };
}

// Zig tip: `pgSize` relies on the same Zig feature as `HugeInt` above: see the tip there.
/// The size in bytes of a PostgreSQL type for `RowDescription` (-1: variable).
pub fn pgSize(oid: u32) i16 {
    return switch (oid) {
        16 => 1,
        21 => 2,
        23, 700, 1082 => 4,
        20, 701, 1114, 1184, 1083 => 8,
        2950 => 16,
        1186 => 16,
        else => -1,
    };
}

// Zig tip: a decimal is an integer and a scale. The digits of the absolute value are padded on the left with zeros until there
// is at least one digit before the point, then the point goes `scale` digits from the right. `abs` of the smallest i128 does
// not fit, so the unsigned type is used for the digits.
/// The text of the decimal `v` with `scale` digits after the point, written in `buf`.
pub fn formatDecimal(buf: []u8, v: i128, scale: u8) []const u8 {
    var digits: [48]u8 = undefined;
    const mag: u128 = if (v < 0) @as(u128, @intCast(-(v + 1))) + 1 else @intCast(v);
    var n: usize = 0;
    var m = mag;
    while (m > 0) : (m /= 10) {
        digits[n] = '0' + @as(u8, @intCast(m % 10));
        n += 1;
    }
    while (n <= scale) : (n += 1) digits[n] = '0';
    var len: usize = 0;
    if (v < 0) {
        buf[len] = '-';
        len += 1;
    }
    var i: usize = n;
    while (i > 0) {
        i -= 1;
        buf[len] = digits[i];
        len += 1;
        if (scale > 0 and i == scale) {
            buf[len] = '.';
            len += 1;
        }
    }
    return buf[0..len];
}

// Zig tip: a `test` block is compiled only by `zig build test`; `try std.testing.expect…` fails the test, with the values,
// when a check is false.
test "decimals are written with their scale" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("12.50", formatDecimal(&buf, 1250, 2));
    try std.testing.expectEqualStrings("-0.05", formatDecimal(&buf, -5, 2));
    try std.testing.expectEqualStrings("7", formatDecimal(&buf, 7, 0));
    try std.testing.expectEqualStrings("0.001", formatDecimal(&buf, 1, 3));
}

// Zig tip: test "the cells of a result: many types, NULLs, and more than one chunk" relies on the same Zig feature as test
// "decimals are written with their scale" above: see the tip there.
test "the cells of a result: many types, NULLs, and more than one chunk" {
    const gpa = std.testing.allocator;
    var db = try duckdb.Database.open(null);
    defer db.close();
    var conn = try db.connect();
    defer conn.close();
    var res = try conn.query("select i::bigint as n, case when i % 3 = 0 then null else i::varchar end as s, '00112233-4455-6677-8899-aabbccddeeff'::uuid as u, 12.5::decimal(30,2) as d, 'y'::enum('x','y') as e, timestamptz '2026-10-17 08:00:00+00' as t from range(5000) as r(i)");
    defer res.deinit();
    var cells = try Cells.init(gpa, &res);
    defer cells.deinit();
    try std.testing.expect(cells.firstUnsupported() == null);
    var b = ewp.Builder.init(gpa);
    defer b.deinit();
    for ([_]u64{ 0, 3, 2047, 2048, 4999 }) |row| {
        b.buf.clearRetainingCapacity();
        for (0..6) |k| try cells.append(&b, k, row);
        var cur: ewp.Cursor = .{ .buf = b.buf.items };
        try std.testing.expectEqual(@as(i64, @intCast(row)), (try cur.value()).int);
        const sv = try cur.value();
        if (row % 3 == 0) try std.testing.expectEqual(std.meta.Tag(ewp.Value).null, std.meta.activeTag(sv)) else try std.testing.expect(sv == .string);
        const u = try cur.value();
        try std.testing.expectEqual(@as(u8, 0x00), u.uuid[0]);
        try std.testing.expectEqual(@as(u8, 0xff), u.uuid[15]);
        try std.testing.expectEqualStrings("12.50", (try cur.value()).decimal);
        try std.testing.expectEqualStrings("y", (try cur.value()).string);
        try std.testing.expectEqual(@as(i64, 1792224000000000), (try cur.value()).instant);
    }
    var lres = try conn.query("select [1,2] as l");
    defer lres.deinit();
    var lcells = try Cells.init(gpa, &lres);
    defer lcells.deinit();
    try std.testing.expectEqual(@as(?usize, 0), lcells.firstUnsupported());
}
