const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get title in format "user@hostname"
pub fn getTitle(allocator: Allocator) !?[]const u8 {
    const user = getUsername(allocator) catch return null;
    defer allocator.free(user);

    const hostname = getHostname(allocator) catch return null;
    defer allocator.free(hostname);

    return try std.fmt.allocPrint(allocator, "{s}@{s}", .{ user, hostname });
}

fn getUsername(allocator: Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "USER") catch {
        return try allocator.dupe(u8, "unknown");
    };
}

fn getHostname(allocator: Allocator) ![]u8 {
    if (builtin.os.tag == .macos) {
        return darwin.sysctlString(allocator, "kern.hostname") catch {
            return try allocator.dupe(u8, "unknown");
        };
    } else if (builtin.os.tag == .linux) {
        return linux.getHostname(allocator) catch {
            return try allocator.dupe(u8, "unknown");
        };
    }
    return try allocator.dupe(u8, "unknown");
}
