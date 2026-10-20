//! @eve-module parser.consts
//! @spec spec/syntax/grammar.md
//! @feature F-VM-01
//! @decision D-179
//! @see code/evecp/src/parser.zig:Parser
//! Reserved words, the block end words and the number helper the parser parts share.
const std = @import("std");
const lexer = @import("../lexer.zig");
const ast = @import("evecm").ast;
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
