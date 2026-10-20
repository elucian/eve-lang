//! @eve-module evetx.app.settings
//! @feature F-TLS-24
//! @decision D-173
//! @see code/evetx/src/app.zig:App
//! Options, themes and the settings dialog.
const std = @import("std");
const Io = std.Io;
const vaxis = @import("vaxis");
const Key = vaxis.Key;
const ide = @import("ide");
const options_mod = @import("../options.zig");
const theme = @import("../theme.zig");
const App = @import("../app.zig").App;
const types = @import("types.zig");
const Tab = types.Tab;
const ThemeBtn = types.ThemeBtn;
const OptAction = types.OptAction;

// ------------------------------------------------------------ options

/// Put the colors of the options in use (the drawing reads them in the next frame).
pub fn applyOptions(self: *App) void {
    theme.apply(self.options.palette());
}

/// Write the options and the custom themes to the user cache.
pub fn saveOptions(self: *App) void {
    if (self.options.format(self.gpa)) |text_out| {
        defer self.gpa.free(text_out);
        self.cache.writeFile("evetx-options.txt", text_out) catch |err| self.setMessage("options not saved: {s}", .{@errorName(err)});
    } else |_| {}
    if (self.options.themesJson(self.gpa)) |json| {
        defer self.gpa.free(json);
        self.cache.writeFile("evetx-themes.json", json) catch |err| self.setMessage("themes not saved: {s}", .{@errorName(err)});
    } else |_| {}
}

/// HELP > Options (Ctrl+,): the dialog opens on the Theme tab.
pub fn openOptions(self: *App) void {
    self.opt_backup = self.options;
    self.opt_tab = 0;
    self.opt_edit = .none;
    self.openOverlay(.settings);
}

/// The Save button of the Options dialog: keep the changes and write them.
pub fn optOk(self: *App) void {
    self.opt_edit = .none;
    self.saveOptions();
    self.overlay = .none;
    self.setMessage("options saved", .{});
}

/// The custom theme to change: the one in use, or a new copy of the built-in one in use. Null when the list is full.
pub fn editableTheme(self: *App) ?*options_mod.UserTheme {
    const o = &self.options;
    if (!options_mod.Options.isBuiltin(o.theme_id)) return o.custom(o.theme_id);
    var buf: [40]u8 = undefined;
    const base = o.baseOf(o.theme_id);
    const name = o.customName(base, &buf);
    const id = o.addCustom(name, base, o.palette()) orelse {
        self.setMessage("{d} custom themes is the most: remove one first", .{options_mod.max_custom});
        return null;
    };
    o.theme_id = id;
    self.setMessage("the colors go to a new theme: {s}", .{o.nameOf(id)});
    return o.custom(id);
}

/// Set a color of the theme in use (a built-in theme is copied first, see `editableTheme`).
pub fn setSlotColor(self: *App, slot: usize, hex: u24) void {
    const t = self.editableTheme() orelse return;
    t.colors[slot] = hex;
    self.applyOptions();
}

pub fn setChannel(self: *App, ch: u8, v: u8) void {
    const slot: usize = self.opt_slot;
    const hex: u24 = self.options.palette()[slot];
    const shift: u5 = @intCast(8 * (2 - @as(u5, @intCast(ch))));
    const cleared: u24 = hex & ~(@as(u24, 0xff) << shift);
    self.setSlotColor(slot, cleared | (@as(u24, v) << shift));
}

/// Add `delta` to the channel that is selected in the Colors tab.
pub fn adjustChannel(self: *App, delta: i32) void {
    const hex: u24 = self.options.palette()[self.opt_slot];
    const shift: u5 = @intCast(8 * (2 - @as(u5, @intCast(self.opt_channel))));
    const now: i32 = @intCast((hex >> shift) & 0xff);
    self.setChannel(self.opt_channel, @intCast(std.math.clamp(now + delta, 0, 255)));
}

/// Change timer `row` of the Timers tab (0 Auto save, 1 Run delay, 2 Trace delay) by `delta`.
pub fn adjustTimer(self: *App, row: u8, delta: i32) void {
    if (row == 0) {
        self.options.autosave_s = @intCast(std.math.clamp(@as(i32, self.options.autosave_s) + delta, 0, 3600));
    } else if (row == 2) {
        self.options.trace_ms = @intCast(std.math.clamp(@as(i32, self.options.trace_ms) + delta, 0, 5000));
    } else {
        self.options.run_delay_s = @intCast(std.math.clamp(@as(i32, self.options.run_delay_s) + delta, 0, 60));
    }
}

/// Select the theme `delta` places up or down the list (Up and Down on the Theme tab).
pub fn themeStep(self: *App, delta: i32) void {
    const id: i32 = @intCast(self.options.theme_id);
    const last: i32 = @intCast(self.options.count() - 1);
    self.options.theme_id = @intCast(std.math.clamp(id + delta, 0, last));
    self.applyOptions();
}

/// The folder where Export writes and Import looks first: `<user data folder>/eve/themes`.
pub fn themesDir(self: *App) ![]u8 {
    const up = std.fs.path.dirname(self.cache.dir) orelse ".";
    return std.fmt.allocPrint(self.gpa, "{s}/themes", .{up});
}

/// The file name of a theme.
pub fn themeSlug(name: []const u8, buf: []u8) []const u8 {
    var n: usize = 0;
    var dash = false;
    for (name) |c| {
        if (n + 6 >= buf.len) break;
        if (std.ascii.isAlphanumeric(c)) {
            if (dash and n > 0) {
                buf[n] = '-';
                n += 1;
            }
            dash = false;
            buf[n] = std.ascii.toLower(c);
            n += 1;
        } else dash = true;
    }
    if (n == 0) {
        @memcpy(buf[0..5], "theme");
        n = 5;
    }
    @memcpy(buf[n .. n + 5], ".json");
    return buf[0 .. n + 5];
}

/// A button under the list of themes.
pub fn themeButton(self: *App, b: ThemeBtn) !void {
    const o = &self.options;
    const builtin_theme = options_mod.Options.isBuiltin(o.theme_id);
    switch (b) {
        .rename, .remove => if (builtin_theme) {
            self.setMessage("{s} is a built-in theme: it cannot be renamed or removed (change a color to make a copy)", .{o.nameOf(o.theme_id)});
            return;
        },
        else => {},
    }
    self.opt_in.clearRetainingCapacity();
    switch (b) {
        .rename => {
            try self.opt_in.insertSliceAtCursor(o.nameOf(o.theme_id));
            self.opt_edit = .rename;
        },
        .remove => {
            const name = try self.gpa.dupe(u8, o.nameOf(o.theme_id));
            defer self.gpa.free(name);
            o.removeCustom(o.theme_id);
            self.applyOptions();
            self.setMessage("removed {s} (Cancel brings it back)", .{name});
        },
        .export_file, .import_file => {
            self.opt_edit = .none;
            const dir = try self.themesDir();
            defer self.gpa.free(dir);
            Io.Dir.cwd().createDirPath(self.io, dir) catch {};
            self.openChooser(if (b == .export_file) .theme_export else .theme_import, .settings, dir);
            self.fb_name.clearRetainingCapacity();
            if (b == .export_file) {
                var buf: [64]u8 = undefined;
                try self.fb_name.insertSliceAtCursor(App.themeSlug(o.nameOf(o.theme_id), &buf));
            }
        },
        .apply => try self.themeFieldEnter(),
    }
}

/// Enter in the field under the list of themes: rename the theme.
pub fn themeFieldEnter(self: *App) !void {
    const gpa = self.gpa;
    const o = &self.options;
    const raw = try self.opt_in.toOwnedContents(gpa);
    defer gpa.free(raw);
    const value = std.mem.trim(u8, raw, " ");
    const what = self.opt_edit;
    defer self.opt_edit = .none;
    if (value.len == 0) return;
    switch (what) {
        .none => {},
        .rename => {
            if (options_mod.Options.isBuiltin(o.theme_id)) return;
            if (o.findName(value)) |other| {
                if (other != o.theme_id) {
                    self.setMessage("a theme called {s} exists already", .{value});
                    return;
                }
            }
            o.custom(o.theme_id).setName(value);
            self.setMessage("theme renamed to {s}", .{o.nameOf(o.theme_id)});
        },
    }
}

/// The keys of the Options dialog: Tab changes the tab, the arrows change the values, Enter saves.
pub fn optionsKey(self: *App, key: Key) !void {
    // while the field under the list of themes is open, the keys go to it; Enter applies it (Esc: `closeOverlay`)
    if (self.opt_edit != .none) {
        if (key.matches(Key.enter, .{})) return self.themeFieldEnter();
        return self.opt_in.update(.{ .key_press = key });
    }
    if (key.matches(Key.tab, .{})) {
        self.opt_tab = (self.opt_tab + 1) % 3;
        return;
    }
    if (key.matches(Key.tab, .{ .shift = true })) {
        self.opt_tab = (self.opt_tab + 2) % 3;
        return;
    }
    if (key.matches(Key.enter, .{})) return self.optOk();
    var k = key;
    k.mods.shift = false;
    const small = key.mods.shift;
    const up = k.matches(Key.up, .{});
    const down = k.matches(Key.down, .{});
    const left = k.matches(Key.left, .{});
    const right = k.matches(Key.right, .{});
    switch (self.opt_tab) {
        0 => {
            if (up) self.themeStep(-1) else if (down) self.themeStep(1) else if (k.matches('n', .{})) try self.themeButton(.rename) else if (k.matches(Key.delete, .{})) try self.themeButton(.remove) else if (k.matches('e', .{})) try self.themeButton(.export_file) else if (k.matches('i', .{})) try self.themeButton(.import_file);
        },
        1 => {
            if (up) self.opt_slot = self.opt_slot -| 1 else if (down) self.opt_slot = @intCast(@min(self.opt_slot + 1, theme.slot_count - 1)) else if (left) self.adjustChannel(if (small) -1 else -8) else if (right) self.adjustChannel(if (small) 1 else 8) else if (k.matches('r', .{})) self.opt_channel = 0 else if (k.matches('g', .{})) self.opt_channel = 1 else if (k.matches('b', .{})) self.opt_channel = 2;
        },
        else => {
            const step: i32 = if (self.opt_row == 2) 50 else if (small or self.opt_row != 0) 1 else 10;
            if (up) self.opt_row = (self.opt_row + 2) % 3 else if (down) self.opt_row = (self.opt_row + 1) % 3 else if (left) self.adjustTimer(self.opt_row, -step) else if (right) self.adjustTimer(self.opt_row, step);
        },
    }
}

/// A click in the Options dialog.
pub fn optAction(self: *App, o: OptAction) !void {
    switch (o) {
        .tab => |t| {
            self.opt_tab = t;
            self.opt_edit = .none;
        },
        .theme => |t| {
            self.options.theme_id = t;
            self.opt_edit = .none;
            self.applyOptions();
        },
        .theme_btn => |b| try self.themeButton(b),
        .slot => |i| self.opt_slot = i,
        .channel => |c| self.opt_channel = c,
        .slider => |s| {
            self.opt_channel = s.ch;
            self.setChannel(s.ch, s.v);
        },
        .swatch => |hex| self.setSlotColor(self.opt_slot, hex),
        .auto => |d| {
            self.opt_row = 0;
            self.adjustTimer(0, d);
        },
        .delay => |d| {
            self.opt_row = 1;
            self.adjustTimer(1, d);
        },
        .trace => |d| {
            self.opt_row = 2;
            self.adjustTimer(2, d);
        },
        .ok => self.optOk(),
        // the built-in Dark Theme and the first timers; the custom themes stay
        .defaults => {
            const keep = self.options;
            self.options = .{ .customs = keep.customs, .n_custom = keep.n_custom };
            self.applyOptions();
        },
    }
}

/// The file that the folder selector names: the folder shown and the name field.
pub fn chooserFile(self: *App) !?[]u8 {
    const raw = try self.fb_name.toOwnedContents(self.gpa);
    defer self.gpa.free(raw);
    const name = std.mem.trim(u8, raw, " \"");
    if (name.len == 0) return null;
    const dir = self.fb_path orelse return null;
    return try std.fs.path.join(self.gpa, &.{ dir, name });
}

/// Export (the folder selector opened by Export): write the theme in use to the file named.
pub fn exportTheme(self: *App) !void {
    const gpa = self.gpa;
    const o = &self.options;
    const named = (try self.chooserFile()) orelse {
        self.setMessage("type the name of the file", .{});
        return;
    };
    defer gpa.free(named);
    const path = if (std.ascii.endsWithIgnoreCase(named, ".json")) try gpa.dupe(u8, named) else try std.fmt.allocPrint(gpa, "{s}.json", .{named});
    defer gpa.free(path);
    const bytes = try options_mod.themeFile(gpa, o.nameOf(o.theme_id), o.baseOf(o.theme_id), o.palette());
    defer gpa.free(bytes);
    self.chooserDone();
    Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = bytes }) catch |err| {
        return self.fail("Cannot write {s}: {s}.", .{ path, @errorName(err) });
    };
    self.setMessage("exported {s} to {s}", .{ o.nameOf(o.theme_id), path });
}

/// Import (the folder selector opened by Import): read the theme file named and add it as a custom theme.
pub fn importTheme(self: *App) !void {
    const gpa = self.gpa;
    const o = &self.options;
    const path = (try self.chooserFile()) orelse {
        self.setMessage("choose a theme file (.json)", .{});
        return;
    };
    defer gpa.free(path);
    self.chooserDone();
    const bytes = Io.Dir.cwd().readFileAlloc(self.io, path, gpa, .limited(1 << 20)) catch |err| {
        return self.fail("Cannot read {s}: {s}.", .{ path, @errorName(err) });
    };
    defer gpa.free(bytes);
    const t = options_mod.parseThemeFile(gpa, bytes) orelse {
        return self.fail("{s} is not a theme. A theme file is a JSON object with a name and colors.", .{std.fs.path.basename(path)});
    };
    var buf: [options_mod.name_max + 8]u8 = undefined;
    const name = o.uniqueName(t.name(), &buf);
    const id = o.addCustom(name, t.base, t.colors) orelse {
        return self.fail("{d} custom themes is the most: remove one first.", .{options_mod.max_custom});
    };
    o.theme_id = id;
    self.applyOptions();
    self.setMessage("imported {s}: rename it if you like", .{o.nameOf(id)});
}

/// An operation failed: a pop-up says why (title "Operation failed"); OK goes back to the dialog that was open.
pub fn fail(self: *App, comptime f: []const u8, args: anytype) void {
    if (self.alert_msg) |m| self.gpa.free(m);
    self.alert_msg = std.fmt.allocPrint(self.gpa, f, args) catch null;
    self.alert_back = self.overlay;
    self.overlay = .alert;
}
