const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;
const sysinfo = @import("../sysinfo.zig");

// C imports for macOS swap info
const c = if (builtin.os.tag == .macos) @cImport({
    @cInclude("sys/sysctl.h");
}) else undefined;

/// Get swap usage in format "X.XX GiB / Y.YY GiB (Z%)"
pub fn getSwap(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getSwapDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getSwapLinux(allocator);
    }
    return null;
}

fn getSwapDarwin(allocator: Allocator) !?[]const u8 {
    // Read vm.swapusage sysctl
    var swap_usage: c.struct_xsw_usage = undefined;
    var size: usize = @sizeOf(c.struct_xsw_usage);

    if (c.sysctlbyname("vm.swapusage", &swap_usage, &size, null, 0) != 0) {
        return null;
    }

    const total: u64 = swap_usage.xsu_total;
    const used: u64 = swap_usage.xsu_used;

    if (total == 0) return null;

    return try sysinfo.formatBytes(allocator, used, total);
}

fn getSwapLinux(allocator: Allocator) !?[]const u8 {
    const meminfo = linux.parseProcMeminfo(allocator) catch return null;

    // Convert KB to bytes
    const total = meminfo.swap_total * 1024;
    const free = meminfo.swap_free * 1024;
    const used = if (total > free) total - free else 0;

    if (total == 0) return null;

    return try sysinfo.formatBytes(allocator, used, total);
}
