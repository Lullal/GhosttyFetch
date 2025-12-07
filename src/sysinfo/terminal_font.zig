const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Get terminal font (terminal-specific config parsing)
pub fn getTerminalFont(allocator: Allocator) !?[]const u8 {
    // Try Ghostty config first
    if (try getGhosttyFont(allocator)) |font| {
        return font;
    }

    // Try Kitty config
    if (try getKittyFont(allocator)) |font| {
        return font;
    }

    // Try Alacritty config
    if (try getAlacrittyFont(allocator)) |font| {
        return font;
    }

    // Try WezTerm config
    if (try getWezTermFont(allocator)) |font| {
        return font;
    }

    return null;
}

fn getGhosttyFont(allocator: Allocator) !?[]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);

    // Try XDG config first
    const xdg_config = std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME") catch null;
    defer if (xdg_config) |x| allocator.free(x);

    if (xdg_config) |xdg| {
        const xdg_path = try std.fmt.allocPrint(allocator, "{s}/ghostty/config", .{xdg});
        defer allocator.free(xdg_path);
        if (parseGhosttyConfig(allocator, xdg_path)) |font| {
            return font;
        }
    }

    // Try default config path
    var path_buf: [512]u8 = undefined;
    const default_path = std.fmt.bufPrint(&path_buf, "{s}/.config/ghostty/config", .{home}) catch return null;
    return parseGhosttyConfig(allocator, default_path);
}

fn parseGhosttyConfig(allocator: Allocator, path: []const u8) ?[]const u8 {
    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "font-family")) {
            const eq_pos = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
            const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
            if (value.len > 0) {
                return allocator.dupe(u8, value) catch null;
            }
        }
    }

    return null;
}

fn getKittyFont(allocator: Allocator) !?[]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);

    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.config/kitty/kitty.conf", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (std.mem.startsWith(u8, trimmed, "font_family")) {
            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
            _ = parts.next(); // skip "font_family"
            const font = parts.rest();
            if (font.len > 0) {
                return try allocator.dupe(u8, std.mem.trim(u8, font, " \t\"'"));
            }
        }
    }

    return null;
}

fn getAlacrittyFont(allocator: Allocator) !?[]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);

    const paths = [_][]const u8{
        ".config/alacritty/alacritty.toml",
        ".config/alacritty/alacritty.yml",
        ".alacritty.toml",
        ".alacritty.yml",
    };

    for (paths) |rel_path| {
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ home, rel_path }) catch continue;

        const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch continue;
        defer allocator.free(content);

        // Simple TOML/YAML parsing for font.normal.family
        var lines = std.mem.splitScalar(u8, content, '\n');
        var in_font_section = false;
        var in_normal_section = false;

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t");

            if (std.mem.startsWith(u8, trimmed, "[font")) {
                in_font_section = true;
                in_normal_section = std.mem.indexOf(u8, trimmed, "normal") != null;
            } else if (std.mem.startsWith(u8, trimmed, "[") and !std.mem.startsWith(u8, trimmed, "[font")) {
                in_font_section = false;
                in_normal_section = false;
            }

            if (std.mem.startsWith(u8, trimmed, "normal:")) {
                in_normal_section = true;
            }

            if ((in_font_section or in_normal_section) and std.mem.startsWith(u8, trimmed, "family")) {
                const eq_pos = std.mem.indexOfAny(u8, trimmed, "=:") orelse continue;
                const value = std.mem.trim(u8, trimmed[eq_pos + 1 ..], " \t\"'");
                if (value.len > 0) {
                    return try allocator.dupe(u8, value);
                }
            }
        }
    }

    return null;
}

fn getWezTermFont(allocator: Allocator) !?[]const u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);

    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/.wezterm.lua", .{home}) catch return null;

    const content = std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch return null;
    defer allocator.free(content);

    // Simple Lua parsing for font = wezterm.font("...")
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Look for font = wezterm.font("FontName")
        if (std.mem.indexOf(u8, trimmed, "wezterm.font")) |_| {
            const quote_start = std.mem.indexOfScalar(u8, trimmed, '"') orelse
                std.mem.indexOfScalar(u8, trimmed, '\'') orelse continue;
            const rest = trimmed[quote_start + 1 ..];
            const quote_end = std.mem.indexOfScalar(u8, rest, '"') orelse
                std.mem.indexOfScalar(u8, rest, '\'') orelse continue;
            const font = rest[0..quote_end];
            if (font.len > 0) {
                return try allocator.dupe(u8, font);
            }
        }
    }

    return null;
}
