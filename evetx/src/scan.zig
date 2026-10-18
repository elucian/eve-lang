//! @eve-module scan: the scanner of Eve source lines for syntax colors (shared by evetx and eveux)
//! @spec spec/lexical/lexical.md#comments
//! @feature F-TLS-24
//! @decision D-190
//! @tests evetx: `zig build test` in evetx/
//! No dependency on a screen library: the tokens of a line, and the state of `/* */` and `(** **)` comments between lines.
const std = @import("std");
const text = @import("text.zig");

// @eve-impl syntax colors of an Eve line for the editor; the scan always starts at byte 0 of the line (and in the state
// `carry` left by the lines above), then the part from `start` on is drawn. So a wrapped piece or a line scrolled to the
// right keeps the color of the string or comment it is inside, and `/* ... */` and `(** ... **)` may span lines.
// @feature F-TLS-24
// @invariant the same scanner (`Scan`) gives the colors and the state at the end of a line; they can not disagree
// @see evetx/src/view.zig:editor and drawCode (computes `carry` for the first visible line and passes it on line by line)

/// Where a line begins: in no comment, inside `/* ... */`, or inside `(** ... **)` opened on an earlier line.
pub const Carry = enum { none, block, expr };

pub const TokenKind = enum { plain, string, comment, comment_expr, comment_block, number, word };

pub const Token = struct { start: usize, end: usize, kind: TokenKind };

/// One scan of an Eve line: `next` gives the tokens in order and keeps the carry for the next line in `carry`.
pub const Scan = struct {
    line: []const u8,
    i: usize = 0,
    carry: Carry,

    pub fn next(self: *Scan) ?Token {
        const s = self.line;
        const i = self.i;
        if (i >= s.len) return null;
        var j = i + 1;
        var kind: TokenKind = .plain;
        if (self.carry != .none) {
            // inside a comment of an earlier line: it goes on to its closing mark, or to the end of this line
            const was = self.carry;
            const close = if (was == .block) "*/" else "**)";
            if (std.mem.indexOf(u8, s[i..], close)) |e| {
                j = i + e + close.len;
                self.carry = .none;
            } else j = s.len;
            kind = if (was == .block) .comment_block else .comment_expr;
        } else if (i == 0 and s[0] == '#') {
            j = s.len;
            kind = .comment; // the caller colors a `#` line as a title
        } else if (s[i] == '"') {
            while (j < s.len and s[j] != '"') j += 1;
            if (j < s.len) j += 1;
            kind = .string;
        } else if (s[i] == '*' and i + 1 < s.len and s[i + 1] == '*') {
            j = s.len;
            kind = .comment;
        } else if (std.mem.startsWith(u8, s[i..], "(**")) {
            if (std.mem.indexOf(u8, s[i + 3 ..], "**)")) |e| {
                j = i + 3 + e + 3;
            } else {
                j = s.len;
                self.carry = .expr;
            }
            kind = .comment_expr;
        } else if (std.mem.startsWith(u8, s[i..], "/*")) {
            if (std.mem.indexOf(u8, s[i + 2 ..], "*/")) |e| {
                j = i + 2 + e + 2;
            } else {
                j = s.len;
                self.carry = .block;
            }
            kind = .comment_block;
        } else if (std.ascii.isDigit(s[i])) {
            while (j < s.len and (std.ascii.isDigit(s[j]) or s[j] == '.' or s[j] == '_')) j += 1;
            kind = .number;
        } else if (std.ascii.isAlphabetic(s[i]) or s[i] == '_') {
            while (j < s.len and (std.ascii.isAlphanumeric(s[j]) or s[j] == '_')) j += 1;
            kind = .word;
        } else {
            // a character that is not a word: one UTF-8 character at a time
            const n = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
            j = @min(s.len, i + n);
        }
        self.i = j;
        return .{ .start = i, .end = j, .kind = kind };
    }
};

/// The state at the end of an Eve line that begins in `carry`.
pub fn carryAfter(line: []const u8, carry: Carry) Carry {
    var sc: Scan = .{ .line = line, .carry = carry };
    while (sc.next()) |_| {}
    return sc.carry;
}

/// The state at the start of line `row`: the lines above it are scanned (a comment may begin far above).
pub fn carryAt(b: *text.Buffer, row: usize) Carry {
    var carry: Carry = .none;
    var r: usize = 0;
    while (r < row) : (r += 1) carry = carryAfter(b.lineAt(r), carry);
    return carry;
}

// @test syntax colors of Eve comments: state across lines, and a piece that starts inside a comment
test "carry of block and expression comments across lines" {
    try std.testing.expectEqual(Carry.block, carryAfter("x /* start", .none));
    try std.testing.expectEqual(Carry.block, carryAfter("still inside", .block));
    try std.testing.expectEqual(Carry.none, carryAfter("end */ code", .block));
    try std.testing.expectEqual(Carry.expr, carryAfter("a (** note", .none));
    try std.testing.expectEqual(Carry.none, carryAfter("done **) b", .expr));
    try std.testing.expectEqual(Carry.none, carryAfter("a ** comment /* not a block", .none));
    try std.testing.expectEqual(Carry.none, carryAfter("print \"/* in a string\";", .none));
    try std.testing.expectEqual(Carry.none, carryAfter("# title /* not a block", .none));
}

test "a line inside a block comment is one comment token" {
    var sc: Scan = .{ .line = "# not a title, new x := 1;", .carry = .block };
    const t = sc.next().?;
    try std.testing.expectEqual(TokenKind.comment_block, t.kind);
    try std.testing.expectEqual(@as(usize, 26), t.end);
    try std.testing.expect(sc.next() == null);
    try std.testing.expectEqual(Carry.block, sc.carry);
}

test "tokens of a line after a closed comment" {
    var sc: Scan = .{ .line = "*/ new x", .carry = .block };
    try std.testing.expectEqual(TokenKind.comment_block, sc.next().?.kind);
    try std.testing.expectEqual(TokenKind.plain, sc.next().?.kind);
    try std.testing.expectEqual(TokenKind.word, sc.next().?.kind);
}
