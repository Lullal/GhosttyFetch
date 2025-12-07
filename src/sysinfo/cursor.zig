const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Get cursor theme info in format "Adwaita (24px)"
pub fn getCursor(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getCursorDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getCursorLinux(allocator);
    }
    return null;
}

fn getCursorDarwin(allocator: Allocator) !?[]const u8 {
    // macOS doesn't have cursor themes like Linux
    // Could detect cursor size from accessibility settings
    _ = allocator;
    return null;
}

fn getCursorLinux(allocator: Allocator) !?[]const u8 {
    // Try XCURSOR_THEME and XCURSOR_SIZE environment variables
    const theme = std.process.getEnvVarOwned(allocator, "XCURSOR_THEME") catch null;
    defer if (theme) |t| allocator.free(t);

    const size = std.process.getEnvVarOwned(allocator, "XCURSOR_SIZE") catch null;
    defer if (size) |s| allocator.free(s);

    if (theme) |t| {
        if (size) |s| {
            return try std.fmt.allocPrint(allocator, "{s} ({s}px)", .{ t, s });
        }
        return try allocator.dupe(u8, t);
    }

    // Try reading from various config files
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);

    // Try GTK3 settings
    if (try getGTK3Cursor(allocator, home)) |cursor| {
        return cursor;
    }

    // Try Xresources
    if (try getXresourcesCursor(allocator, home)) |cursor| {
        return cursor;
    }

    // Try index.theme in default cursor directory
    if (try getDefaultCursor(allocator, home)) |cursor| {
        return cursor;
    }

    return null;
}

fn getGTK3Cursor(allocator: Allocator, home: []const u8) !?[]const u8 {
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.config/gtk-3.0/settings.ini", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    var cursor_theme: ?[]const u8 = null;
    var cursor_size: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "gtk-cursor-theme-name")) {
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            cursor_theme = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
        } else if (std.mem.startsWith(u8, trimmed, "gtk-cursor-theme-size")) {
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            cursor_size = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
        }
    }

    if (cursor_theme) |t| {
        if (t.len > 0) {
            if (cursor_size) |s| {
                return try std.fmt.allocPrint(allocator, "{s} ({s}px)", .{ t, s });
            }
            return try allocator.dupe(u8, t);
        }
    }

    return null;
}

fn getXresourcesCursor(allocator: Allocator, home: []const u8) !?[]const u8 {
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.Xresources", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    var cursor_theme: ?[]const u8 = null;
    var cursor_size: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.startsWith(u8, trimmed, "Xcursor.theme:")) {
            cursor_theme = std.mem.trim(u8, trimmed["Xcursor.theme:".len..], " \t");
        } else if (std.mem.startsWith(u8, trimmed, "Xcursor.size:")) {
            cursor_size = std.mem.trim(u8, trimmed["Xcursor.size:".len..], " \t");
        }
    }

    if (cursor_theme) |t| {
        if (t.len > 0) {
            if (cursor_size) |s| {
                return try std.fmt.allocPrint(allocator, "{s} ({s}px)", .{ t, s });
            }
            return try allocator.dupe(u8, t);
        }
    }

    return null;
}

fn getDefaultCursor(allocator: Allocator, home: []const u8) !?[]const u8 {
    // Try ~/.icons/default/index.theme
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.icons/default/index.theme", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 8 * 1024) catch return null;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "Inherits")) {
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
            if (value.len > 0) {
                return try allocator.dupe(u8, value);
            }
        }
    }

    return null;
}
