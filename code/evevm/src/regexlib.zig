//! @eve-module regexlib: regular expressions of the RE2 family (linear time) for the module `regex`
//! @spec spec/library/text.md#module-regex
//! @feature F-LIB-03
//! @decision D-236
//! @tests test/level3/c83_text_regex
//! A pattern is compiled to a small program and run by a backtracking machine that remembers the states (pc, position) it has seen, so the time is at most the length of the text times the size of the program: no pattern can take exponential time. The text is UTF-8; `.` and a class match a whole code point. `\d`, `\w` and `\s` are ASCII, as in RE2.
const std = @import("std");

pub const Error = error{ OutOfMemory, BadPattern, TooCostly };

const Op = enum { char, any, class, split, jmp, save, bol, eol, bot, eot, word, nonword, match };

const Inst = struct { op: Op, x: u32 = 0, y: u32 = 0 };

const Range = struct { lo: u21, hi: u21 };

const Class = struct { ranges: []const Range, negated: bool };

pub const Flags = struct { icase: bool = false, multiline: bool = false, dotall: bool = false };

pub const Prog = struct {
    insts: []const Inst,
    classes: []const Class,
    /// The number of capture groups, group 0 (the whole match) not counted.
    groups: usize,
    flags: Flags,
    /// Where a bad pattern went wrong (byte offset) and why.
    pub var err_at: usize = 0;
    pub var err_why: []const u8 = "";
};

const max_program = 40000;
const max_repeat = 1000;
/// The memory of the seen states, in bits: a text and a pattern whose product is larger are refused.
const max_visited_bits: usize = 256 * 1024 * 1024;

// ---- the syntax tree --------------------------------------------------------------------------

const Node = union(enum) {
    empty,
    lit: u21,
    any,
    class: u32,
    cat: []const *const Node,
    alt: []const *const Node,
    rep: struct { child: *const Node, min: u32, max: ?u32, greedy: bool },
    group: struct { child: *const Node, index: ?u32 },
    bol,
    eol,
    /// The start and the end of the whole text (`bol` and `eol` also stand at a line end with the flag m).
    bot,
    eot,
    word,
    nonword,
};

const Parser = struct {
    a: std.mem.Allocator,
    src: []const u8,
    at: usize = 0,
    groups: u32 = 0,
    classes: std.ArrayList(Class) = .empty,
    flags: Flags = .{},

    fn fail(p: *Parser, why: []const u8) Error {
        Prog.err_at = p.at;
        Prog.err_why = why;
        return error.BadPattern;
    }

    fn peek(p: *Parser) ?u8 {
        return if (p.at < p.src.len) p.src[p.at] else null;
    }

    fn node(p: *Parser, n: Node) Error!*const Node {
        const ptr = try p.a.create(Node);
        ptr.* = n;
        return ptr;
    }

    /// The code point at the cursor, and the cursor moved after it.
    fn rune(p: *Parser) Error!u21 {
        const len = std.unicode.utf8ByteSequenceLength(p.src[p.at]) catch return p.fail("the pattern is not valid UTF-8");
        if (p.at + len > p.src.len) return p.fail("the pattern is not valid UTF-8");
        const cp = std.unicode.utf8Decode(p.src[p.at..][0..len]) catch return p.fail("the pattern is not valid UTF-8");
        p.at += len;
        return cp;
    }

    fn parseAlt(p: *Parser) Error!*const Node {
        var branches: std.ArrayList(*const Node) = .empty;
        try branches.append(p.a, try p.parseCat());
        while (p.peek() == '|') {
            p.at += 1;
            try branches.append(p.a, try p.parseCat());
        }
        if (branches.items.len == 1) return branches.items[0];
        return p.node(.{ .alt = try branches.toOwnedSlice(p.a) });
    }

    fn parseCat(p: *Parser) Error!*const Node {
        var items: std.ArrayList(*const Node) = .empty;
        while (p.peek()) |c| {
            if (c == '|' or c == ')') break;
            try items.append(p.a, try p.parseRepeat());
        }
        if (items.items.len == 0) return p.node(.empty);
        if (items.items.len == 1) return items.items[0];
        return p.node(.{ .cat = try items.toOwnedSlice(p.a) });
    }

    fn parseRepeat(p: *Parser) Error!*const Node {
        var atom = try p.parseAtom();
        while (p.peek()) |c| {
            var min: u32 = 0;
            var max: ?u32 = null;
            switch (c) {
                '*' => p.at += 1,
                '+' => {
                    min = 1;
                    p.at += 1;
                },
                '?' => {
                    max = 1;
                    p.at += 1;
                },
                '{' => {
                    const save = p.at;
                    p.at += 1;
                    const lo = p.number() orelse {
                        p.at = save;
                        break;
                    };
                    min = lo;
                    max = lo;
                    if (p.peek() == ',') {
                        p.at += 1;
                        max = p.number();
                    }
                    if (p.peek() != '}') {
                        p.at = save;
                        break;
                    }
                    p.at += 1;
                    if (min > max_repeat or (max != null and (max.? > max_repeat or max.? < min))) return p.fail("a repeat count is at most 1000 and the first number is not above the second");
                },
                else => break,
            }
            var greedy = true;
            if (p.peek() == '?') {
                greedy = false;
                p.at += 1;
            }
            atom = try p.node(.{ .rep = .{ .child = atom, .min = min, .max = max, .greedy = greedy } });
        }
        return atom;
    }

    fn number(p: *Parser) ?u32 {
        const start = p.at;
        var n: u32 = 0;
        while (p.peek()) |c| : (p.at += 1) {
            if (c < '0' or c > '9') break;
            n = n *| 10 +| (c - '0');
        }
        return if (p.at == start) null else n;
    }

    fn parseAtom(p: *Parser) Error!*const Node {
        const c = p.src[p.at];
        switch (c) {
            '(' => {
                p.at += 1;
                var index: ?u32 = null;
                if (p.peek() == '?') {
                    p.at += 1;
                    const k = p.peek() orelse return p.fail("a group is not complete");
                    if (k == ':') {
                        p.at += 1;
                    } else if (k == 'P' or k == '<') {
                        // a named group: the name is read and dropped, the group is numbered
                        if (k == 'P') p.at += 1;
                        if (p.peek() != '<') return p.fail("a group name is written (?P<name>...)");
                        while (p.peek() != null and p.peek() != '>') p.at += 1;
                        if (p.peek() == null) return p.fail("a group name is not closed");
                        p.at += 1;
                        p.groups += 1;
                        index = p.groups;
                    } else return p.fail("this kind of group is not supported");
                } else {
                    p.groups += 1;
                    index = p.groups;
                }
                const inner = try p.parseAlt();
                if (p.peek() != ')') return p.fail("a group is not closed");
                p.at += 1;
                return p.node(.{ .group = .{ .child = inner, .index = index } });
            },
            '[' => return p.parseClass(),
            '.' => {
                p.at += 1;
                return p.node(.any);
            },
            '^' => {
                p.at += 1;
                return p.node(.bol);
            },
            '$' => {
                p.at += 1;
                return p.node(.eol);
            },
            '*', '+', '?' => return p.fail("a repeat has nothing before it"),
            '\\' => return p.parseEscape(),
            else => return p.node(.{ .lit = try p.rune() }),
        }
    }

    fn classNode(p: *Parser, ranges: []const Range, negated: bool) Error!*const Node {
        try p.classes.append(p.a, .{ .ranges = ranges, .negated = negated });
        return p.node(.{ .class = @intCast(p.classes.items.len - 1) });
    }

    /// The ranges of `\d`, `\w`, `\s` (lower case letter) written for the letter `k`.
    fn perl(k: u8) ?[]const Range {
        return switch (k) {
            'd' => &.{.{ .lo = '0', .hi = '9' }},
            'w' => &.{ .{ .lo = '0', .hi = '9' }, .{ .lo = 'A', .hi = 'Z' }, .{ .lo = '_', .hi = '_' }, .{ .lo = 'a', .hi = 'z' } },
            's' => &.{ .{ .lo = '\t', .hi = '\r' }, .{ .lo = ' ', .hi = ' ' } },
            else => null,
        };
    }

    fn parseEscape(p: *Parser) Error!*const Node {
        p.at += 1;
        const k = p.peek() orelse return p.fail("a backslash ends the pattern");
        if (perl(std.ascii.toLower(k))) |ranges| {
            p.at += 1;
            return p.classNode(ranges, std.ascii.isUpper(k));
        }
        if (k == 'b') {
            p.at += 1;
            return p.node(.word);
        }
        if (k == 'B') {
            p.at += 1;
            return p.node(.nonword);
        }
        return p.node(.{ .lit = try p.escapedRune() });
    }

    /// The code point of an escape that stands for one: `\n`, `\t`, `\xHH`, `\x{H...}` or a punctuation mark.
    fn escapedRune(p: *Parser) Error!u21 {
        const k = p.src[p.at];
        p.at += 1;
        switch (k) {
            'n' => return '\n',
            't' => return '\t',
            'r' => return '\r',
            'f' => return 0x0c,
            'v' => return 0x0b,
            'x' => {
                var digits: usize = 0;
                var v: u32 = 0;
                const braced = p.peek() == '{';
                if (braced) p.at += 1;
                while (p.peek()) |c| {
                    const d = std.fmt.charToDigit(c, 16) catch break;
                    v = v * 16 + d;
                    p.at += 1;
                    digits += 1;
                    if (!braced and digits == 2) break;
                    if (v > 0x10FFFF) return p.fail("a code point is at most 10FFFF");
                }
                if (braced) {
                    if (p.peek() != '}') return p.fail("\\x{...} is not closed");
                    p.at += 1;
                }
                if (digits == 0) return p.fail("\\x needs hexadecimal digits");
                return @intCast(v);
            },
            else => {
                if (std.ascii.isAlphanumeric(k)) return p.fail("this escape is not known");
                p.at -= 1;
                return p.rune();
            },
        }
    }

    fn parseClass(p: *Parser) Error!*const Node {
        p.at += 1;
        var negated = false;
        if (p.peek() == '^') {
            negated = true;
            p.at += 1;
        }
        var ranges: std.ArrayList(Range) = .empty;
        var first = true;
        while (true) {
            const c = p.peek() orelse return p.fail("a class is not closed");
            if (c == ']' and !first) {
                p.at += 1;
                break;
            }
            first = false;
            var lo: u21 = undefined;
            if (c == '\\') {
                p.at += 1;
                const k = p.peek() orelse return p.fail("a backslash ends the pattern");
                if (perl(std.ascii.toLower(k))) |rs| {
                    p.at += 1;
                    if (std.ascii.isUpper(k)) {
                        // the complement of a Perl class inside a class: the ranges between its ranges
                        var from: u21 = 0;
                        for (rs) |r| {
                            if (r.lo > from) try ranges.append(p.a, .{ .lo = from, .hi = r.lo - 1 });
                            from = r.hi + 1;
                        }
                        try ranges.append(p.a, .{ .lo = from, .hi = 0x10FFFF });
                    } else try ranges.appendSlice(p.a, rs);
                    continue;
                }
                lo = try p.escapedRune();
            } else lo = try p.rune();
            var hi = lo;
            if (p.peek() == '-' and p.at + 1 < p.src.len and p.src[p.at + 1] != ']') {
                p.at += 1;
                hi = if (p.peek() == '\\') blk: {
                    p.at += 1;
                    break :blk try p.escapedRune();
                } else try p.rune();
                if (hi < lo) return p.fail("a range of a class goes backward");
            }
            try ranges.append(p.a, .{ .lo = lo, .hi = hi });
        }
        return p.classNode(try ranges.toOwnedSlice(p.a), negated);
    }
};

// ---- the program ------------------------------------------------------------------------------

const Emitter = struct {
    a: std.mem.Allocator,
    insts: std.ArrayList(Inst) = .empty,

    fn emit(e: *Emitter, i: Inst) Error!u32 {
        if (e.insts.items.len >= max_program) {
            Prog.err_why = "the pattern is too large";
            return error.BadPattern;
        }
        try e.insts.append(e.a, i);
        return @intCast(e.insts.items.len - 1);
    }

    fn here(e: *Emitter) u32 {
        return @intCast(e.insts.items.len);
    }

    fn gen(e: *Emitter, n: *const Node) Error!void {
        switch (n.*) {
            .empty => {},
            .lit => |cp| _ = try e.emit(.{ .op = .char, .x = cp }),
            .any => _ = try e.emit(.{ .op = .any }),
            .class => |idx| _ = try e.emit(.{ .op = .class, .x = idx }),
            .bol => _ = try e.emit(.{ .op = .bol }),
            .eol => _ = try e.emit(.{ .op = .eol }),
            .bot => _ = try e.emit(.{ .op = .bot }),
            .eot => _ = try e.emit(.{ .op = .eot }),
            .word => _ = try e.emit(.{ .op = .word }),
            .nonword => _ = try e.emit(.{ .op = .nonword }),
            .cat => |items| for (items) |k| try e.gen(k),
            .alt => |branches| {
                var jumps: std.ArrayList(u32) = .empty;
                for (branches, 0..) |b, i| {
                    if (i + 1 < branches.len) {
                        const split = try e.emit(.{ .op = .split });
                        e.insts.items[split].x = e.here();
                        try e.gen(b);
                        try jumps.append(e.a, try e.emit(.{ .op = .jmp }));
                        e.insts.items[split].y = e.here();
                    } else try e.gen(b);
                }
                for (jumps.items) |j| e.insts.items[j].x = e.here();
            },
            .group => |g| {
                if (g.index) |idx| {
                    _ = try e.emit(.{ .op = .save, .x = idx * 2 });
                    try e.gen(g.child);
                    _ = try e.emit(.{ .op = .save, .x = idx * 2 + 1 });
                } else try e.gen(g.child);
            },
            .rep => |r| {
                var i: u32 = 0;
                while (i < r.min) : (i += 1) try e.gen(r.child);
                if (r.max) |max| {
                    // up to max - min optional copies, each leaving the repeat when it does not match
                    var skips: std.ArrayList(u32) = .empty;
                    var k: u32 = r.min;
                    while (k < max) : (k += 1) {
                        const split = try e.emit(.{ .op = .split });
                        try skips.append(e.a, split);
                        const body = e.here();
                        try e.gen(r.child);
                        if (r.greedy) e.insts.items[split].x = body else e.insts.items[split].y = body;
                    }
                    for (skips.items) |s| {
                        if (r.greedy) e.insts.items[s].y = e.here() else e.insts.items[s].x = e.here();
                    }
                } else {
                    const split = try e.emit(.{ .op = .split });
                    const body = e.here();
                    try e.gen(r.child);
                    _ = try e.emit(.{ .op = .jmp, .x = split });
                    if (r.greedy) {
                        e.insts.items[split].x = body;
                        e.insts.items[split].y = e.here();
                    } else {
                        e.insts.items[split].y = body;
                        e.insts.items[split].x = e.here();
                    }
                }
            },
        }
    }
};

/// Compiles a pattern. The flags `(?i)`, `(?m)` and `(?s)` may open it, alone or together, `(?im)`. A bad pattern is `error.BadPattern` with the place and the reason in `Prog.err_at` and `Prog.err_why`.
pub fn compile(a: std.mem.Allocator, pattern: []const u8) Error!Prog {
    return compileWhole(a, pattern, false);
}

/// `compile`, and with `whole` the pattern must match the whole text: `^(?:pattern)$` with the start and the end of the text.
pub fn compileWhole(a: std.mem.Allocator, pattern: []const u8, whole: bool) Error!Prog {
    var p: Parser = .{ .a = a, .src = pattern };
    Prog.err_why = "";
    while (std.mem.startsWith(u8, p.src[p.at..], "(?") and p.at + 2 < p.src.len) {
        var q = p.at + 2;
        var f = p.flags;
        while (q < p.src.len and (p.src[q] == 'i' or p.src[q] == 'm' or p.src[q] == 's')) : (q += 1) {
            switch (p.src[q]) {
                'i' => f.icase = true,
                'm' => f.multiline = true,
                else => f.dotall = true,
            }
        }
        if (q == p.at + 2 or q >= p.src.len or p.src[q] != ')') break;
        p.flags = f;
        p.at = q + 1;
    }
    const tree = try p.parseAlt();
    if (p.at < p.src.len) return p.fail("a ) closes no group");
    var e: Emitter = .{ .a = a };
    _ = try e.emit(.{ .op = .save, .x = 0 });
    if (whole) _ = try e.emit(.{ .op = .bot });
    try e.gen(tree);
    if (whole) _ = try e.emit(.{ .op = .eot });
    _ = try e.emit(.{ .op = .save, .x = 1 });
    _ = try e.emit(.{ .op = .match });
    return .{ .insts = try e.insts.toOwnedSlice(a), .classes = try p.classes.toOwnedSlice(a), .groups = p.groups, .flags = p.flags };
}

/// Compiles a pattern given as a text of the language: either the regex literal form `/pattern/flags` (the flags are `i`, `m`, `s` and `g`; `g` is accepted and ignored) or a bare pattern. A text that starts with `/` is read as the literal form.
pub fn compileSpec(a: std.mem.Allocator, spec: []const u8) Error!Prog {
    return compileSpecWhole(a, spec, false);
}

/// `compileSpec` for a pattern that must match the whole text.
pub fn compileSpecWhole(a: std.mem.Allocator, spec: []const u8, whole: bool) Error!Prog {
    if (spec.len >= 2 and spec[0] == '/') {
        if (std.mem.lastIndexOfScalar(u8, spec, '/')) |last| if (last > 0) {
            const flags = spec[last + 1 ..];
            var ok = true;
            for (flags) |f| if (std.mem.indexOfScalar(u8, "imsg", f) == null) {
                ok = false;
            };
            if (ok) {
                var text: std.ArrayList(u8) = .empty;
                var any = false;
                for (flags) |f| if (f != 'g') {
                    if (!any) try text.appendSlice(a, "(?");
                    any = true;
                    try text.append(a, f);
                };
                if (any) try text.append(a, ')');
                try text.appendSlice(a, spec[1..last]);
                return compileWhole(a, text.items, whole);
            }
        };
    }
    return compileWhole(a, spec, whole);
}

// ---- the machine ------------------------------------------------------------------------------

pub const Match = struct {
    /// Byte offsets: slot 2k and 2k+1 are the start and the end of group k; -1 for a group that did not take part.
    slots: []isize,
};

fn decode(text: []const u8, pos: usize) struct { cp: u21, len: usize } {
    const len = std.unicode.utf8ByteSequenceLength(text[pos]) catch return .{ .cp = text[pos], .len = 1 };
    if (pos + len > text.len) return .{ .cp = text[pos], .len = 1 };
    const cp = std.unicode.utf8Decode(text[pos..][0..len]) catch return .{ .cp = text[pos], .len = 1 };
    return .{ .cp = cp, .len = len };
}

fn fold(cp: u21) u21 {
    if (cp >= 'A' and cp <= 'Z') return cp + 32;
    if (cp >= 0xC0 and cp <= 0xDE and cp != 0xD7) return cp + 32;
    if (cp >= 0x391 and cp <= 0x3A9) return cp + 32;
    if (cp >= 0x410 and cp <= 0x42F) return cp + 32;
    return cp;
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn inClass(prog: *const Prog, cls: Class, cp: u21) bool {
    var hit = false;
    for (cls.ranges) |r| {
        if (cp >= r.lo and cp <= r.hi) {
            hit = true;
            break;
        }
        if (prog.flags.icase) {
            const f = fold(cp);
            const lo_f = fold(r.lo);
            const hi_f = fold(r.hi);
            if (f >= lo_f and f <= hi_f) {
                hit = true;
                break;
            }
        }
    }
    return hit != cls.negated;
}

const Job = union(enum) { explore: struct { pc: u32, pos: usize }, restore: struct { slot: u32, old: isize } };

/// Looks for the first match of `prog` in `text` that starts at `from` or later. The slots are the groups of the match.
pub fn search(a: std.mem.Allocator, prog: *const Prog, text: []const u8, from: usize) Error!?[]isize {
    const bits = (prog.insts.len) * (text.len + 1);
    if (bits > max_visited_bits) return error.TooCostly;
    const visited = try a.alloc(u8, bits / 8 + 1);
    defer a.free(visited);
    @memset(visited, 0);
    const slots = try a.alloc(isize, (prog.groups + 1) * 2);
    errdefer a.free(slots);
    var stack: std.ArrayList(Job) = .empty;
    defer stack.deinit(a);
    var start = from;
    while (start <= text.len) {
        @memset(slots, -1);
        stack.clearRetainingCapacity();
        try stack.append(a, .{ .explore = .{ .pc = 0, .pos = start } });
        while (stack.pop()) |job| {
            switch (job) {
                .restore => |r| slots[r.slot] = r.old,
                .explore => |ex| {
                    var pc = ex.pc;
                    var pos = ex.pos;
                    run: while (true) {
                        const bit = @as(usize, pc) * (text.len + 1) + pos;
                        if (visited[bit / 8] & (@as(u8, 1) << @intCast(bit % 8)) != 0) break :run;
                        visited[bit / 8] |= @as(u8, 1) << @intCast(bit % 8);
                        const inst = prog.insts[pc];
                        switch (inst.op) {
                            .char => {
                                if (pos >= text.len) break :run;
                                const d = decode(text, pos);
                                const same = d.cp == inst.x or (prog.flags.icase and fold(d.cp) == fold(@intCast(inst.x)));
                                if (!same) break :run;
                                pos += d.len;
                                pc += 1;
                            },
                            .any => {
                                if (pos >= text.len) break :run;
                                const d = decode(text, pos);
                                if (d.cp == '\n' and !prog.flags.dotall) break :run;
                                pos += d.len;
                                pc += 1;
                            },
                            .class => {
                                if (pos >= text.len) break :run;
                                const d = decode(text, pos);
                                if (!inClass(prog, prog.classes[inst.x], d.cp)) break :run;
                                pos += d.len;
                                pc += 1;
                            },
                            .split => {
                                try stack.append(a, .{ .explore = .{ .pc = inst.y, .pos = pos } });
                                pc = inst.x;
                            },
                            .jmp => pc = inst.x,
                            .save => {
                                try stack.append(a, .{ .restore = .{ .slot = inst.x, .old = slots[inst.x] } });
                                slots[inst.x] = @intCast(pos);
                                pc += 1;
                            },
                            .bol => {
                                if (pos != 0 and !(prog.flags.multiline and text[pos - 1] == '\n')) break :run;
                                pc += 1;
                            },
                            .eol => {
                                if (pos != text.len and !(prog.flags.multiline and text[pos] == '\n')) break :run;
                                pc += 1;
                            },
                            .bot => {
                                if (pos != 0) break :run;
                                pc += 1;
                            },
                            .eot => {
                                if (pos != text.len) break :run;
                                pc += 1;
                            },
                            .word, .nonword => {
                                const before = pos > 0 and isWord(text[pos - 1]);
                                const after = pos < text.len and isWord(text[pos]);
                                if ((before != after) != (inst.op == .word)) break :run;
                                pc += 1;
                            },
                            .match => return slots,
                        }
                    }
                },
            }
        }
        if (start >= text.len) break;
        start += decode(text, start).len;
    }
    a.free(slots);
    return null;
}

test "spec: text.md#module-regex literals, classes, groups and repeats" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prog = try compile(a, "(\\d+)-(\\w+)");
    const m = (try search(a, &prog, "id 42-abc!", 0)).?;
    try std.testing.expectEqual(@as(isize, 3), m[0]);
    try std.testing.expectEqual(@as(isize, 9), m[1]);
    try std.testing.expectEqual(@as(isize, 3), m[2]);
    try std.testing.expectEqual(@as(isize, 5), m[3]);
    const lit = try compileSpec(a, "/ABC/i");
    try std.testing.expect((try search(a, &lit, "xabcx", 0)) != null);
    const none = try compile(a, "^a+$");
    try std.testing.expect((try search(a, &none, "aaab", 0)) == null);
    const lazy = try compile(a, "a+?");
    const l = (try search(a, &lazy, "aaa", 0)).?;
    try std.testing.expectEqual(@as(isize, 1), l[1]);
    try std.testing.expectError(error.BadPattern, compile(a, "(ab"));
    // a pattern that takes exponential time with a backtracking engine is quick here
    const evil = try compile(a, "(a*)*b");
    try std.testing.expect((try search(a, &evil, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 0)) == null);
}
