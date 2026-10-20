//! Unicode normalization form C (NFC), for `normalize: "nfc"` of the readers
//! (spec/semantics/data-types.md#what-nfc-is). The same letter can be one code point (U+00E9) or two (`e` and
//! the combining acute U+0301); NFC rewrites the text to the composed form so equal-looking text compares equal.
//! The tables are generated from the Unicode data by `script/gen_nfc.py` (nfc_data.zig).
const std = @import("std");
const tables = @import("nfc_data.zig");

// Zig tip: the constants of the Hangul algorithm (Unicode 3.12): the syllables are not in the tables, a few
// integer operations turn a syllable into its jamo and back. `const` at file level is known while compiling.
const s_base: u21 = 0xAC00;
const l_base: u21 = 0x1100;
const v_base: u21 = 0x1161;
const t_base: u21 = 0x11A7;
const l_count: u21 = 19;
const v_count: u21 = 21;
const t_count: u21 = 28;
const n_count: u21 = v_count * t_count;
const s_count: u21 = l_count * n_count;

// Zig tip: a binary search over a sorted array of structs. `lo` and `hi` bound the part still possible; the
// middle element decides which half remains. The tables are sorted by code point (the generator sorts them),
// which is what makes the search valid. `std.math.order` compares two integers.
fn findDecomp(cp: u21) ?tables.Decomp {
    var lo: usize = 0;
    var hi: usize = tables.decomp.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = tables.decomp[mid];
        switch (std.math.order(cp, e.cp)) {
            .eq => return e,
            .lt => hi = mid,
            .gt => lo = mid + 1,
        }
    }
    return null;
}

fn combiningClass(cp: u21) u8 {
    if (cp < 0x300) return 0; // no combining mark below U+0300
    var lo: usize = 0;
    var hi: usize = tables.ccc.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = tables.ccc[mid];
        switch (std.math.order(cp, e.cp)) {
            .eq => return e.class,
            .lt => hi = mid,
            .gt => lo = mid + 1,
        }
    }
    return 0;
}

fn composePair(a: u21, b: u21) ?u21 {
    // Hangul: a leading consonant and a vowel make LV, an LV syllable and a trailing consonant make LVT
    if (a >= l_base and a < l_base + l_count and b >= v_base and b < v_base + v_count) {
        return s_base + ((a - l_base) * v_count + (b - v_base)) * t_count;
    }
    if (a >= s_base and a < s_base + s_count and (a - s_base) % t_count == 0 and b > t_base and b < t_base + t_count) {
        return a + (b - t_base);
    }
    var lo: usize = 0;
    var hi: usize = tables.compose.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const e = tables.compose[mid];
        const key = std.math.order(a, e.a);
        const ord = if (key == .eq) std.math.order(b, e.b) else key;
        switch (ord) {
            .eq => return e.cp,
            .lt => hi = mid,
            .gt => lo = mid + 1,
        }
    }
    return null;
}

// Zig tip: a recursive function appends the full canonical decomposition of one code point to a list. A code
// point without an entry is its own decomposition. `try out.append(a, cp)` can fail only with `OutOfMemory`.
fn decompose(a: std.mem.Allocator, cp: u21, out: *std.ArrayList(u21)) std.mem.Allocator.Error!void {
    if (cp >= s_base and cp < s_base + s_count) {
        const si = cp - s_base;
        try out.append(a, l_base + si / n_count);
        try out.append(a, v_base + (si % n_count) / t_count);
        if (si % t_count != 0) try out.append(a, t_base + si % t_count);
        return;
    }
    if (findDecomp(cp)) |e| {
        try decompose(a, e.a, out);
        if (e.b != 0) try decompose(a, e.b, out);
        return;
    }
    try out.append(a, cp);
}

fn isAscii(text: []const u8) bool {
    for (text) |ch| if (ch >= 0x80) return false;
    return true;
}

/// Is the text in NFC already? (Used to avoid a copy when nothing changes.)
pub fn isNormalized(a: std.mem.Allocator, text: []const u8) bool {
    if (isAscii(text)) return true;
    const out = normalize(a, text) catch return false;
    defer a.free(out);
    return std.mem.eql(u8, out, text);
}

// Zig tip: the steps are three loops over a list of code points: decompose everything, put the combining marks
// in the order of their combining class (a stable insertion sort of each run of marks), then compose from the left.
// `std.unicode.Utf8View` walks the code points of a text; an invalid text is returned unchanged by the caller.
/// The NFC form of `text`, in new memory the caller frees. Text with an invalid UTF-8 sequence is copied unchanged.
pub fn normalize(a: std.mem.Allocator, text: []const u8) std.mem.Allocator.Error![]u8 {
    if (isAscii(text)) return a.dupe(u8, text);
    const view = std.unicode.Utf8View.init(text) catch return a.dupe(u8, text);
    var cps: std.ArrayList(u21) = .empty;
    defer cps.deinit(a);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| try decompose(a, cp, &cps);

    // canonical ordering: a mark moves left past marks with a higher class
    var i: usize = 1;
    while (i < cps.items.len) : (i += 1) {
        const c = combiningClass(cps.items[i]);
        if (c == 0) continue;
        var j = i;
        while (j > 0 and combiningClass(cps.items[j - 1]) > c) : (j -= 1) {
            std.mem.swap(u21, &cps.items[j - 1], &cps.items[j]);
        }
    }

    // canonical composition
    var out: std.ArrayList(u21) = .empty;
    defer out.deinit(a);
    var starter: ?usize = null;
    var last_class: u8 = 0;
    for (cps.items) |cp| {
        const cc = combiningClass(cp);
        if (starter) |s| {
            if (last_class < cc or last_class == 0) {
                if (composePair(out.items[s], cp)) |composed| {
                    out.items[s] = composed;
                    continue;
                }
            }
        }
        if (cc == 0) starter = out.items.len;
        last_class = cc;
        try out.append(a, cp);
    }

    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    for (out.items) |cp| {
        var buf: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &buf) catch continue;
        try bytes.appendSlice(a, buf[0..n]);
    }
    return bytes.toOwnedSlice(a);
}

test "e and a combining accent compose into one code point" {
    const a = std.testing.allocator;
    const out = try normalize(a, "e\u{0301}");
    defer a.free(out);
    try std.testing.expectEqualStrings("\u{00E9}", out);
}

test "already composed text and ASCII are unchanged; marks are put in order" {
    const a = std.testing.allocator;
    const same = try normalize(a, "caf\u{00E9} abc");
    defer a.free(same);
    try std.testing.expectEqualStrings("caf\u{00E9} abc", same);
    // dot below (class 220) and acute (class 230) in the wrong order: NFC gives U+1EA1 (a with dot below) + acute
    const ordered = try normalize(a, "a\u{0301}\u{0323}");
    defer a.free(ordered);
    try std.testing.expectEqualStrings("\u{1EA1}\u{0301}", ordered);
    try std.testing.expect(isNormalized(a, "plain"));
    try std.testing.expect(!isNormalized(a, "e\u{0301}"));
}

test "Hangul jamo compose into a syllable" {
    const a = std.testing.allocator;
    const out = try normalize(a, "\u{1112}\u{1161}\u{11AB}"); // han
    defer a.free(out);
    try std.testing.expectEqualStrings("\u{D55C}", out);
}
