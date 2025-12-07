const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get terminal info in format "Ghostty 1.0.0" or "iTerm2 3.5"
pub fn getTerminal(allocator: Allocator) !?[]const u8 {
    // Try environment variables first
    if (try getTerminalFromEnv(allocator)) |term| {
        return term;
    }

    // Fallback to process detection
    return try detectTerminalFromProcess(allocator);
}

fn getTerminalFromEnv(allocator: Allocator) !?[]const u8 {
    // Check common terminal environment variables

    // Ghostty
    if (std.process.getEnvVarOwned(allocator, "GHOSTTY_VERSION")) |version| {
        defer allocator.free(version);
        return try std.fmt.allocPrint(allocator, "Ghostty {s}", .{version});
    } else |_| {}

    // Kitty
    if (std.process.getEnvVarOwned(allocator, "KITTY_WINDOW_ID")) |_| {
        const version = std.process.getEnvVarOwned(allocator, "KITTY_PID") catch null;
        defer if (version) |v| allocator.free(v);
        return try allocator.dupe(u8, "Kitty");
    } else |_| {}

    // Alacritty
    if (std.process.getEnvVarOwned(allocator, "ALACRITTY_SOCKET")) |_| {
        return try allocator.dupe(u8, "Alacritty");
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "ALACRITTY_WINDOW_ID")) |_| {
        return try allocator.dupe(u8, "Alacritty");
    } else |_| {}

    // WezTerm
    if (std.process.getEnvVarOwned(allocator, "WEZTERM_EXECUTABLE")) |_| {
        return try allocator.dupe(u8, "WezTerm");
    } else |_| {}

    // Windows Terminal (WSL)
    if (std.process.getEnvVarOwned(allocator, "WT_SESSION")) |_| {
        return try allocator.dupe(u8, "Windows Terminal");
    } else |_| {}

    // iTerm2
    if (std.process.getEnvVarOwned(allocator, "ITERM_SESSION_ID")) |_| {
        return try allocator.dupe(u8, "iTerm2");
    } else |_| {}

    // Konsole
    if (std.process.getEnvVarOwned(allocator, "KONSOLE_VERSION")) |version| {
        defer allocator.free(version);
        return try std.fmt.allocPrint(allocator, "Konsole {s}", .{version});
    } else |_| {}

    // GNOME Terminal
    if (std.process.getEnvVarOwned(allocator, "GNOME_TERMINAL_SCREEN")) |_| {
        return try allocator.dupe(u8, "GNOME Terminal");
    } else |_| {}

    // Generic TERM_PROGRAM
    if (std.process.getEnvVarOwned(allocator, "TERM_PROGRAM")) |program| {
        defer allocator.free(program);

        const version = std.process.getEnvVarOwned(allocator, "TERM_PROGRAM_VERSION") catch null;
        defer if (version) |v| allocator.free(v);

        // Map common program names to friendly names
        const friendly = mapTerminalName(program);

        if (version) |ver| {
            return try std.fmt.allocPrint(allocator, "{s} {s}", .{ friendly, ver });
        }
        return try allocator.dupe(u8, friendly);
    } else |_| {}

    // LC_TERMINAL
    if (std.process.getEnvVarOwned(allocator, "LC_TERMINAL")) |terminal| {
        defer allocator.free(terminal);

        const version = std.process.getEnvVarOwned(allocator, "LC_TERMINAL_VERSION") catch null;
        defer if (version) |v| allocator.free(v);

        if (version) |ver| {
            return try std.fmt.allocPrint(allocator, "{s} {s}", .{ terminal, ver });
        }
        return try allocator.dupe(u8, terminal);
    } else |_| {}

    return null;
}

fn mapTerminalName(program: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(program, "Apple_Terminal")) return "Apple Terminal";
    if (std.ascii.eqlIgnoreCase(program, "iTerm.app")) return "iTerm2";
    if (std.ascii.eqlIgnoreCase(program, "vscode")) return "VS Code";
    if (std.ascii.eqlIgnoreCase(program, "Hyper")) return "Hyper";
    if (std.ascii.eqlIgnoreCase(program, "Terminus")) return "Terminus";
    if (std.ascii.eqlIgnoreCase(program, "mintty")) return "mintty";
    return program;
}

fn detectTerminalFromProcess(allocator: Allocator) !?[]const u8 {
    const terminal_names = [_][]const u8{
        "ghostty",
        "kitty",
        "alacritty",
        "wezterm-gui",
        "wezterm",
        "gnome-terminal",
        "konsole",
        "xterm",
        "urxvt",
        "rxvt",
        "terminology",
        "tilix",
        "terminator",
        "iTerm2",
        "Terminal",
        "Hyper",
    };

    if (builtin.os.tag == .macos) {
        var pid = std.c.getpid();
        var iterations: u32 = 0;

        while (iterations < 30) : (iterations += 1) {
            const info = darwin.getProcessInfo(pid) catch break;
            const name = info.name[0..info.name_len];

            for (terminal_names) |terminal| {
                if (std.ascii.eqlIgnoreCase(name, terminal)) {
                    return try allocator.dupe(u8, terminal);
                }
            }

            if (info.ppid <= 1) break;
            pid = info.ppid;
        }
    } else if (builtin.os.tag == .linux) {
        var pid: i32 = @intCast(std.c.getpid());
        var iterations: u32 = 0;

        while (iterations < 30) : (iterations += 1) {
            const info = linux.getProcessInfo(allocator, pid) catch break;
            defer allocator.free(info.name);

            for (terminal_names) |terminal| {
                if (std.ascii.eqlIgnoreCase(info.name, terminal)) {
                    return try allocator.dupe(u8, terminal);
                }
            }

            if (info.ppid <= 1) break;
            pid = info.ppid;
        }
    }

    // Last resort: use TERM
    const term = std.process.getEnvVarOwned(allocator, "TERM") catch return null;
    return term;
}
