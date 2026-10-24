//! @eve-module parser.consts
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Reserved words, the block end words and the number helper the parser parts share.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
const rational = @import("evecm").rational;
const checker = @import("../check.zig");
const Token = lexer.Token;
const Node = ast.Node;
const Tag = ast.Tag;
const Diag = lexer.Diag;
const Error = lexer.Error;

pub const reserved = std.StaticStringMap(void).initComptime(.{
    .{"primary"}, .{"is"},        .{"process"},  .{"return"}, .{"end"},       .{"new"},        .{"set"},
    .{"let"},     .{"if"},        .{"else"},     .{"do"},     .{"done"},      .{"while"},      .{"loop"},
    .{"for"},     .{"in"},        .{"match"},    .{"when"},   .{"then"},      .{"break"},      .{"skip"},
    .{"raise"},   .{"recover"},   .{"finalize"}, .{"job"},    .{"retry"},     .{"resume"},     .{"abort"},
    .{"over"},    .{"exit"},      .{"stop"},     .{"pass"},   .{"panic"},     .{"print"},      .{"write"},
    .{"expect"},  .{"assert"},    .{"defer"},    .{"class"},  .{"function"},  .{"procedure"},  .{"constructor"},
    .{"public"},  .{"protected"}, .{"private"},  .{"and"},    .{"or"},        .{"xor"},        .{"not"},
    .{"repeat"},  .{"eq"},        .{"apply"},    .{"aspect"}, .{"exclusive"}, .{"concurrent"}, .{"parallel"},
    .{"start"},   .{"spawn"},     .{"await"},    .{"wait"},   .{"trait"},
});

// @eve-impl a plain number literal is converted once, by the parser (R1 of design/design-bytecode.md)
// @invariant the same value as `number` in code/evevm/src/interp/expr.zig gives for a text of digits (no comma, no suffix, no leading zero)
pub fn plainNumber(n: *Node, text: []const u8) void {
    // a duration literal `30s`, `250ms`: microseconds, once (spec/library/time.md#literals)
    if (text.len > 1 and std.ascii.isDigit(text[0]) and std.ascii.isAlphabetic(text[text.len - 1])) {
        if (@import("evecm").duration.parseLiteral(text)) |us| {
            n.lit_kind = .dur;
            n.lit_bits = @bitCast(us);
        }
        return;
    }
    // an imaginary literal `i99`: the bits of the f64 (spec/semantics/types.md#complex)
    if (text.len > 1 and text[0] == 'i') {
        n.lit_kind = .imag;
        n.lit_bits = @bitCast(std.fmt.parseFloat(f64, text[1..]) catch return);
        return;
    }
    // a Rational literal `3\4` of small numbers: reduced here, once (spec/semantics/types.md#rational)
    if (std.mem.indexOfScalar(u8, text, '\\')) |cut| {
        if (cut == 0 or cut > 9 or text.len - cut - 1 == 0 or text.len - cut - 1 > 9) return;
        const num = std.fmt.parseInt(u32, text[0..cut], 10) catch return;
        const den = std.fmt.parseInt(u32, text[cut + 1 ..], 10) catch return;
        if (den == 0 or num > std.math.maxInt(i32) or den > std.math.maxInt(i32)) return;
        const q = rational.make(num, den) orelse return;
        n.lit_kind = .rat;
        n.lit_bits = ast.packRat(@intCast(q.n), @intCast(q.d));
        return;
    }
    if (text.len == 0 or text.len > 18 or (text.len > 1 and text[0] == '0' and text[1] != '.')) return;
    var dots: usize = 0;
    for (text) |c| {
        if (c == '.') {
            dots += 1;
        } else if (c < '0' or c > '9') return;
    }
    if (dots == 0) {
        n.lit_kind = .int;
        n.lit_bits = @bitCast(std.fmt.parseInt(i64, text, 10) catch return);
    } else if (dots == 1 and text[0] != '.' and text[text.len - 1] != '.') {
        n.lit_kind = .real;
        n.lit_bits = @bitCast(std.fmt.parseFloat(f64, text) catch return);
    }
}

/// Words that end a block: a statement list stops in front of them.
pub const block_end = std.StaticStringMap(void).initComptime(.{
    .{"return"}, .{"recover"}, .{"finalize"}, .{"done"}, .{"else"}, .{"then"}, .{"when"}, .{"end"}, .{"repeat"},
});
