const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get OS name in format "macOS Sequoia 15.1" or "Ubuntu 24.04 LTS"
pub fn getOS(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getOSDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getOSLinux(allocator);
    }
    return null;
}

fn getOSDarwin(allocator: Allocator) !?[]const u8 {
    // Try reading SystemVersion.plist first
    const plist_result = readSystemVersionPlist(allocator);
    if (plist_result) |result| {
        return result;
    }

    // Fallback to sysctl
    const version = darwin.sysctlString(allocator, "kern.osproductversion") catch return null;
    defer allocator.free(version);

    const codename = getMacOSCodename(version);
    if (codename) |name| {
        return try std.fmt.allocPrint(allocator, "macOS {s} {s}", .{ name, version });
    }

    return try std.fmt.allocPrint(allocator, "macOS {s}", .{version});
}

fn readSystemVersionPlist(allocator: Allocator) ?[]const u8 {
    const plist_path = "/System/Library/CoreServices/SystemVersion.plist";
    const content = std.fs.cwd().readFileAlloc(allocator, plist_path, 64 * 1024) catch return null;
    defer allocator.free(content);

    // Simple plist parsing - look for ProductName and ProductUserVisibleVersion
    const product_name = extractPlistValue(content, "ProductName") orelse "macOS";
    const version = extractPlistValue(content, "ProductUserVisibleVersion") orelse return null;

    const codename = getMacOSCodename(version);
    if (codename) |name| {
        return std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ product_name, name, version }) catch null;
    }

    return std.fmt.allocPrint(allocator, "{s} {s}", .{ product_name, version }) catch null;
}

fn extractPlistValue(content: []const u8, key: []const u8) ?[]const u8 {
    // Look for <key>ProductName</key>\n\t<string>VALUE</string>
    var search_buf: [128]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_buf, "<key>{s}</key>", .{key}) catch return null;

    const key_pos = std.mem.indexOf(u8, content, search_key) orelse return null;
    const after_key = content[key_pos + search_key.len ..];

    const string_start = std.mem.indexOf(u8, after_key, "<string>") orelse return null;
    const value_start = after_key[string_start + 8 ..];

    const string_end = std.mem.indexOf(u8, value_start, "</string>") orelse return null;

    return value_start[0..string_end];
}

fn getMacOSCodename(version: []const u8) ?[]const u8 {
    // Extract major version
    var parts = std.mem.splitScalar(u8, version, '.');
    const major_str = parts.next() orelse return null;
    const major = std.fmt.parseInt(u32, major_str, 10) catch return null;

    return switch (major) {
        16 => "Tahoe",
        15 => "Sequoia",
        14 => "Sonoma",
        13 => "Ventura",
        12 => "Monterey",
        11 => "Big Sur",
        10 => blk: {
            // macOS 10.x versions
            const minor_str = parts.next() orelse break :blk null;
            const minor = std.fmt.parseInt(u32, minor_str, 10) catch break :blk null;
            break :blk switch (minor) {
                15 => "Catalina",
                14 => "Mojave",
                13 => "High Sierra",
                12 => "Sierra",
                11 => "El Capitan",
                10 => "Yosemite",
                else => null,
            };
        },
        else => null,
    };
}

fn getOSLinux(allocator: Allocator) !?[]const u8 {
    var os_release = linux.parseOsRelease(allocator) catch {
        // Fallback to uname
        const uname = std.posix.uname();
        const sysname = std.mem.sliceTo(&uname.sysname, 0);
        const release = std.mem.sliceTo(&uname.release, 0);
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ sysname, release });
    };
    defer {
        var iter = os_release.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        os_release.deinit();
    }

    // Try PRETTY_NAME first, then NAME + VERSION
    if (os_release.get("PRETTY_NAME")) |pretty| {
        return try allocator.dupe(u8, pretty);
    }

    const name = os_release.get("NAME") orelse "Linux";
    const version = os_release.get("VERSION");

    if (version) |ver| {
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ name, ver });
    }

    return try allocator.dupe(u8, name);
}
