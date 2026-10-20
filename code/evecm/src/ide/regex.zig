//! @eve-module ide.regex
//! @decision D-193
//! @tests code/evecm/src/ide/regex.zig (zig build test)
//! A small regular expression engine for the filter of a table: `.` `*` `+` `?` `{n,m}` `|` `( )` `[a-z]` `[^x]` `^` `$` and the
//! escapes `\d \w \s` (and their capitals). The match is made anywhere in the text and ignores the case of the letters.
//! A pattern that is not a valid expression is the caller's to treat as plain text (`compile` fails with `BadPattern`).
//!
//! The pattern is parsed into a tree, the tree is turned into a short program, and the program is run on the text by
//! following all the possible paths at once (one pass over the text, no backtracking), so no pattern can make a filter slow.
const std = @import("std");

pub const Error = error{ BadPattern, OutOfMemory };

const Op = enum { char, any, class, split, jmp, assert_start, assert_end, match };

// Zig tip: `x` and `y` are the two places a `split` can go to, or the one place of a `jmp`; `c` is the letter of a `char`, and
// for a `class` it is the number of the set of letters. One struct with a few numbers is enough for every instruction.
const Inst = struct { op: Op, c: u8 = 0, x: usize = 0, y: usize = 0 };

const Set = [256]bool;

// Zig tip: a tagged union is a value that is one of several shapes, and `switch` must name them all. `*const Node` is a pointer to
// a node that is not changed; the nodes live in an arena, so they are all freed together when the parse ends.
const Node = union(enum) {
    char: u8,
    any,
    class: u8,
    start,
    end,
    cat: []const *const Node,
    alt: [2]*const Node,
    rep: struct { node: *const Node, min: u16, max: ?u16 },
    empty,
};

const max_copies = 64;

const Parser = struct {
    src: []const u8,
    i: usize = 0,
    arena: std.mem.Allocator,
    sets: std.ArrayList(Set) = .empty,

    fn peek(p: *Parser) ?u8 {
        return if (p.i < p.src.len) p.src[p.i] else null;
    }

    fn node(p: *Parser, n: Node) Error!*const Node {
        const ptr = try p.arena.create(Node);
        ptr.* = n;
        return ptr;
    }

    // Zig tip: the three `parse` functions call each other, one for each level of the grammar: an alternative (`a|b`) is a list of
    // sequences, a sequence is a list of items, an item is an atom with an optional repeat. The level that binds tighter is
    // called by the one above it. This is called recursive descent.
    fn parseAlt(p: *Parser) Error!*const Node {
        const left = try p.parseSeq();
        if (p.peek() == '|') {
            p.i += 1;
            const right = try p.parseAlt();
            return p.node(.{ .alt = .{ left, right } });
        }
        return left;
    }

    fn parseSeq(p: *Parser) Error!*const Node {
        var items: std.ArrayList(*const Node) = .empty;
        while (p.peek()) |c| {
            if (c == '|' or c == ')') break;
            try items.append(p.arena, try p.parseItem());
        }
        if (items.items.len == 0) return p.node(.empty);
        return p.node(.{ .cat = items.items });
    }

    fn parseItem(p: *Parser) Error!*const Node {
        const atom = try p.parseAtom();
        const c = p.peek() orelse return atom;
        var min: u16 = 0;
        var max: ?u16 = null;
        switch (c) {
            '*' => {},
            '+' => min = 1,
            '?' => max = 1,
            '{' => {
                p.i += 1;
                min = try p.number();
                max = min;
                if (p.peek() == ',') {
                    p.i += 1;
                    max = if (p.peek() == '}') null else try p.number();
                }
                if (p.peek() != '}') return error.BadPattern;
                if (min > max_copies or (max != null and (max.? > max_copies or max.? < min))) return error.BadPattern;
            },
            else => return atom,
        }
        p.i += 1;
        return p.node(.{ .rep = .{ .node = atom, .min = min, .max = max } });
    }

    fn number(p: *Parser) Error!u16 {
        const start = p.i;
        while (p.peek()) |c| {
            if (c < '0' or c > '9') break;
            p.i += 1;
        }
        if (p.i == start) return error.BadPattern;
        return std.fmt.parseInt(u16, p.src[start..p.i], 10) catch error.BadPattern;
    }

    fn parseAtom(p: *Parser) Error!*const Node {
        const c = p.src[p.i];
        p.i += 1;
        switch (c) {
            '(' => {
                const inner = try p.parseAlt();
                if (p.peek() != ')') return error.BadPattern;
                p.i += 1;
                return inner;
            },
            '.' => return p.node(.any),
            '^' => return p.node(.start),
            '$' => return p.node(.end),
            '[' => return p.parseClass(),
            '\\' => {
                const e = p.peek() orelse return error.BadPattern;
                p.i += 1;
                if (std.mem.indexOfScalar(u8, "dDwWsS", e) != null) {
                    var set: Set = @as([256]bool, @splat(false));
                    fillEscape(&set, e);
                    return p.addSet(set);
                }
                return p.node(.{ .char = std.ascii.toLower(switch (e) {
                    'n' => '\n',
                    't' => '\t',
                    else => e,
                }) });
            },
            '*', '+', '?', '{', '}', ')' => return error.BadPattern,
            else => return p.node(.{ .char = std.ascii.toLower(c) }),
        }
    }

    fn addSet(p: *Parser, set: Set) Error!*const Node {
        if (p.sets.items.len >= 255) return error.BadPattern;
        try p.sets.append(p.arena, set);
        return p.node(.{ .class = @intCast(p.sets.items.len - 1) });
    }

    // Zig tip: a set of letters is a table of 256 booleans, one for each byte, so asking "is this byte in the set?" is one
    // index. Both cases of a letter are put in, so the match ignores the case.
    fn parseClass(p: *Parser) Error!*const Node {
        var set: Set = @as([256]bool, @splat(false));
        var negate = false;
        if (p.peek() == '^') {
            negate = true;
            p.i += 1;
        }
        var first = true;
        while (true) {
            const c = p.peek() orelse return error.BadPattern;
            p.i += 1;
            if (c == ']' and !first) break;
            first = false;
            var lo = c;
            if (c == '\\') {
                const e = p.peek() orelse return error.BadPattern;
                p.i += 1;
                if (std.mem.indexOfScalar(u8, "dDwWsS", e) != null) {
                    fillEscape(&set, e);
                    continue;
                }
                lo = e;
            }
            var hi = lo;
            if (p.peek() == '-' and p.i + 1 < p.src.len and p.src[p.i + 1] != ']') {
                hi = p.src[p.i + 1];
                p.i += 2;
            }
            if (hi < lo) return error.BadPattern;
            var b: usize = lo;
            while (b <= hi) : (b += 1) {
                set[b] = true;
                set[std.ascii.toLower(@intCast(b))] = true;
                set[std.ascii.toUpper(@intCast(b))] = true;
            }
        }
        if (negate) {
            for (&set) |*b| b.* = !b.*;
        }
        return p.addSet(set);
    }
};

fn fillEscape(set: *Set, e: u8) void {
    const want_not = std.ascii.isUpper(e);
    var b: usize = 0;
    while (b < 256) : (b += 1) {
        const ch: u8 = @intCast(b);
        const inside = switch (std.ascii.toLower(e)) {
            'd' => std.ascii.isDigit(ch),
            'w' => std.ascii.isAlphanumeric(ch) or ch == '_',
            else => std.ascii.isWhitespace(ch),
        };
        if (inside != want_not) set[b] = true;
    }
}

pub const Regex = struct {
    gpa: std.mem.Allocator,
    prog: []Inst,
    sets: []Set,

    // Zig tip: `defer arena.deinit()` frees the whole tree of the parse when `compile` returns; only the program and the sets,
    // copied into memory of the caller (`toOwnedSlice`), stay.
    /// Compile a pattern; `error.BadPattern` when it is not a regular expression.
    pub fn compile(gpa: std.mem.Allocator, pattern: []const u8) Error!Regex {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        var p: Parser = .{ .src = pattern, .arena = arena_state.allocator() };
        const root = try p.parseAlt();
        if (p.i != pattern.len) return error.BadPattern;
        var prog: std.ArrayList(Inst) = .empty;
        errdefer prog.deinit(gpa);
        try emit(gpa, &prog, root);
        try prog.append(gpa, .{ .op = .match });
        const sets = try gpa.dupe(Set, p.sets.items);
        errdefer gpa.free(sets);
        return .{ .gpa = gpa, .prog = try prog.toOwnedSlice(gpa), .sets = sets };
    }

    pub fn deinit(self: *Regex) void {
        self.gpa.free(self.prog);
        self.gpa.free(self.sets);
    }

    /// Does the pattern match somewhere in `text`?
    pub fn find(self: *const Regex, text: []const u8) bool {
        const n = self.prog.len;
        const mem = self.gpa.alloc(usize, n * 3) catch return false;
        defer self.gpa.free(mem);
        const marks = self.gpa.alloc(u32, n) catch return false;
        defer self.gpa.free(marks);
        @memset(marks, 0);
        var cur = Threads{ .list = mem[0..n] };
        var next = Threads{ .list = mem[n .. 2 * n] };
        var gen: u32 = 1;
        cur.mark = gen;
        var pos: usize = 0;
        while (true) : (pos += 1) {
            // a new path may begin at every place of the text: the match is not tied to the start
            if (self.add(&cur, marks, 0, pos, text.len)) return true;
            if (pos >= text.len) return false;
            const ch = std.ascii.toLower(text[pos]);
            gen += 1;
            next.len = 0;
            next.mark = gen;
            var k: usize = 0;
            while (k < cur.len) : (k += 1) {
                const inst = self.prog[cur.list[k]];
                const ok = switch (inst.op) {
                    .char => inst.c == ch,
                    .any => true,
                    .class => self.sets[inst.c][text[pos]],
                    else => false,
                };
                if (ok and self.add(&next, marks, cur.list[k] + 1, pos + 1, text.len)) return true;
            }
            std.mem.swap(Threads, &cur, &next);
        }
    }

    const Threads = struct { list: []usize, len: usize = 0, mark: u32 = 0 };

    // Zig tip: `split`, `jmp` and the two assertions cost no letter, so they are followed at once; the instructions that read a
    // letter are put in the list. `marks[pc] == list.mark` says the place was already followed in this step. The answer is true as
    // soon as `match` is reached.
    fn add(self: *const Regex, t: *Threads, marks: []u32, pc: usize, pos: usize, end: usize) bool {
        if (marks[pc] == t.mark) return false;
        marks[pc] = t.mark;
        const inst = self.prog[pc];
        switch (inst.op) {
            .jmp => return self.add(t, marks, inst.x, pos, end),
            .split => return self.add(t, marks, inst.x, pos, end) or self.add(t, marks, inst.y, pos, end),
            .assert_start => return if (pos == 0) self.add(t, marks, pc + 1, pos, end) else false,
            .assert_end => return if (pos == end) self.add(t, marks, pc + 1, pos, end) else false,
            .match => return true,
            else => {
                t.list[t.len] = pc;
                t.len += 1;
                return false;
            },
        }
    }
};

fn push(gpa: std.mem.Allocator, prog: *std.ArrayList(Inst), inst: Inst) Error!usize {
    try prog.append(gpa, inst);
    return prog.items.len - 1;
}

// Zig tip: the program is written in order, and a `split` or `jmp` whose target is not known yet is written with a blank and
// filled in later ("patched") when the target is reached. A repeat of `min` to `max` times writes the node `min` times, then
// either a loop (no maximum) or `max - min` optional copies, each able to skip the rest.
fn emit(gpa: std.mem.Allocator, prog: *std.ArrayList(Inst), n: *const Node) Error!void {
    switch (n.*) {
        .char => |c| _ = try push(gpa, prog, .{ .op = .char, .c = c }),
        .any => _ = try push(gpa, prog, .{ .op = .any }),
        .class => |c| _ = try push(gpa, prog, .{ .op = .class, .c = c }),
        .start => _ = try push(gpa, prog, .{ .op = .assert_start }),
        .end => _ = try push(gpa, prog, .{ .op = .assert_end }),
        .empty => {},
        .cat => |items| for (items) |it| try emit(gpa, prog, it),
        .alt => |pair| {
            const sp = try push(gpa, prog, .{ .op = .split });
            prog.items[sp].x = prog.items.len;
            try emit(gpa, prog, pair[0]);
            const jm = try push(gpa, prog, .{ .op = .jmp });
            prog.items[sp].y = prog.items.len;
            try emit(gpa, prog, pair[1]);
            prog.items[jm].x = prog.items.len;
        },
        .rep => |r| {
            var k: u16 = 0;
            while (k < r.min) : (k += 1) try emit(gpa, prog, r.node);
            if (r.max) |mx| {
                var skips: [max_copies]usize = undefined;
                var count: usize = 0;
                k = r.min;
                while (k < mx) : (k += 1) {
                    const sp = try push(gpa, prog, .{ .op = .split });
                    prog.items[sp].x = prog.items.len;
                    skips[count] = sp;
                    count += 1;
                    try emit(gpa, prog, r.node);
                }
                for (skips[0..count]) |sp| prog.items[sp].y = prog.items.len;
            } else {
                const sp = try push(gpa, prog, .{ .op = .split });
                prog.items[sp].x = prog.items.len;
                try emit(gpa, prog, r.node);
                _ = try push(gpa, prog, .{ .op = .jmp, .x = sp });
                prog.items[sp].y = prog.items.len;
            }
        },
    }
}

fn matches(pattern: []const u8, text: []const u8) !bool {
    var re = try Regex.compile(std.testing.allocator, pattern);
    defer re.deinit();
    return re.find(text);
}

test "plain text matches anywhere and ignores the case" {
    try std.testing.expect(try matches("bost", "Boston"));
    try std.testing.expect(!try matches("dallas", "Boston"));
}

test "anchors, classes, repeats and alternatives" {
    try std.testing.expect(try matches("^b.*n$", "Boston"));
    try std.testing.expect(!try matches("^o", "Boston"));
    try std.testing.expect(try matches("^[a-c]+\\d{2,3}$", "ab123"));
    try std.testing.expect(!try matches("^[a-c]+\\d{2,3}$", "ab1"));
    try std.testing.expect(try matches("(den|aus)tin?", "Austin"));
    try std.testing.expect(try matches("colou?r", "color"));
    try std.testing.expect(try matches("^[^0-9]*$", "abc"));
    try std.testing.expect(!try matches("^[^0-9]*$", "ab3"));
}

test "a bad pattern is an error" {
    try std.testing.expectError(error.BadPattern, Regex.compile(std.testing.allocator, "(ab"));
    try std.testing.expectError(error.BadPattern, Regex.compile(std.testing.allocator, "*a"));
    try std.testing.expectError(error.BadPattern, Regex.compile(std.testing.allocator, "[a"));
}
