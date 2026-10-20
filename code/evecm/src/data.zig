//! The plain parts of the data language (spec/library/data-language.md, database.md): the CSV
//! reader, the connection lines of `eve.cfg` and the JSON text writer. They work on bytes and
//! slices only; the interpreter (interp.zig) turns the results into Eve values.
const std = @import("std");
const Io = std.Io;

/// One CSV field. A field that was quoted is a text even when empty; an unquoted empty field is
/// a `null` (spec/semantics/data-types.md, reading a unit).
pub const Field = struct {
    text: []const u8,
    quoted: bool,
};

pub const CsvError = error{ UnterminatedQuote, OutOfMemory };

/// One CSV line: the line of the file where it starts (the first line is 1) and its fields.
pub const Row = struct {
    line: usize,
    fields: []const Field,
};

/// Parse CSV text: fields separated by `sep` (a comma by default), a field in double quotes may hold the
/// separator, line breaks and `""` for one quote; rows end with LF or CRLF. An empty line is not a row.
pub fn parseCsv(a: std.mem.Allocator, text: []const u8, sep: u8) CsvError![]const Row {
    var rows: std.ArrayList(Row) = .empty;
    var row: std.ArrayList(Field) = .empty;
    var i: usize = 0;
    var line: usize = 1;
    var row_line: usize = 1;
    while (i < text.len) {
        // one field
        var buf: std.ArrayList(u8) = .empty;
        var quoted = false;
        if (text[i] == '"') {
            quoted = true;
            i += 1;
            while (true) {
                if (i >= text.len) return error.UnterminatedQuote;
                if (text[i] == '"') {
                    if (i + 1 < text.len and text[i + 1] == '"') {
                        try buf.append(a, '"');
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                if (text[i] == '\n') line += 1;
                try buf.append(a, text[i]);
                i += 1;
            }
        } else {
            while (i < text.len and text[i] != sep and text[i] != '\n' and text[i] != '\r') : (i += 1) try buf.append(a, text[i]);
        }
        try row.append(a, .{ .text = buf.items, .quoted = quoted });
        // what ends the field
        if (i < text.len and text[i] == sep) {
            i += 1;
            if (i >= text.len) try row.append(a, .{ .text = "", .quoted = false }); // a separator at the very end
            continue;
        }
        if (i < text.len and text[i] == '\r') i += 1;
        if (i < text.len and text[i] == '\n') {
            i += 1;
            line += 1;
        }
        const blank = row.items.len == 1 and !row.items[0].quoted and row.items[0].text.len == 0;
        if (!blank) try rows.append(a, .{ .line = row_line, .fields = row.items });
        row = .empty;
        row_line = line;
    }
    if (row.items.len > 0) try rows.append(a, .{ .line = row_line, .fields = row.items });
    return rows.items;
}

/// The URL of the connection `name` in the text of `eve.cfg`: the line `database "name" = "url"`.
/// Lines that start with `#` or `**` are comments. Null when the name is not declared.
pub fn connectionUrl(cfg: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, cfg, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (!std.mem.startsWith(u8, line, "database")) continue;
        line = std.mem.trimStart(u8, line["database".len..], " \t");
        const n = quotedText(&line) orelse continue;
        line = std.mem.trimStart(u8, line, " \t");
        if (line.len == 0 or line[0] != '=') continue; // `database "x" schema_version = ...` is another setting
        line = std.mem.trimStart(u8, line[1..], " \t");
        const url = quotedText(&line) orelse continue;
        if (std.mem.eql(u8, n, name)) return url;
    }
    return null;
}

/// Reads `"text"` at the start of `rest` and moves `rest` after it; null when there is no quote.
fn quotedText(rest: *[]const u8) ?[]const u8 {
    if (rest.len == 0 or rest.*[0] != '"') return null;
    const end = std.mem.indexOfScalarPos(u8, rest.*, 1, '"') orelse return null;
    const inner = rest.*[1..end];
    rest.* = rest.*[end + 1 ..];
    return inner;
}

/// The path of a `sqlite://path` URL; null for another scheme.
pub fn sqlitePath(url: []const u8) ?[]const u8 {
    const prefix = "sqlite://";
    if (!std.mem.startsWith(u8, url, prefix)) return null;
    return url[prefix.len..];
}

/// Writes `s` as a JSON string, with the quotes.
pub fn writeJsonString(w: *Io.Writer, s: []const u8) Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |ch| switch (ch) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0...8, 11, 12, 14...31 => try w.print("\\u{x:0>4}", .{ch}),
        else => try w.writeByte(ch),
    };
    try w.writeByte('"');
}

/// A JSON value. Numbers keep their text, so `12.50` is not turned into a float and does not lose its scale.
pub const Json = union(enum) {
    null,
    boolean: bool,
    number: []const u8,
    string: []const u8,
    array: []const Json,
    object: []const Member,
};

/// One key and value of a JSON object, in the order of the text.
pub const Member = struct {
    key: []const u8,
    value: Json,
};

/// Where and why a JSON text is not well formed.
pub const JsonDiag = struct {
    line: usize = 1,
    column: usize = 1,
    reason: []const u8 = "",
};

pub const JsonError = error{ BadJson, OutOfMemory };

const JsonParser = struct {
    a: std.mem.Allocator,
    text: []const u8,
    i: usize = 0,
    diag: *JsonDiag,

    fn fail(p: *JsonParser, reason: []const u8) JsonError {
        var line: usize = 1;
        var col: usize = 1;
        for (p.text[0..@min(p.i, p.text.len)]) |ch| {
            if (ch == '\n') {
                line += 1;
                col = 1;
            } else col += 1;
        }
        p.diag.* = .{ .line = line, .column = col, .reason = reason };
        return error.BadJson;
    }

    fn skip(p: *JsonParser) void {
        while (p.i < p.text.len and (p.text[p.i] == ' ' or p.text[p.i] == '\t' or p.text[p.i] == '\n' or p.text[p.i] == '\r')) p.i += 1;
    }

    fn value(p: *JsonParser) JsonError!Json {
        p.skip();
        if (p.i >= p.text.len) return p.fail("the text ends where a value is expected");
        switch (p.text[p.i]) {
            '{' => return p.object(),
            '[' => return p.array(),
            '"' => return .{ .string = try p.string() },
            't' => return p.word("true", .{ .boolean = true }),
            'f' => return p.word("false", .{ .boolean = false }),
            'n' => return p.word("null", .null),
            else => return p.number(),
        }
    }

    fn word(p: *JsonParser, w: []const u8, v: Json) JsonError!Json {
        if (!std.mem.startsWith(u8, p.text[p.i..], w)) return p.fail("not a JSON value");
        p.i += w.len;
        return v;
    }

    fn number(p: *JsonParser) JsonError!Json {
        const start = p.i;
        if (p.i < p.text.len and p.text[p.i] == '-') p.i += 1;
        const digits_from = p.i;
        while (p.i < p.text.len and std.ascii.isDigit(p.text[p.i])) p.i += 1;
        if (p.i == digits_from) {
            p.i = start;
            return p.fail("not a JSON value");
        }
        if (p.i < p.text.len and p.text[p.i] == '.') {
            p.i += 1;
            while (p.i < p.text.len and std.ascii.isDigit(p.text[p.i])) p.i += 1;
        }
        if (p.i < p.text.len and (p.text[p.i] == 'e' or p.text[p.i] == 'E')) {
            p.i += 1;
            if (p.i < p.text.len and (p.text[p.i] == '+' or p.text[p.i] == '-')) p.i += 1;
            while (p.i < p.text.len and std.ascii.isDigit(p.text[p.i])) p.i += 1;
        }
        return .{ .number = p.text[start..p.i] };
    }

    fn hex4(p: *JsonParser) JsonError!u21 {
        if (p.i + 4 > p.text.len) return p.fail("a \\u escape needs four hexadecimal digits");
        const v = std.fmt.parseInt(u21, p.text[p.i .. p.i + 4], 16) catch return p.fail("a \\u escape needs four hexadecimal digits");
        p.i += 4;
        return v;
    }

    fn string(p: *JsonParser) JsonError![]const u8 {
        p.i += 1; // the opening quote
        var out: std.ArrayList(u8) = .empty;
        while (true) {
            if (p.i >= p.text.len) return p.fail("a string is not closed");
            const ch = p.text[p.i];
            if (ch == '"') {
                p.i += 1;
                return out.items;
            }
            if (ch != '\\') {
                try out.append(p.a, ch);
                p.i += 1;
                continue;
            }
            p.i += 1;
            if (p.i >= p.text.len) return p.fail("a string is not closed");
            const esc = p.text[p.i];
            p.i += 1;
            switch (esc) {
                '"', '\\', '/' => try out.append(p.a, esc),
                'b' => try out.append(p.a, 8),
                'f' => try out.append(p.a, 12),
                'n' => try out.append(p.a, '\n'),
                'r' => try out.append(p.a, '\r'),
                't' => try out.append(p.a, '\t'),
                'u' => {
                    var cp = try p.hex4();
                    if (cp >= 0xD800 and cp < 0xDC00) {
                        // a high surrogate must be followed by \uDC00..\uDFFF
                        if (!std.mem.startsWith(u8, p.text[p.i..], "\\u")) return p.fail("a high surrogate needs a low surrogate");
                        p.i += 2;
                        const low = try p.hex4();
                        if (low < 0xDC00 or low > 0xDFFF) return p.fail("a high surrogate needs a low surrogate");
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                    }
                    var buf: [4]u8 = undefined;
                    const n = std.unicode.utf8Encode(cp, &buf) catch return p.fail("not a valid code point");
                    try out.appendSlice(p.a, buf[0..n]);
                },
                else => return p.fail("unknown escape in a string"),
            }
        }
    }

    fn array(p: *JsonParser) JsonError!Json {
        p.i += 1;
        var items: std.ArrayList(Json) = .empty;
        p.skip();
        if (p.i < p.text.len and p.text[p.i] == ']') {
            p.i += 1;
            return .{ .array = items.items };
        }
        while (true) {
            try items.append(p.a, try p.value());
            p.skip();
            if (p.i >= p.text.len) return p.fail("an array is not closed");
            if (p.text[p.i] == ',') {
                p.i += 1;
                continue;
            }
            if (p.text[p.i] == ']') {
                p.i += 1;
                return .{ .array = items.items };
            }
            return p.fail("expected ',' or ']' in an array");
        }
    }

    fn object(p: *JsonParser) JsonError!Json {
        p.i += 1;
        var members: std.ArrayList(Member) = .empty;
        p.skip();
        if (p.i < p.text.len and p.text[p.i] == '}') {
            p.i += 1;
            return .{ .object = members.items };
        }
        while (true) {
            p.skip();
            if (p.i >= p.text.len or p.text[p.i] != '"') return p.fail("a key of an object is a string");
            const key = try p.string();
            p.skip();
            if (p.i >= p.text.len or p.text[p.i] != ':') return p.fail("expected ':' after a key");
            p.i += 1;
            try members.append(p.a, .{ .key = key, .value = try p.value() });
            p.skip();
            if (p.i >= p.text.len) return p.fail("an object is not closed");
            if (p.text[p.i] == ',') {
                p.i += 1;
                continue;
            }
            if (p.text[p.i] == '}') {
                p.i += 1;
                return .{ .object = members.items };
            }
            return p.fail("expected ',' or '}' in an object");
        }
    }
};

// @eve-impl one JSON value of a text in memory (json.parse): unlike parseJsonDocuments a top-level array stays one value
// @spec spec/library/data-language.md#json-text-in-memory-jsonparse-and-jsontext
// @feature F-LIB-05
/// The JSON value of `text`; text after the value is an error.
pub fn parseJson(a: std.mem.Allocator, text: []const u8, diag: *JsonDiag) JsonError!Json {
    var p: JsonParser = .{ .a = a, .text = text, .diag = diag };
    const v = try p.value();
    p.skip();
    if (p.i < text.len) return p.fail("text after the end of the value");
    return v;
}

/// The documents of a JSON file: the items of one top-level array, or every value of a JSON Lines text.
pub fn parseJsonDocuments(a: std.mem.Allocator, text: []const u8, diag: *JsonDiag) JsonError![]const Json {
    var p: JsonParser = .{ .a = a, .text = text, .diag = diag };
    var out: std.ArrayList(Json) = .empty;
    p.skip();
    if (p.i < text.len and text[p.i] == '[') {
        const arr = try p.value();
        p.skip();
        if (p.i < text.len) return p.fail("text after the end of the array");
        return arr.array;
    }
    while (true) {
        p.skip();
        if (p.i >= text.len) break;
        try out.append(a, try p.value());
    }
    return out.items;
}

test "the CSV reader keeps quotes, commas, empty and quoted-empty fields apart" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const rows = try parseCsv(arena.allocator(), "id,name,note\r\n1,\"Smith, \"\"Bob\"\"\",\n2,Ann,\"\"\n3,x,y", ',');
    try std.testing.expectEqual(@as(usize, 4), rows.len);
    try std.testing.expectEqualStrings("Smith, \"Bob\"", rows[1].fields[1].text);
    try std.testing.expect(rows[1].fields[1].quoted);
    try std.testing.expectEqual(@as(usize, 3), rows[1].fields.len);
    try std.testing.expect(!rows[1].fields[2].quoted and rows[1].fields[2].text.len == 0); // null
    try std.testing.expect(rows[2].fields[2].quoted and rows[2].fields[2].text.len == 0); // the empty string
    try std.testing.expectEqualStrings("y", rows[3].fields[2].text); // no line break at the end
    try std.testing.expectEqual(@as(usize, 4), rows[3].line);
    try std.testing.expectError(error.UnterminatedQuote, parseCsv(arena.allocator(), "a,\"b", ','));
    const semi = try parseCsv(arena.allocator(), "a;b\n1;2\n", ';');
    try std.testing.expectEqualStrings("2", semi[1].fields[1].text);
}

test "the connection of a name is found in eve.cfg" {
    const cfg = "# comment\ndatabase \"shop\" = \"sqlite://db/shop.db\"\ndatabase \"shop\" schema_version = \"select 1\"\n" ++
        "database \"cache\"  =  \"sqlite://db/cache.db\" exclusive\n";
    try std.testing.expectEqualStrings("sqlite://db/cache.db", connectionUrl(cfg, "cache").?);
    try std.testing.expectEqualStrings("sqlite://db/shop.db", connectionUrl(cfg, "shop").?);
    try std.testing.expect(connectionUrl(cfg, "nope") == null);
    try std.testing.expectEqualStrings("db/cache.db", sqlitePath("sqlite://db/cache.db").?);
    try std.testing.expect(sqlitePath("postgresql://h/db") == null);
}

test "a JSON string escapes quotes, backslashes and control characters" {
    var buf: Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try writeJsonString(&buf.writer, "a\"b\\c\n\x01é");
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\n\\u0001é\"", buf.written());
}

test "the JSON reader reads an array and JSON Lines, keeps number text and unescapes strings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: JsonDiag = .{};
    const docs = try parseJsonDocuments(arena.allocator(), "{\"id\":1,\"p\":12.50,\"n\":null,\"s\":\"a\\\"b\\u00e9\"}\n{\"id\":2}\n", &diag);
    try std.testing.expectEqual(@as(usize, 2), docs.len);
    try std.testing.expectEqualStrings("12.50", docs[0].object[1].value.number);
    try std.testing.expect(docs[0].object[2].value == .null);
    try std.testing.expectEqualStrings("a\"b\u{00e9}", docs[0].object[3].value.string);
    const arr = try parseJsonDocuments(arena.allocator(), " [ {\"id\": 1}, {\"id\": 2} ] ", &diag);
    try std.testing.expectEqual(@as(usize, 2), arr.len);
    try std.testing.expectError(error.BadJson, parseJsonDocuments(arena.allocator(), "{\"id\": }", &diag));
    try std.testing.expectEqual(@as(usize, 1), diag.line);
}
