const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;

/// Get kernel info in format "Darwin 24.1.0 arm64" or "Linux 6.5.0-arch1 x86_64"
pub fn getKernel(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getKernelDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getKernelLinux(allocator);
    }
    return null;
}

fn getKernelDarwin(allocator: Allocator) !?[]const u8 {
    const os_type = darwin.sysctlString(allocator, "kern.ostype") catch return null;
    defer allocator.free(os_type);

    const os_release = darwin.sysctlString(allocator, "kern.osrelease") catch return null;
    defer allocator.free(os_release);

    const machine = darwin.sysctlString(allocator, "hw.machine") catch return null;
    defer allocator.free(machine);

    return try std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ os_type, os_release, machine });
}

fn getKernelLinux(allocator: Allocator) !?[]const u8 {
    const uname = std.posix.uname();

    const sysname = std.mem.sliceTo(&uname.sysname, 0);
    const release = std.mem.sliceTo(&uname.release, 0);
    const machine = std.mem.sliceTo(&uname.machine, 0);

    return try std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ sysname, release, machine });
}
