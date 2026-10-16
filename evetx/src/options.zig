//! The options of evetx: how the tool looks and behaves for the user who runs it (the theme, the
//! timers). They are the properties of the user interface, not of Eve: the settings of Eve are in the
//! configuration files of the project. They belong to the user, not to a project, and are kept in the
//! user cache: `evetx-options.txt` (the theme in use and the timers, `key=value` lines) and
//! `evetx-themes.json` (the custom themes); the design puts them in `eve.db` later.
//!
//! The themes: three built-in ones (`theme.themes`: Dark, Gray, Light) that cannot be changed, renamed
//! or removed, then the custom themes of the user. Changing a color of a built-in theme makes a custom
//! copy named after its kind (`Dark Custom1`); a custom theme can be renamed, removed, exported to a
//! JSON file and imported from one. A theme file is one JSON object:
//!
//!   { "name": "Dark Navy", "base": "dark", "colors": { "panel": "#161c24", "deep": "#0c1015", ... } }
//!
//! with one color for every slot of `theme.Slot`; a slot that is missing keeps the color of the
//! built-in theme of the same kind.
const std = @import("std");
const theme = @import("theme.zig");

/// The most custom themes the user can keep, and the longest name of a theme (in bytes).
pub const max_custom = 24;
pub const name_max = 32;

// Zig tip: the name lives in a fixed array inside the struct (`[name_max]u8`) with its length beside it, so a theme
// is a plain value with no pointer to other memory: copying the options (to put them back on Cancel) copies the
// themes too, and nothing has to be freed. `@splat(0)` fills the whole array with zeros.
/// A custom theme of the user.
pub const UserTheme = struct {
    name_buf: [name_max]u8 = @splat(0),
    name_len: u8 = 0,
    base: theme.Base = .dark,
    colors: theme.Palette = theme.themes[0].colors,

    // Zig tip: the result is a slice into the struct itself, so it is valid only while the theme stays where it is:
    // call it on `&options.customs[i]`, not on a copy that goes away.
    pub fn name(self: *const UserTheme) []const u8 {
        return self.name_buf[0..self.name_len];
    }

    // Zig tip: a name that is too long is cut, and the cut steps back over the continuation bytes of UTF-8
    // (`10xxxxxx`), so it never splits a character in two.
    /// Set the name (cut to `name_max` bytes).
    pub fn setName(self: *UserTheme, s: []const u8) void {
        var n = @min(s.len, name_max);
        while (n > 0 and n < s.len and (s[n] & 0xC0) == 0x80) n -= 1;
        @memcpy(self.name_buf[0..n], s[0..n]);
        self.name_len = @intCast(n);
    }
};

// Zig tip: `@intFromEnum(theme.Slot.deep)` is the place of a slot in the palette; the brightness is the same weighted sum
// as `theme.isLight`. A `u24` holds the three bytes of a color, so `>> 16` and `& 0xff` take one of them.
/// The kind of a palette when a theme file does not say it: gray when every color is a gray, light when the
/// editor background is bright.
fn guessBase(p: theme.Palette) theme.Base {
    var gray = true;
    for (p) |c| {
        const r = c >> 16;
        const g = (c >> 8) & 0xff;
        const b = c & 0xff;
        if (r != g or g != b) gray = false;
    }
    if (gray) return .gray;
    const d = p[@intFromEnum(theme.Slot.deep)];
    const lum = ((d >> 16) * 299 + ((d >> 8) & 0xff) * 587 + (d & 0xff) * 114) / 1000;
    return if (lum > 140) .light else .dark;
}

// Zig tip: a struct whose fields all have defaults is made with `.{}`; `@splat(.{})` fills the array of custom themes with
// empty ones, and `n_custom` says how many of them are in use.
/// The options of the user: the theme in use, the custom themes, the timers.
pub const Options = struct {
    /// The theme in use: a place in `theme.themes` (0 to 2), or 3 and more for the custom themes in order.
    theme_id: u8 = 0,
    customs: [max_custom]UserTheme = @splat(.{}),
    n_custom: u8 = 0,
    /// Save the changed files every so many seconds; 0 means never.
    autosave_s: u16 = 0,
    /// Seconds between typing a run command in the prompt and running it; 0 runs it at once.
    run_delay_s: u16 = 3,
    /// Milliseconds between two statements while Trace runs.
    trace_ms: u16 = 400,

    // Zig tip: `theme.themes.len` is known to the compiler; adding the `u8` count gives a `usize`, the type of lengths.
    /// How many themes there are: the built-in ones, then the custom ones.
    pub fn count(self: *const Options) usize {
        return theme.themes.len + self.n_custom;
    }

    // Zig tip: a function in a struct without `self` is called on the type: `Options.isBuiltin(id)`.
    /// Is theme `id` one of the built-in themes (which cannot be changed, renamed or removed)?
    pub fn isBuiltin(id: usize) bool {
        return id < theme.themes.len;
    }

    // Zig tip: `&self.customs[i]` is a pointer into the array, so a change through it changes the theme in the options.
    /// The custom theme `id` (an id of 3 or more).
    pub fn custom(self: *Options, id: usize) *UserTheme {
        return &self.customs[id - theme.themes.len];
    }

    // Zig tip: `if (...) a else b` is an expression, so one `return` serves the built-in themes and the custom ones; the
    // three functions below have the same shape.
    /// The name, the kind and the colors of theme `id`.
    pub fn nameOf(self: *const Options, id: usize) []const u8 {
        return if (isBuiltin(id)) theme.themes[id].name else self.customs[id - theme.themes.len].name();
    }

    pub fn baseOf(self: *const Options, id: usize) theme.Base {
        return if (isBuiltin(id)) theme.themes[id].base else self.customs[id - theme.themes.len].base;
    }

    pub fn paletteOf(self: *const Options, id: usize) theme.Palette {
        return if (isBuiltin(id)) theme.themes[id].colors else self.customs[id - theme.themes.len].colors;
    }

    // Zig tip: `self: *const Options` promises not to change the options; the result is an array
    // returned by value (28 numbers), which is cheap.
    /// The colors of the theme in use.
    pub fn palette(self: *const Options) theme.Palette {
        return self.paletteOf(self.theme_id);
    }

    // Zig tip: `while (i < n) : (i += 1)` is the counting loop of Zig: the part after the colon runs after each turn.
    /// The theme called `name` (upper and lower case are the same), if there is one.
    pub fn findName(self: *const Options, name: []const u8) ?usize {
        var i: usize = 0;
        while (i < self.count()) : (i += 1) {
            if (std.ascii.eqlIgnoreCase(self.nameOf(i), name)) return i;
        }
        return null;
    }

    // Zig tip: `buf` is memory of the caller (a small array on its stack); the answer is a slice of it, so nothing is
    // allocated. `std.fmt.bufPrint` writes into the buffer and fails when it is too small.
    /// The first free name of the form `Dark Custom1`, `Dark Custom2`, … for a copy of a theme of kind `base`.
    pub fn customName(self: *const Options, base: theme.Base, buf: []u8) []const u8 {
        const word: []const u8 = switch (base) {
            .dark => "Dark",
            .gray => "Gray",
            .light => "Light",
        };
        var n: usize = 1;
        while (true) : (n += 1) {
            const s = std.fmt.bufPrint(buf, "{s} Custom{d}", .{ word, n }) catch return "Custom";
            if (self.findName(s) == null) return s;
        }
    }

    // Zig tip: the name is cut first (`wanted[0..@min(...)]`) so the number still fits in `name_max` bytes.
    /// `wanted` when no theme has that name yet, else `wanted 2`, `wanted 3`, …
    pub fn uniqueName(self: *const Options, wanted: []const u8, buf: []u8) []const u8 {
        const w = if (wanted.len == 0) "Imported" else wanted[0..@min(wanted.len, name_max - 4)];
        if (self.findName(w) == null) return w;
        var n: usize = 2;
        while (true) : (n += 1) {
            const s = std.fmt.bufPrint(buf, "{s} {d}", .{ w, n }) catch return w;
            if (self.findName(s) == null) return s;
        }
    }

    // Zig tip: the answer `?u8` is null when nothing was added; the caller decides what to say (`orelse`).
    /// Add a custom theme at the end of the list; its id, or null when the list is full.
    pub fn addCustom(self: *Options, name: []const u8, base: theme.Base, colors: theme.Palette) ?u8 {
        if (self.n_custom >= max_custom) return null;
        var t: UserTheme = .{ .base = base, .colors = colors };
        t.setName(name);
        self.customs[self.n_custom] = t;
        self.n_custom += 1;
        return @intCast(theme.themes.len + self.n_custom - 1);
    }

    // Zig tip: removing from the middle of an array moves the ones after it one place to the left. `std.mem.copyForwards`
    // copies from the first element to the last, which is the safe direction when the two ranges overlap this way.
    /// Remove the custom theme `id`; the theme in use stays the same theme, or becomes the built-in one of its kind.
    pub fn removeCustom(self: *Options, id: usize) void {
        if (isBuiltin(id) or id >= self.count()) return;
        const k = id - theme.themes.len;
        const base = self.customs[k].base;
        std.mem.copyForwards(UserTheme, self.customs[k .. self.n_custom - 1], self.customs[k + 1 .. self.n_custom]);
        self.n_custom -= 1;
        if (self.theme_id == id) {
            self.theme_id = @intFromEnum(base);
        } else if (self.theme_id > id) {
            self.theme_id -= 1;
        }
    }

    // Zig tip: The file is a list of `key=value` lines, read leniently: a line that is not understood
    // is skipped, and a number out of range is brought back into it with `@min`. A damaged file gives
    // the default options and never an error. The theme is written by name, so the custom themes must
    // be read first (`loadThemes`); an unknown name keeps the Dark Theme.
    /// Read the options from the text of the file (after the custom themes).
    pub fn parse(self: *Options, bytes: []const u8) void {
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |raw| {
            const l = std.mem.trim(u8, raw, " \r\t");
            const eq = std.mem.indexOfScalar(u8, l, '=') orelse continue;
            const key = l[0..eq];
            const val = l[eq + 1 ..];
            if (std.mem.eql(u8, key, "theme")) {
                self.theme_id = if (self.findName(val)) |i| @intCast(i) else 0;
            } else if (std.mem.eql(u8, key, "autosave")) {
                self.autosave_s = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 0, 3600));
            } else if (std.mem.eql(u8, key, "rundelay")) {
                self.run_delay_s = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 3, 60));
            } else if (std.mem.eql(u8, key, "tracems")) {
                self.trace_ms = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 400, 5000));
            }
        }
    }

    // Zig tip: `std.fmt.allocPrint` makes the whole text in new memory; the theme is written by its name, not its number,
    // so removing a custom theme never makes the file point at another one.
    /// The text of `evetx-options.txt`. The caller frees it.
    pub fn format(self: *const Options, gpa: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(gpa, "theme={s}\nautosave={d}\nrundelay={d}\ntracems={d}\n", .{ self.nameOf(self.theme_id), self.autosave_s, self.run_delay_s, self.trace_ms });
    }

    // Zig tip: `std.Io.Writer.Allocating` is a writer that collects what is printed in memory it grows; `toOwnedSlice`
    // hands that memory to the caller. `errdefer` frees it if a later step fails.
    /// The text of `evetx-themes.json`: the custom themes, in order. The caller frees it.
    pub fn themesJson(self: *const Options, gpa: std.mem.Allocator) ![]u8 {
        var aw: std.Io.Writer.Allocating = .init(gpa);
        errdefer aw.deinit();
        const w = &aw.writer;
        try w.writeAll("{\n  \"themes\": [");
        for (self.customs[0..self.n_custom], 0..) |*t, i| {
            try w.writeAll(if (i == 0) "\n" else ",\n");
            try writeTheme(w, t.name(), t.base, t.colors, "    ");
        }
        try w.writeAll(if (self.n_custom == 0) "]\n}\n" else "\n  ]\n}\n");
        return aw.toOwnedSlice();
    }

    // Zig tip: `std.json.parseFromSlice(std.json.Value, ...)` reads any JSON into a tree of values (objects, arrays,
    // strings); `parsed.deinit()` frees the whole tree at once. A theme that cannot be read is skipped.
    /// Read the custom themes from the text of `evetx-themes.json`.
    pub fn loadThemes(self: *Options, gpa: std.mem.Allocator, bytes: []const u8) void {
        const parsed = std.json.parseFromSlice(std.json.Value, gpa, bytes, .{}) catch return;
        defer parsed.deinit();
        if (parsed.value != .object) return;
        const list = parsed.value.object.get("themes") orelse return;
        if (list != .array) return;
        for (list.array.items) |v| {
            const t = themeFromValue(v) orelse continue;
            var buf: [name_max + 8]u8 = undefined;
            _ = self.addCustom(self.uniqueName(t.name(), &buf), t.base, t.colors) orelse return;
        }
    }
};

// Zig tip: `inline for` over the fields of the enum `theme.Slot` writes one `"slot": "#rrggbb"` line for each color; in
// each copy of the body `f.name` is a string known to the compiler. `{f}` prints a value with its own `format`
// function: `std.json.fmt(name, .{})` writes the name as a JSON string, with quotes and escapes.
/// Write one theme as a JSON object, each line after the first starting with `indent`.
pub fn writeTheme(w: *std.Io.Writer, name: []const u8, base: theme.Base, colors: theme.Palette, indent: []const u8) !void {
    try w.print("{s}{{\n{s}  \"name\": {f},\n{s}  \"base\": \"{s}\",\n{s}  \"colors\": {{\n", .{ indent, indent, std.json.fmt(name, .{}), indent, @tagName(base), indent });
    inline for (@typeInfo(theme.Slot).@"enum".fields, 0..) |f, i| {
        const comma = if (i + 1 < theme.slot_count) "," else "";
        try w.print("{s}    \"" ++ f.name ++ "\": \"#{x:0>6}\"{s}\n", .{ indent, colors[i], comma });
    }
    try w.print("{s}  }}\n{s}}}", .{ indent, indent });
}

// Zig tip: the same writer as `themesJson`, with no indent: `&aw.writer` is the `*std.Io.Writer` that `writeTheme` takes.
/// The text of a theme file (one theme). The caller frees it.
pub fn themeFile(gpa: std.mem.Allocator, name: []const u8, base: theme.Base, colors: theme.Palette) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try writeTheme(&aw.writer, name, base, colors, "");
    try aw.writer.writeAll("\n");
    return aw.toOwnedSlice();
}

// Zig tip: a JSON value is a tagged union; `v != .object` asks which field it holds, and `v.object.get("name")` is an
// optional (null when the key is missing). `std.meta.stringToEnum` turns "dark" into `theme.Base.dark`, or null.
/// A theme read from a JSON object, or null when it has no name. Missing colors come from the built-in theme of its kind.
pub fn themeFromValue(v: std.json.Value) ?UserTheme {
    if (v != .object) return null;
    const name_v = v.object.get("name") orelse return null;
    if (name_v != .string or std.mem.trim(u8, name_v.string, " ").len == 0) return null;
    const colors_v = v.object.get("colors");
    var base: ?theme.Base = null;
    if (v.object.get("base")) |b| {
        if (b == .string) base = std.meta.stringToEnum(theme.Base, b.string);
    }
    // first the colors that are given, on top of the Dark Theme, to guess the kind when the file does not say it
    var colors = theme.themes[@intFromEnum(base orelse .dark)].colors;
    var given: [theme.slot_count]bool = @splat(false);
    if (colors_v) |cv| {
        if (cv == .object) {
            inline for (@typeInfo(theme.Slot).@"enum".fields, 0..) |f, i| {
                if (cv.object.get(f.name)) |c| {
                    if (c == .string) {
                        const hex = std.mem.trimStart(u8, c.string, "#");
                        if (std.fmt.parseInt(u24, hex, 16)) |x| {
                            colors[i] = x;
                            given[i] = true;
                        } else |_| {}
                    }
                }
            }
        }
    }
    const kind = base orelse guessBase(colors);
    // the colors that are missing come from the built-in theme of that kind
    for (given, 0..) |g, i| {
        if (!g) colors[i] = theme.themes[@intFromEnum(kind)].colors[i];
    }
    var t: UserTheme = .{ .base = kind, .colors = colors };
    t.setName(std.mem.trim(u8, name_v.string, " "));
    return t;
}

// Zig tip: `defer parsed.deinit()` frees the JSON tree when the function returns; the theme is copied out of it first, as
// a value with its own name buffer, so nothing points into the freed tree.
/// Read a theme file (one theme). The caller owns nothing: the answer is a value.
pub fn parseThemeFile(gpa: std.mem.Allocator, bytes: []const u8) ?UserTheme {
    const parsed = std.json.parseFromSlice(std.json.Value, gpa, bytes, .{}) catch return null;
    defer parsed.deinit();
    return themeFromValue(parsed.value);
}

// Zig tip: a `test` block runs with `zig test src/options.zig`; `std.testing.allocator` fails the test when memory
// is not given back, so the test also checks that nothing leaks.
test "a theme goes to JSON and comes back" {
    const gpa = std.testing.allocator;
    var o: Options = .{};
    var buf: [40]u8 = undefined;
    const name = o.customName(.light, &buf);
    try std.testing.expectEqualStrings("Light Custom1", name);
    var colors = theme.themes[2].colors;
    colors[0] = 0x123456;
    const id = o.addCustom(name, .light, colors).?;
    try std.testing.expectEqual(@as(u8, 3), id);
    try std.testing.expectEqualStrings("Light Custom2", o.customName(.light, &buf));
    const text = try o.themesJson(gpa);
    defer gpa.free(text);
    var back: Options = .{};
    back.loadThemes(gpa, text);
    try std.testing.expectEqual(@as(u8, 1), back.n_custom);
    try std.testing.expectEqualStrings("Light Custom1", back.customs[0].name());
    try std.testing.expectEqual(@as(u24, 0x123456), back.customs[0].colors[0]);
    try std.testing.expectEqual(theme.Base.light, back.customs[0].base);
    const file = try themeFile(gpa, "My \"blue\"", .dark, theme.themes[0].colors);
    defer gpa.free(file);
    const t = parseThemeFile(gpa, file).?;
    try std.testing.expectEqualStrings("My \"blue\"", t.name());
    back.parse("theme=light custom1\nautosave=10\n");
    try std.testing.expectEqual(@as(u8, 3), back.theme_id);
    back.removeCustom(3);
    try std.testing.expectEqual(@as(u8, 2), back.theme_id);
}
