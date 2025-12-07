const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get host/machine name in format "MacBook Pro (M2 Pro)" or "ThinkPad X1 Carbon"
pub fn getHost(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getHostDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getHostLinux(allocator);
    }
    return null;
}

fn getHostDarwin(allocator: Allocator) !?[]const u8 {
    // Get hw.model (e.g., "Mac14,5")
    const model = darwin.sysctlString(allocator, "hw.model") catch return null;
    defer allocator.free(model);

    // Look up friendly name
    const friendly_name = getMacModelName(model);
    if (friendly_name) |name| {
        return try allocator.dupe(u8, name);
    }

    // Fallback: return the raw model identifier
    return try allocator.dupe(u8, model);
}

fn getMacModelName(model_id: []const u8) ?[]const u8 {
    // Common Mac model identifiers to friendly names
    // This is a subset - can be expanded
    const models = .{
        // MacBook Pro (Apple Silicon)
        .{ "Mac14,5", "MacBook Pro 14\" (M2 Pro, 2023)" },
        .{ "Mac14,6", "MacBook Pro 16\" (M2 Pro, 2023)" },
        .{ "Mac14,9", "MacBook Pro 14\" (M2 Max, 2023)" },
        .{ "Mac14,10", "MacBook Pro 16\" (M2 Max, 2023)" },
        .{ "Mac15,3", "MacBook Pro 14\" (M3, 2023)" },
        .{ "Mac15,6", "MacBook Pro 14\" (M3 Pro, 2023)" },
        .{ "Mac15,7", "MacBook Pro 16\" (M3 Pro, 2023)" },
        .{ "Mac15,8", "MacBook Pro 14\" (M3 Max, 2023)" },
        .{ "Mac15,9", "MacBook Pro 16\" (M3 Max, 2023)" },
        .{ "Mac15,10", "MacBook Pro 14\" (M3 Pro, 2024)" },
        .{ "Mac15,11", "MacBook Pro 16\" (M3 Max, 2024)" },
        .{ "Mac16,1", "MacBook Pro 14\" (M4, 2024)" },
        .{ "Mac16,5", "MacBook Pro 14\" (M4 Pro, 2024)" },
        .{ "Mac16,6", "MacBook Pro 14\" (M4 Max, 2024)" },
        .{ "Mac16,7", "MacBook Pro 16\" (M4 Pro, 2024)" },
        .{ "Mac16,8", "MacBook Pro 16\" (M4 Max, 2024)" },
        .{ "MacBookPro18,1", "MacBook Pro 16\" (M1 Pro, 2021)" },
        .{ "MacBookPro18,2", "MacBook Pro 16\" (M1 Max, 2021)" },
        .{ "MacBookPro18,3", "MacBook Pro 14\" (M1 Pro, 2021)" },
        .{ "MacBookPro18,4", "MacBook Pro 14\" (M1 Max, 2021)" },
        .{ "MacBookPro17,1", "MacBook Pro 13\" (M1, 2020)" },
        // MacBook Air
        .{ "Mac14,2", "MacBook Air 13\" (M2, 2022)" },
        .{ "Mac14,15", "MacBook Air 15\" (M2, 2023)" },
        .{ "Mac15,12", "MacBook Air 13\" (M3, 2024)" },
        .{ "Mac15,13", "MacBook Air 15\" (M3, 2024)" },
        .{ "MacBookAir10,1", "MacBook Air (M1, 2020)" },
        // Mac Mini
        .{ "Mac14,3", "Mac mini (M2, 2023)" },
        .{ "Mac14,12", "Mac mini (M2 Pro, 2023)" },
        .{ "Mac16,10", "Mac mini (M4, 2024)" },
        .{ "Mac16,11", "Mac mini (M4 Pro, 2024)" },
        .{ "Macmini9,1", "Mac mini (M1, 2020)" },
        // Mac Studio
        .{ "Mac13,1", "Mac Studio (M1 Max, 2022)" },
        .{ "Mac13,2", "Mac Studio (M1 Ultra, 2022)" },
        .{ "Mac14,13", "Mac Studio (M2 Max, 2023)" },
        .{ "Mac14,14", "Mac Studio (M2 Ultra, 2023)" },
        .{ "Mac16,9", "Mac Studio (M4 Max, 2025)" },
        // Mac Pro
        .{ "Mac14,8", "Mac Pro (M2 Ultra, 2023)" },
        // iMac
        .{ "Mac15,4", "iMac 24\" (M3, 2023)" },
        .{ "Mac15,5", "iMac 24\" (M3, 2023)" },
        .{ "iMac21,1", "iMac 24\" (M1, 2021)" },
        .{ "iMac21,2", "iMac 24\" (M1, 2021)" },
    };

    inline for (models) |entry| {
        if (std.mem.eql(u8, model_id, entry[0])) {
            return entry[1];
        }
    }

    return null;
}

fn getHostLinux(allocator: Allocator) !?[]const u8 {
    // Try DMI information
    const product_name = linux.readSysFile(allocator, "/sys/class/dmi/id/product_name") catch null;
    defer if (product_name) |p| allocator.free(p);

    const product_version = linux.readSysFile(allocator, "/sys/class/dmi/id/product_version") catch null;
    defer if (product_version) |v| allocator.free(v);

    if (product_name) |name| {
        if (name.len > 0 and !isGenericProductName(name)) {
            if (product_version) |version| {
                if (version.len > 0 and !std.mem.eql(u8, version, "None") and !std.mem.eql(u8, version, "System Version")) {
                    return try std.fmt.allocPrint(allocator, "{s} ({s})", .{ name, version });
                }
            }
            return try allocator.dupe(u8, name);
        }
    }

    // Fallback: try reading board name
    const board_name = linux.readSysFile(allocator, "/sys/class/dmi/id/board_name") catch null;
    if (board_name) |name| {
        if (name.len > 0) {
            return name;
        }
        allocator.free(name);
    }

    // Last resort: use hostname
    const hostname = linux.getHostname(allocator) catch return null;
    return hostname;
}

fn isGenericProductName(name: []const u8) bool {
    const generic_names = [_][]const u8{
        "System Product Name",
        "To Be Filled By O.E.M.",
        "Default string",
        "None",
        "Type1ProductConfigId",
    };

    for (generic_names) |generic| {
        if (std.ascii.eqlIgnoreCase(name, generic)) {
            return true;
        }
    }
    return false;
}
