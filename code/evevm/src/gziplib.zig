//! @eve-module gziplib: the gzip files behind the readers of csv, json, txt and fs.lines! (a path that ends in .gz)
//! @spec spec/library/data-language.md#compression
//! @feature F-LIB-09
//! @tests test/level5/e152_gzip_readers
//! A whole file is read into memory and inflated with the standard library's deflate decoder (the gzip container); a stream of bytes and the writers are level 6.
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
