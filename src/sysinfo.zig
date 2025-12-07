const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

const Allocator = types.Allocator;
const SysInfoConfig = types.SysInfoConfig;

// Import all sysinfo modules
const kernel = @import("sysinfo/kernel.zig");
const uptime_mod = @import("sysinfo/uptime.zig");
const memory = @import("sysinfo/memory.zig");
const swap = @import("sysinfo/swap.zig");
const disk = @import("sysinfo/disk.zig");
const os_mod = @import("sysinfo/os.zig");
const host = @import("sysinfo/host.zig");
const cpu = @import("sysinfo/cpu.zig");
const packages = @import("sysinfo/packages.zig");
const localip = @import("sysinfo/localip.zig");
const shell_mod = @import("sysinfo/shell.zig");
const terminal_mod = @import("sysinfo/terminal.zig");
const terminal_font = @import("sysinfo/terminal_font.zig");
const gpu = @import("sysinfo/gpu.zig");
const display = @import("sysinfo/display.zig");
const wm = @import("sysinfo/wm.zig");
const wmtheme = @import("sysinfo/wmtheme.zig");
const cursor = @import("sysinfo/cursor.zig");
const title = @import("sysinfo/title.zig");

/// Load system information lines, formatted for display
pub fn loadSystemInfoLines(allocator: Allocator, config: SysInfoConfig) ![]const []const u8 {
    if (!config.enabled or config.modules.len == 0) {
        return try emptyStringList(allocator);
    }

    var lines = std.ArrayList([]const u8).empty;
    errdefer freeSystemInfoLines(allocator, lines.items);

    for (config.modules) |module_name| {
        const formatted = getModuleValue(allocator, module_name) catch null;
        if (formatted) |value_str| {
            const line = std.fmt.allocPrint(allocator, "{s}: {s}", .{ module_name, value_str }) catch {
                allocator.free(value_str);
                continue;
            };
            allocator.free(value_str);
            lines.append(allocator, line) catch {
                allocator.free(line);
                continue;
            };
        }
    }

    return try lines.toOwnedSlice(allocator);
}

/// Free system info lines allocated by loadSystemInfoLines
pub fn freeSystemInfoLines(allocator: Allocator, lines: []const []const u8) void {
    for (lines) |line| allocator.free(line);
    if (lines.len > 0) allocator.free(lines);
}

fn getModuleValue(allocator: Allocator, module_name: []const u8) !?[]const u8 {
    if (std.ascii.eqlIgnoreCase(module_name, "Title")) {
        return try title.getTitle(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "OS")) {
        return try os_mod.getOS(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Host")) {
        return try host.getHost(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Kernel")) {
        return try kernel.getKernel(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Uptime")) {
        return try uptime_mod.getUptime(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Packages")) {
        return try packages.getPackages(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Shell")) {
        return try shell_mod.getShell(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Display")) {
        return try display.getDisplay(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Terminal")) {
        return try terminal_mod.getTerminal(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "TerminalFont")) {
        return try terminal_font.getTerminalFont(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "CPU")) {
        return try cpu.getCPU(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "GPU")) {
        return try gpu.getGPU(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Memory")) {
        return try memory.getMemory(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Swap")) {
        return try swap.getSwap(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Disk")) {
        return try disk.getDisk(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "WM")) {
        return try wm.getWM(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "WMTheme")) {
        return try wmtheme.getWMTheme(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "Cursor")) {
        return try cursor.getCursor(allocator);
    }
    if (std.ascii.eqlIgnoreCase(module_name, "LocalIp")) {
        return try localip.getLocalIp(allocator);
    }

    // Unknown module
    return null;
}

fn emptyStringList(_: Allocator) ![]const []const u8 {
    return &[_][]const u8{};
}

// Helper functions for formatting (shared across modules)
pub fn formatBytes(allocator: Allocator, used: u64, total: u64) ![]const u8 {
    if (total == 0) return try allocator.dupe(u8, "n/a");
    const percent = @as(u8, @intFromFloat((@as(f64, @floatFromInt(used)) / @as(f64, @floatFromInt(total))) * 100.0));
    return try std.fmt.allocPrint(allocator, "{d:.2} GiB / {d:.2} GiB ({d}%)", .{ bytesToGiB(used), bytesToGiB(total), percent });
}

pub fn bytesToGiB(value: u64) f64 {
    const div = @as(f64, @floatFromInt(1024 * 1024 * 1024));
    return @as(f64, @floatFromInt(value)) / div;
}
