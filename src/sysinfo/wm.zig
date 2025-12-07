const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

/// Get window manager info
pub fn getWM(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        if (try quartzVersion(allocator)) |v| return v;
        return try allocator.dupe(u8, "Quartz Compositor");
    } else if (builtin.os.tag == .linux) {
        return try getWMLinux(allocator);
    }
    return null;
}

fn quartzVersion(allocator: Allocator) !?[]const u8 {
    const plist_path = "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreGraphics.framework/Versions/A/Resources/Info.plist";
    const data = std.fs.cwd().readFileAlloc(allocator, plist_path, 32 * 1024) catch return null;
    defer allocator.free(data);

    const key = "<key>CFBundleShortVersionString</key>";
    const key_idx = std.mem.indexOf(u8, data, key) orelse return null;

    const after_key = data[key_idx + key.len ..];
    const string_tag = "<string>";
    const start_idx = std.mem.indexOf(u8, after_key, string_tag) orelse return null;
    const after_tag = after_key[start_idx + string_tag.len ..];

    const end_idx = std.mem.indexOf(u8, after_tag, "</string>") orelse return null;
    const version_raw = std.mem.trim(u8, after_tag[0..end_idx], " \t\r\n");
    if (version_raw.len == 0) return null;

    const version_copy = try allocator.dupe(u8, version_raw);
    defer allocator.free(version_copy);
    return try std.fmt.allocPrint(allocator, "Quartz Compositor {s}", .{version_copy});
}

fn getWMLinux(allocator: Allocator) !?[]const u8 {
    // Try XDG_CURRENT_DESKTOP first
    if (std.process.getEnvVarOwned(allocator, "XDG_CURRENT_DESKTOP")) |desktop| {
        return desktop;
    } else |_| {}

    // Try XDG_SESSION_DESKTOP
    if (std.process.getEnvVarOwned(allocator, "XDG_SESSION_DESKTOP")) |desktop| {
        return desktop;
    } else |_| {}

    // Try DESKTOP_SESSION
    if (std.process.getEnvVarOwned(allocator, "DESKTOP_SESSION")) |session| {
        return session;
    } else |_| {}

    // Check for specific WM environment variables
    if (std.process.getEnvVarOwned(allocator, "SWAYSOCK")) |_| {
        return try allocator.dupe(u8, "Sway");
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "HYPRLAND_INSTANCE_SIGNATURE")) |_| {
        return try allocator.dupe(u8, "Hyprland");
    } else |_| {}

    if (std.process.getEnvVarOwned(allocator, "I3SOCK")) |_| {
        return try allocator.dupe(u8, "i3");
    } else |_| {}

    // Check for running WM processes
    const wm_names = [_][]const u8{
        "sway",
        "hyprland",
        "i3",
        "bspwm",
        "dwm",
        "awesome",
        "openbox",
        "fluxbox",
        "xfwm4",
        "kwin",
        "mutter",
        "marco",
        "compiz",
        "wayfire",
        "river",
        "weston",
    };

    // Read /proc to find running WM
    var proc_dir = std.fs.openDirAbsolute("/proc", .{ .iterate = true }) catch return null;
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;

        // Check if directory name is a PID
        _ = std.fmt.parseInt(i32, entry.name, 10) catch continue;

        var path_buf: [256]u8 = undefined;
        const comm_path = std.fmt.bufPrint(&path_buf, "/proc/{s}/comm", .{entry.name}) catch continue;

        const comm = std.fs.cwd().readFileAlloc(allocator, comm_path, 256) catch continue;
        defer allocator.free(comm);

        const name = std.mem.trim(u8, comm, " \t\r\n");

        for (wm_names) |wm| {
            if (std.ascii.eqlIgnoreCase(name, wm)) {
                return try allocator.dupe(u8, wm);
            }
        }
    }

    // Check XDG_SESSION_TYPE for Wayland vs X11
    if (std.process.getEnvVarOwned(allocator, "XDG_SESSION_TYPE")) |session_type| {
        defer allocator.free(session_type);
        if (std.mem.eql(u8, session_type, "wayland")) {
            return try allocator.dupe(u8, "Wayland");
        } else if (std.mem.eql(u8, session_type, "x11")) {
            return try allocator.dupe(u8, "X11");
        }
    } else |_| {}

    return null;
}
