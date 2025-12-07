const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get uptime in format "X days, Y hours, Z mins"
pub fn getUptime(allocator: Allocator) !?[]const u8 {
    const uptime_secs = getUptimeSeconds() catch return null;
    return try formatUptime(allocator, uptime_secs);
}

fn getUptimeSeconds() !i64 {
    if (builtin.os.tag == .macos) {
        const boottime = try darwin.sysctlTimeval("kern.boottime");
        const now = std.time.timestamp();
        return now - boottime.tv_sec;
    } else if (builtin.os.tag == .linux) {
        const uptime = try linux.readUptime();
        return @intFromFloat(uptime);
    }
    return error.UnsupportedPlatform;
}

fn formatUptime(allocator: Allocator, total_secs: i64) ![]const u8 {
    const secs: u64 = @intCast(@max(0, total_secs));
    const days = secs / 86400;
    const hours = (secs % 86400) / 3600;
    const minutes = (secs % 3600) / 60;

    var parts = std.ArrayList([]const u8).empty;
    defer {
        for (parts.items) |item| allocator.free(item);
        parts.deinit(allocator);
    }

    if (days > 0) {
        const day_str = if (days == 1)
            try std.fmt.allocPrint(allocator, "{d} day", .{days})
        else
            try std.fmt.allocPrint(allocator, "{d} days", .{days});
        try parts.append(allocator, day_str);
    }

    if (hours > 0) {
        const hour_str = if (hours == 1)
            try std.fmt.allocPrint(allocator, "{d} hour", .{hours})
        else
            try std.fmt.allocPrint(allocator, "{d} hours", .{hours});
        try parts.append(allocator, hour_str);
    }

    if (minutes > 0 or parts.items.len == 0) {
        const min_str = try std.fmt.allocPrint(allocator, "{d} mins", .{minutes});
        try parts.append(allocator, min_str);
    }

    return try std.mem.join(allocator, ", ", parts.items);
}
