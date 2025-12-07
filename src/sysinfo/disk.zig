const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const sysinfo = @import("../sysinfo.zig");

// C imports for statvfs
const c = @cImport({
    @cInclude("sys/statvfs.h");
});

/// Get disk usage for root filesystem in format "X.XX GiB / Y.YY GiB (Z%)"
pub fn getDisk(allocator: Allocator) !?[]const u8 {
    var stat: c.struct_statvfs = undefined;

    if (c.statvfs("/", &stat) != 0) {
        return null;
    }

    const block_size: u64 = stat.f_frsize;
    const total = stat.f_blocks * block_size;
    const available = stat.f_bavail * block_size;
    const used = if (total > available) total - available else 0;

    return try sysinfo.formatBytes(allocator, used, total);
}
