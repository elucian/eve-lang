//! The options of evetx: how the tool looks and behaves for the user who runs it (the theme, the
//! timers). They are the properties of the user interface, not of Eve: the settings of Eve are in the
//! configuration files of the project. They belong to the user, not to a project, and are kept in the
//! user cache (a text file for now, `evetx-options.txt`, like the list of projects; the design puts
//! them in `eve.db`).
const std = @import("std");
const theme = @import("theme.zig");

pub const Options = struct {
    /// The theme in use: a place in `theme.themes`, or `theme.custom_id`.
    theme_id: u8 = 0,
    /// The colors of the Custom theme.
    custom: theme.Palette = theme.themes[0].colors,
    /// Save the changed files every so many seconds; 0 means never.
    autosave_s: u16 = 0,
    /// Seconds between typing a run command in the prompt and running it; 0 runs it at once.
    run_delay_s: u16 = 3,
    /// Seconds the pointer must rest on a border between panels before the border can be dragged; 0 means at once.
    hover_delay_s: u16 = 5,
    /// Milliseconds between two statements while Trace runs.
    trace_ms: u16 = 400,

    // Zig tip: `self: *const Options` promises not to change the options; the result is an array
    // returned by value (28 numbers), which is cheap.
    /// The colors of the theme in use.
    pub fn palette(self: *const Options) theme.Palette {
        return if (self.theme_id < theme.themes.len) theme.themes[self.theme_id].colors else self.custom;
    }

    // Zig tip: The file is a list of `key=value` lines, read leniently: a line that is not understood
    // is skipped, and a number out of range is brought back into it with `@min`. A damaged file gives
    // the default options and never an error. `std.meta.stringToEnum` finds the color slot of a name.
    /// Read the options from the text of the file.
    pub fn parse(bytes: []const u8) Options {
        var o: Options = .{};
        var it = std.mem.splitScalar(u8, bytes, '\n');
        while (it.next()) |raw| {
            const l = std.mem.trim(u8, raw, " \r\t");
            const eq = std.mem.indexOfScalar(u8, l, '=') orelse continue;
            const key = l[0..eq];
            const val = l[eq + 1 ..];
            if (std.mem.eql(u8, key, "theme")) {
                o.theme_id = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 0, theme.custom_id));
            } else if (std.mem.eql(u8, key, "autosave")) {
                o.autosave_s = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 0, 3600));
            } else if (std.mem.eql(u8, key, "rundelay")) {
                o.run_delay_s = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 3, 60));
            } else if (std.mem.eql(u8, key, "tracems")) {
                o.trace_ms = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 400, 5000));
            } else if (std.mem.eql(u8, key, "hoverdelay")) {
                o.hover_delay_s = @intCast(@min(std.fmt.parseInt(usize, val, 10) catch 5, 60));
            } else if (std.mem.startsWith(u8, key, "color.")) {
                const slot = std.meta.stringToEnum(theme.Slot, key["color.".len..]) orelse continue;
                const hex = std.fmt.parseInt(u24, val, 16) catch continue;
                o.custom[@intFromEnum(slot)] = hex;
            }
        }
        return o;
    }

    // Zig tip: `inline for` over the fields of the enum writes one `color.<name>=RRGGBB` line for
    // each slot; `{x:0>6}` prints a number in hexadecimal with leading zeros up to 6 digits.
    /// The text of the file. The caller frees it.
    pub fn format(self: *const Options, gpa: std.mem.Allocator) ![]u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(gpa);
        const head = try std.fmt.allocPrint(gpa, "theme={d}\nautosave={d}\nrundelay={d}\nhoverdelay={d}\ntracems={d}\n", .{ self.theme_id, self.autosave_s, self.run_delay_s, self.hover_delay_s, self.trace_ms });
        defer gpa.free(head);
        try out.appendSlice(gpa, head);
        inline for (@typeInfo(theme.Slot).@"enum".fields, 0..) |f, i| {
            const l = try std.fmt.allocPrint(gpa, "color." ++ f.name ++ "={x:0>6}\n", .{self.custom[i]});
            defer gpa.free(l);
            try out.appendSlice(gpa, l);
        }
        return try out.toOwnedSlice(gpa);
    }
};
