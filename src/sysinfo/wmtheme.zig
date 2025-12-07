const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Get window manager theme
pub fn getWMTheme(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getWMThemeDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getWMThemeLinux(allocator);
    }
    return null;
}

fn getWMThemeDarwin(allocator: Allocator) !?[]const u8 {
    // Check AppleInterfaceStyle for dark mode
    var child = std.process.Child.init(&.{ "defaults", "read", "-g", "AppleInterfaceStyle" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return try allocator.dupe(u8, "Light");

    const stdout = child.stdout orelse return try allocator.dupe(u8, "Light");
    const output = stdout.readToEndAlloc(allocator, 1024) catch return try allocator.dupe(u8, "Light");
    defer allocator.free(output);

    const term = child.wait() catch return try allocator.dupe(u8, "Light");
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                const trimmed = std.mem.trim(u8, output, " \t\r\n");
                if (std.mem.eql(u8, trimmed, "Dark")) {
                    return try allocator.dupe(u8, "Dark");
                }
            }
        },
        else => {},
    }

    return try allocator.dupe(u8, "Light");
}

fn getWMThemeLinux(allocator: Allocator) !?[]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);

    // Try GTK3 settings first
    if (try getGTK3Theme(allocator, home)) |theme| {
        return theme;
    }

    // Try GTK2 settings
    if (try getGTK2Theme(allocator, home)) |theme| {
        return theme;
    }

    // Try dconf/gsettings for GNOME
    if (try getGnomeTheme(allocator)) |theme| {
        return theme;
    }

    return null;
}

fn getGTK3Theme(allocator: Allocator, home: []const u8) !?[]const u8 {
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.config/gtk-3.0/settings.ini", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "gtk-theme-name")) {
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
            if (value.len > 0) {
                return try allocator.dupe(u8, value);
            }
        }
    }

    return null;
}

fn getGTK2Theme(allocator: Allocator, home: []const u8) !?[]const u8 {
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.gtkrc-2.0", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "gtk-theme-name")) {
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
            if (value.len > 0) {
                return try allocator.dupe(u8, value);
            }
        }
    }

    return null;
}

fn getGnomeTheme(allocator: Allocator) !?[]const u8 {
    // Try gsettings
    var child = std.process.Child.init(&.{ "gsettings", "get", "org.gnome.desktop.interface", "gtk-theme" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return null;

    const stdout = child.stdout orelse return null;
    const output = stdout.readToEndAlloc(allocator, 1024) catch return null;
    defer allocator.free(output);

    const term = child.wait() catch return null;
    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                const trimmed = std.mem.trim(u8, output, " \t\r\n'\"");
                if (trimmed.len > 0) {
                    return try allocator.dupe(u8, trimmed);
                }
            }
        },
        else => {},
    }

    return null;
}
