const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;
const sysinfo = @import("../sysinfo.zig");

/// Get memory usage in format "X.XX GiB / Y.YY GiB (Z%)"
pub fn getMemory(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getMemoryDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getMemoryLinux(allocator);
    }
    return null;
}

fn getMemoryDarwin(allocator: Allocator) !?[]const u8 {
    // Total memory from sysctl
    const total = darwin.sysctlU64("hw.memsize") catch return null;

    // Used memory from Mach VM statistics
    const vm_stats = darwin.hostVMStatistics64() catch return null;

    // Calculate used memory using active/inactive/wired/compressed pages
    const page_size = vm_stats.page_size;
    const used_pages = vm_stats.active_count +
        vm_stats.inactive_count +
        vm_stats.speculative_count +
        vm_stats.wire_count +
        vm_stats.compressor_page_count;
    const purgeable_pages = vm_stats.purgeable_count + vm_stats.external_page_count;

    const used_raw = used_pages * page_size;
    const purgeable = purgeable_pages * page_size;
    const used = if (used_raw > purgeable) used_raw - purgeable else 0;

    return try sysinfo.formatBytes(allocator, used, total);
}

fn getMemoryLinux(allocator: Allocator) !?[]const u8 {
    const meminfo = linux.parseProcMeminfo(allocator) catch return null;

    // Convert KB to bytes
    const total = meminfo.mem_total * 1024;
    const available = meminfo.mem_available * 1024;
    const used = if (total > available) total - available else 0;

    return try sysinfo.formatBytes(allocator, used, total);
}
