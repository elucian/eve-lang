//! @eve-module gziplib: the gzip files behind the readers of csv, json, txt and fs.lines! (a path that ends in .gz)
//! @spec spec/library/data-language.md#compression
//! @feature F-LIB-09
//! @tests test/level5/e152_gzip_readers
//! A whole file is read into memory and inflated with the standard library's deflate decoder (the gzip container); a file is written by compressing the whole content in memory.
const std = @import("std");

/// True when the path names a gzip file by its extension, `.gz` (data-language.md#compression).
pub fn isGzPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".gz");
}

// @eve-fn csv.read!, json.read!, txt.read!, fs.lines!
// @spec spec/library/data-language.md#compression
// @feature F-LIB-09
// @test test/level5/e152_gzip_readers
/// The content of a gzip stream; null when `packed_bytes` is not one. The result is allocated with `gpa`.
pub fn gunzip(gpa: std.mem.Allocator, packed_bytes: []const u8) error{OutOfMemory}!?[]u8 {
    var input: std.Io.Reader = .fixed(packed_bytes);
    var dec: std.compress.flate.Decompress = .init(&input, .gzip, &.{});
    return dec.reader.allocRemaining(gpa, .unlimited) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
}

// @eve-fn gzip.write, csv.write, json.write, txt.write
// @spec spec/library/data-language.md#compression
// @feature F-LIB-09
// @test test/level5/e165_gzip_write
/// The gzip file (default level) of `content`, allocated with `gpa`.
pub fn gzip(gpa: std.mem.Allocator, content: []const u8) error{OutOfMemory}![]u8 {
    var out = std.Io.Writer.Allocating.initCapacity(gpa, content.len / 2 + 64) catch return error.OutOfMemory;
    errdefer out.deinit();
    const window = try gpa.alloc(u8, std.compress.flate.max_window_len);
    defer gpa.free(window);
    var enc = std.compress.flate.Compress.init(&out.writer, window, .gzip, .default) catch return error.OutOfMemory;
    enc.writer.writeAll(content) catch return error.OutOfMemory;
    enc.finish() catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

test "spec: data-language.md#compression a gzip file inflates to its content" {
    const a = std.testing.allocator;
    const packed_bytes = try gzip(a, "hello hello hello hello");
    defer a.free(packed_bytes);
    try std.testing.expectEqual(@as(u8, 0x1f), packed_bytes[0]);
    const back = (try gunzip(a, packed_bytes)).?;
    defer a.free(back);
    try std.testing.expectEqualStrings("hello hello hello hello", back);
}
