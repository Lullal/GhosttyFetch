const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get CPU info in format "Apple M2 Pro (12) @ 3.49 GHz" or "Intel Core i7-10700K (16) @ 5.10 GHz"
pub fn getCPU(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getCPUDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getCPULinux(allocator);
    }
    return null;
}

fn getCPUDarwin(allocator: Allocator) !?[]const u8 {
    // Get CPU brand string
    const brand = darwin.sysctlString(allocator, "machdep.cpu.brand_string") catch {
        // Apple Silicon doesn't have this, try to build from sysctl
        return try getAppleSiliconCPU(allocator);
    };
    defer allocator.free(brand);

    // Get core count
    const cores = darwin.sysctlI32("hw.physicalcpu") catch 0;

    // Get frequency (Intel)
    const freq_hz = darwin.sysctlU64("hw.cpufrequency") catch 0;
    const freq_ghz: f64 = @as(f64, @floatFromInt(freq_hz)) / 1_000_000_000.0;

    // Clean up the brand string
    const clean_brand = cleanCPUBrand(brand);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, clean_brand);

    if (cores > 0) {
        try out.writer(allocator).print(" ({d})", .{cores});
    }

    if (freq_ghz > 0.1) {
        try out.writer(allocator).print(" @ {d:.2} GHz", .{freq_ghz});
    }

    return try out.toOwnedSlice(allocator);
}

fn getAppleSiliconCPU(allocator: Allocator) !?[]const u8 {
    // Try to get CPU brand string (works on Apple Silicon with recent macOS)
    const brand = darwin.sysctlString(allocator, "machdep.cpu.brand_string") catch blk: {
        // Fallback: try to build from hw.model
        const model = darwin.sysctlString(allocator, "hw.model") catch return null;
        break :blk model;
    };
    defer allocator.free(brand);

    const cores = darwin.sysctlI32("hw.physicalcpu") catch 0;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    // Clean and add CPU name
    const clean_name = cleanCPUBrand(brand);
    try out.appendSlice(allocator, clean_name);

    if (cores > 0) {
        try out.writer(allocator).print(" ({d})", .{cores});
    }

    // Get real frequency from IOKit pmgr
    if (darwin.getAppleSiliconCPUFrequency()) |freq_mhz| {
        const freq_ghz: f64 = @as(f64, @floatFromInt(freq_mhz)) / 1000.0;
        try out.writer(allocator).print(" @ {d:.2} GHz", .{freq_ghz});
    }

    return try out.toOwnedSlice(allocator);
}

fn cleanCPUBrand(brand: []const u8) []const u8 {
    // Remove redundant parts like "(R)", "(TM)", extra spaces
    var result = brand;

    // Trim common prefixes/suffixes
    if (std.mem.startsWith(u8, result, "Intel(R) Core(TM) ")) {
        result = result["Intel(R) Core(TM) ".len..];
        result = std.mem.concat(std.heap.page_allocator, u8, &.{ "Intel Core ", result }) catch result;
    }

    return std.mem.trim(u8, result, " ");
}

fn getCPULinux(allocator: Allocator) !?[]const u8 {
    const cpuinfo = linux.parseProcCpuinfo(allocator) catch return null;
    defer {
        if (cpuinfo.model_name) |m| allocator.free(m);
        if (cpuinfo.vendor_id) |v| allocator.free(v);
    }

    const model = cpuinfo.model_name orelse return null;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    // Clean the model name
    try out.appendSlice(allocator, std.mem.trim(u8, model, " "));

    // Get core count from /proc/cpuinfo or /sys
    if (cpuinfo.cpu_cores) |cores| {
        try out.writer(allocator).print(" ({d})", .{cores});
    }

    // Get max frequency from sysfs
    const freq_khz = getMaxFrequencyLinux();
    if (freq_khz > 0) {
        const freq_ghz = @as(f64, @floatFromInt(freq_khz)) / 1_000_000.0;
        try out.writer(allocator).print(" @ {d:.2} GHz", .{freq_ghz});
    } else if (cpuinfo.cpu_mhz) |mhz| {
        const freq_ghz = mhz / 1000.0;
        try out.writer(allocator).print(" @ {d:.2} GHz", .{freq_ghz});
    }

    return try out.toOwnedSlice(allocator);
}

fn getMaxFrequencyLinux() u64 {
    var buffer: [64]u8 = undefined;

    // Try cpuinfo_max_freq first
    const paths = [_][]const u8{
        "/sys/devices/system/cpu/cpufreq/policy0/cpuinfo_max_freq",
        "/sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq",
        "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq",
    };

    for (paths) |path| {
        const file = std.fs.openFileAbsolute(path, .{}) catch continue;
        defer file.close();

        const bytes_read = file.read(&buffer) catch continue;
        const content = std.mem.trim(u8, buffer[0..bytes_read], " \t\r\n");
        return std.fmt.parseInt(u64, content, 10) catch continue;
    }

    return 0;
}
