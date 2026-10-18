//! @eve-module kind: what a file is, and which viewer opens it
//! @spec eveux/README.md#8-previews
//! @feature F-TLS-19
//! @decision D-193
//! @tests zig test src/preview/kind.zig (from eveux/)
//! Pure functions on a file name; no file is read. The viewer decides the tab; a file of an unknown kind opens the file card.
const std = @import("std");

/// The kind of a file by its name.
pub const Kind = enum { eve, sql, json, xml, html, css, javascript, markdown, text, config, image, svg, audio, video, database, binary };

/// The tab that shows a kind of file.
pub const Viewer = enum { editor, markdown, html, image, audio_video, database, card };

const Row = struct { ext: []const u8, kind: Kind };

// @eve-impl the table of extensions; lower case, with the dot; the first match wins
const table = [_]Row{
    .{ .ext = ".eve", .kind = .eve },        .{ .ext = ".sql", .kind = .sql },        .{ .ext = ".json", .kind = .json },
    .{ .ext = ".jsonl", .kind = .json },     .{ .ext = ".xml", .kind = .xml },        .{ .ext = ".html", .kind = .html },
    .{ .ext = ".htm", .kind = .html },       .{ .ext = ".htmt", .kind = .html },      .{ .ext = ".css", .kind = .css },
    .{ .ext = ".js", .kind = .javascript },  .{ .ext = ".mjs", .kind = .javascript }, .{ .ext = ".md", .kind = .markdown },
    .{ .ext = ".markdown", .kind = .markdown }, .{ .ext = ".txt", .kind = .text },    .{ .ext = ".csv", .kind = .text },
    .{ .ext = ".cfg", .kind = .config },     .{ .ext = ".env", .kind = .config },     .{ .ext = ".png", .kind = .image },
    .{ .ext = ".jpg", .kind = .image },      .{ .ext = ".jpeg", .kind = .image },     .{ .ext = ".gif", .kind = .image },
    .{ .ext = ".bmp", .kind = .image },      .{ .ext = ".svg", .kind = .svg },        .{ .ext = ".mp3", .kind = .audio },
    .{ .ext = ".wav", .kind = .audio },      .{ .ext = ".ogg", .kind = .audio },      .{ .ext = ".flac", .kind = .audio },
    .{ .ext = ".mp4", .kind = .video },      .{ .ext = ".webm", .kind = .video },     .{ .ext = ".mov", .kind = .video },
    .{ .ext = ".mkv", .kind = .video },      .{ .ext = ".db", .kind = .database },    .{ .ext = ".sqlite", .kind = .database },
    .{ .ext = ".sqlite3", .kind = .database }, .{ .ext = ".duckdb", .kind = .database },
};

// @eve-fn kindOf
/// The kind of a file from the end of its name (case does not matter).
pub fn kindOf(name: []const u8) Kind {
    var buf: [16]u8 = undefined;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return .binary;
    const ext = name[dot..];
    if (ext.len > buf.len) return .binary;
    const low = std.ascii.lowerString(&buf, ext);
    for (table) |r| if (std.mem.eql(u8, r.ext, low)) return r.kind;
    return .binary;
}

// @eve-fn viewerOf
/// The viewer for a kind. A text kind opens in the editor; an image, SVG (as an image, with a source tab), audio, video and
/// database have their own tabs; anything else opens the card (name, size, dates, Open with the system).
pub fn viewerOf(kind: Kind) Viewer {
    return switch (kind) {
        .eve, .sql, .json, .xml, .css, .javascript, .text, .config => .editor,
        .markdown => .markdown,
        .html => .html,
        .image, .svg => .image,
        .audio, .video => .audio_video,
        .database => .database,
        .binary => .card,
    };
}

test "kinds by extension" {
    try std.testing.expectEqual(Kind.eve, kindOf("server/sales_load.eve"));
    try std.testing.expectEqual(Kind.markdown, kindOf("README.MD"));
    try std.testing.expectEqual(Kind.video, kindOf("intro.mp4"));
    try std.testing.expectEqual(Kind.binary, kindOf("Makefile"));
    try std.testing.expectEqual(Kind.binary, kindOf("archive.tar.gz"));
}

test "viewers" {
    try std.testing.expectEqual(Viewer.editor, viewerOf(kindOf("a.js")));
    try std.testing.expectEqual(Viewer.html, viewerOf(kindOf("index.html")));
    try std.testing.expectEqual(Viewer.image, viewerOf(kindOf("flow.svg")));
    try std.testing.expectEqual(Viewer.database, viewerOf(kindOf("local.db")));
    try std.testing.expectEqual(Viewer.card, viewerOf(kindOf("data.bin")));
}
