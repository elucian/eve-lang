//! @eve-module evetx.view.syntax
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/view.zig:draw
//! Colors for Eve and SQL code and the selection.
const std = @import("std");
const vaxis = @import("vaxis");
const Window = vaxis.Window;
const theme = @import("../theme.zig");
const ide = @import("ide");
const text = ide.text;
const scan = ide.scan;
const keywords = ide.keywords;
const widgets_m = @import("widgets.zig");
const put = widgets_m.put;

/// Paint the selected part of one line.
pub fn drawSelection(cw: Window, line: []const u8, shown: []const u8, row: usize, sel: text.Range, left: usize) void {
    if (row < sel.start.row or row > sel.end.row) return;
    const from = if (row == sel.start.row) sel.start.col else 0;
    const to = if (row == sel.end.row) sel.end.col else line.len;
    const style = theme.on(theme.bright, theme.sel_bg);
    const fc = text.Buffer.displayWidth(line[0..from]);
    const tc = text.Buffer.displayWidth(line[0..to]);
    const sc = @max(fc, left);
    if (sc < tc) {
        const sb = text.Buffer.byteAtDisplay(shown, sc);
        const eb = text.Buffer.byteAtDisplay(shown, tc);
        _ = put(cw, @intCast(sc - left), 0, shown[sb..eb], style);
    }
    if (row < sel.end.row) {
        const end_col = text.Buffer.displayWidth(line);
        if (end_col >= left) _ = put(cw, @intCast(end_col - left), 0, " ", style);
    }
}

/// Draw one line of text from byte `start`. Eve files get colors for comments, strings, numbers and keywords.
pub fn drawCode(w: Window, line: []const u8, start: usize, eve: bool, bg: theme.Color, carry: scan.Carry) void {
    const s = line;
    const plain = theme.on(theme.text, bg);
    if (!eve) {
        _ = put(w, 0, 0, s[start..], plain);
        return;
    }
    var col: u16 = 0;
    var sc: scan.Scan = .{ .line = s, .carry = carry };
    while (sc.next()) |t| {
        if (t.end <= start) continue;
        const from = @max(t.start, start);
        const piece = s[from..t.end];
        const style = switch (t.kind) {
            .plain => plain,
            .string => theme.on(theme.string, bg),
            .comment => if (carry == .none and s[0] == '#')
                theme.on(if (s.len > 1 and s[1] == '#') theme.subtitle else theme.title, bg)
            else
                theme.on(theme.comment, bg),
            .comment_expr => theme.on(theme.comment_expr, bg),
            .comment_block => theme.on(theme.comment_block, bg),
            .number => theme.on(theme.number, bg),
            .word => if (wordColor(piece)) |color| theme.on(color, bg) else plain,
        };
        col = put(w, col, 0, piece, style);
    }
}

pub const sql_keywords = [_][]const u8{
    "select",      "insert",     "update",    "delete",   "create",    "drop",          "alter",   "table",    "view",     "index",   "trigger",
    "into",        "values",     "set",       "as",       "distinct",  "union",         "all",     "pragma",   "begin",    "commit",  "rollback",
    "transaction", "with",       "recursive", "replace",  "explain",   "vacuum",        "analyze", "attach",   "detach",   "primary", "key",
    "foreign",     "references", "default",   "unique",   "check",     "constraint",    "add",     "column",   "rename",   "to",      "if",
    "exists",      "temp",       "temporary", "virtual",  "returning", "autoincrement", "cascade", "restrict", "conflict", "ignore",  "fail",
    "abort",       "database",   "schema",    "truncate", "grant",     "revoke",        "call",    "show",     "describe", "use",     "load",
};
pub const sql_control = [_][]const u8{
    "from",  "where",  "join",  "inner",  "left", "right", "full", "outer", "cross", "natural", "on",        "using",  "group",  "by",
    "order", "having", "limit", "offset", "case", "when",  "then", "else",  "end",   "over",    "partition", "window", "filter",
};
pub const sql_operators = [_][]const u8{ "and", "or", "not", "in", "is", "like", "glob", "between", "escape", "collate", "asc", "desc", "match", "regexp", "exists" };
pub const sql_constants = [_][]const u8{ "null", "true", "false", "current_timestamp", "current_date", "current_time" };
pub const sql_types = [_][]const u8{
    "integer", "int",     "bigint", "smallint", "tinyint",   "real", "double", "float", "numeric",  "decimal", "text", "varchar", "char",
    "blob",    "boolean", "date",   "datetime", "timestamp", "uuid", "json",   "huge",  "interval",
};

pub fn inLower(list: []const []const u8, word: []const u8) bool {
    for (list) |k| {
        if (std.mem.eql(u8, k, word)) return true;
    }
    return false;
}

/// The color of a word of SQL; null for a name (a table, a column) that keeps the plain color.
pub fn sqlWordColor(word: []const u8) ?theme.Color {
    var buf: [24]u8 = undefined;
    if (word.len > buf.len) return null;
    const low = std.ascii.lowerString(&buf, word);
    if (inLower(&sql_constants, low)) return theme.number;
    if (inLower(&sql_types, low)) return theme.type_name;
    if (inLower(&sql_operators, low)) return theme.oper;
    if (inLower(&sql_control, low)) return theme.control;
    if (inLower(&sql_keywords, low)) return theme.keyword;
    return null;
}

/// Draw one line of SQL from byte `start`, with the colors of the theme.
pub fn drawSql(w: Window, line: []const u8, start: usize, bg: theme.Color) void {
    const s = line[start..];
    const plain = theme.on(theme.text, bg);
    var col: u16 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        var j = i + 1;
        var style = plain;
        if (c == '\'') {
            while (j < s.len) : (j += 1) {
                if (s[j] == '\'') {
                    if (j + 1 < s.len and s[j + 1] == '\'') {
                        j += 1;
                        continue;
                    }
                    j += 1;
                    break;
                }
            }
            style = theme.on(theme.string, bg);
        } else if (c == '"') {
            while (j < s.len and s[j] != '"') j += 1;
            if (j < s.len) j += 1;
            style = theme.on(theme.type_name, bg);
        } else if (c == '-' and i + 1 < s.len and s[i + 1] == '-') {
            j = s.len;
            style = theme.on(theme.comment, bg);
        } else if (std.mem.startsWith(u8, s[i..], "/*")) {
            j = if (std.mem.indexOf(u8, s[i + 2 ..], "*/")) |e| i + 2 + e + 2 else s.len;
            style = theme.on(theme.comment_block, bg);
        } else if (std.ascii.isDigit(c)) {
            while (j < s.len and (std.ascii.isDigit(s[j]) or s[j] == '.')) j += 1;
            style = theme.on(theme.number, bg);
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '_')) j += 1;
            if (sqlWordColor(s[i..j])) |color| {
                style = theme.on(color, bg);
            } else if (j < s.len and s[j] == '(') {
                style = theme.on(theme.blue, bg);
            }
        } else {
            const n = std.unicode.utf8ByteSequenceLength(c) catch 1;
            j = @min(s.len, i + n);
        }
        col = put(w, col, 0, s[i..j], style);
        i = j;
    }
}

pub const interrupt_words = [_][]const u8{ "abort", "break", "exit", "panic", "raise", "resume", "retry", "skip", "stop", "yield" };
pub const control_words = [_][]const u8{ "do", "done", "else", "for", "if", "job", "loop", "match", "parallel", "repeat", "then", "when", "while" };
pub const operator_words = [_][]const u8{ "and", "as", "eq", "in", "is", "not", "or", "xor" };
pub const type_words = [_][]const u8{
    "Byte",     "Short",   "Integer", "Natural", "Huge",   "Real",     "Float",      "Decimal",   "Rational", "String",     "Logic",   "Table",
    "Rune",     "Record",  "Ordinal", "Variant", "Date",   "Time",     "Array",      "List",      "Object",   "Class",      "Lambda",  "Function",
    "DataSet",  "DataMap", "Folder",  "File",    "Null",   "True",     "False",      "Type",
    // the types and traits added by levels 3 to 6 (spec/semantics/types.md, spec/library/)
         "Text",     "Symbol",     "HashMap", "Instant",
    "Duration", "Secret",  "Channel", "Memory",  "Stream", "Iterable", "Comparable", "Printable", "Bytes",    "Connection", "Atomic",  "Error",
    "Warning",
};

pub fn inList(list: []const []const u8, word: []const u8) bool {
    for (list) |k| {
        if (std.mem.eql(u8, k, word)) return true;
    }
    return false;
}

/// The color of a word: type, interruption, control word, operator word or keyword (`null` for none).
pub fn wordColor(word: []const u8) ?theme.Color {
    if (inList(&type_words, word)) return theme.type_name;
    if (inList(&interrupt_words, word)) return theme.interrupt;
    if (inList(&control_words, word)) return theme.control;
    if (inList(&operator_words, word)) return theme.oper;
    if (inList(&keywords.words, word)) return theme.keyword;
    return null;
}

// @test the words of the aspect kinds, export and the newer types have a color (keywords.zig is generated from the spec)
test "wordColor knows primary, export, print and the newer types" {
    for ([_][]const u8{ "primary", "exclusive", "concurrent", "aspect", "export", "external", "recover", "print", "write", "Instant", "Secret", "Stream" }) |w| {
        try std.testing.expect(wordColor(w) != null);
    }
    try std.testing.expect(wordColor("banana") == null);
}
