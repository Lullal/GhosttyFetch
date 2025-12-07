const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get package counts in format "123 (brew), 45 (brew-cask)" or "1234 (apt)"
pub fn getPackages(allocator: Allocator) !?[]const u8 {
    if (builtin.os.tag == .macos) {
        return try getPackagesDarwin(allocator);
    } else if (builtin.os.tag == .linux) {
        return try getPackagesLinux(allocator);
    }
    return null;
}

fn getPackagesDarwin(allocator: Allocator) !?[]const u8 {
    // Get Homebrew prefix
    const prefix = std.process.getEnvVarOwned(allocator, "HOMEBREW_PREFIX") catch blk: {
        // Default based on architecture
        if (builtin.cpu.arch == .aarch64) {
            break :blk try allocator.dupe(u8, "/opt/homebrew");
        } else {
            break :blk try allocator.dupe(u8, "/usr/local");
        }
    };
    defer allocator.free(prefix);

    // Count Cellar packages
    var cellar_path_buf: [256]u8 = undefined;
    const cellar_path = std.fmt.bufPrint(&cellar_path_buf, "{s}/Cellar", .{prefix}) catch return null;
    const brew_count = countDirectories(cellar_path);

    // Count Caskroom packages
    var cask_path_buf: [256]u8 = undefined;
    const cask_path = std.fmt.bufPrint(&cask_path_buf, "{s}/Caskroom", .{prefix}) catch return null;
    const cask_count = countDirectories(cask_path);

    if (brew_count == 0 and cask_count == 0) return null;

    var parts = std.ArrayList([]const u8).empty;
    defer {
        for (parts.items) |item| allocator.free(item);
        parts.deinit(allocator);
    }

    if (brew_count > 0) {
        const brew_str = try std.fmt.allocPrint(allocator, "{d} (brew)", .{brew_count});
        try parts.append(allocator, brew_str);
    }

    if (cask_count > 0) {
        const cask_str = try std.fmt.allocPrint(allocator, "{d} (brew-cask)", .{cask_count});
        try parts.append(allocator, cask_str);
    }

    return try std.mem.join(allocator, ", ", parts.items);
}

fn getPackagesLinux(allocator: Allocator) !?[]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer {
        for (parts.items) |item| allocator.free(item);
        parts.deinit(allocator);
    }

    // Debian/Ubuntu (dpkg)
    const dpkg_count = linux.countLinesMatching(allocator, "/var/lib/dpkg/status", "Status: install ok installed") catch 0;
    if (dpkg_count > 0) {
        const apt_str = try std.fmt.allocPrint(allocator, "{d} (apt)", .{dpkg_count});
        try parts.append(allocator, apt_str);
    }

    // Arch Linux (pacman)
    const pacman_count = countDirectories("/var/lib/pacman/local");
    if (pacman_count > 1) { // -1 for ALPM_DB_VERSION
        const pacman_str = try std.fmt.allocPrint(allocator, "{d} (pacman)", .{pacman_count - 1});
        try parts.append(allocator, pacman_str);
    }

    // Fedora/RHEL (rpm)
    // Try counting from rpm database
    const rpm_count = countRpmPackages();
    if (rpm_count > 0) {
        const rpm_str = try std.fmt.allocPrint(allocator, "{d} (rpm)", .{rpm_count});
        try parts.append(allocator, rpm_str);
    }

    // Flatpak
    const flatpak_count = countDirectories("/var/lib/flatpak/app");
    if (flatpak_count > 0) {
        const flatpak_str = try std.fmt.allocPrint(allocator, "{d} (flatpak)", .{flatpak_count});
        try parts.append(allocator, flatpak_str);
    }

    // Snap
    const snap_count = countSnapPackages();
    if (snap_count > 0) {
        const snap_str = try std.fmt.allocPrint(allocator, "{d} (snap)", .{snap_count});
        try parts.append(allocator, snap_str);
    }

    // Nix
    const nix_count = countNixPackages();
    if (nix_count > 0) {
        const nix_str = try std.fmt.allocPrint(allocator, "{d} (nix)", .{nix_count});
        try parts.append(allocator, nix_str);
    }

    if (parts.items.len == 0) return null;

    return try std.mem.join(allocator, ", ", parts.items);
}

fn countDirectories(path: []const u8) u32 {
    var count: u32 = 0;

    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return 0;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            count += 1;
        }
    }

    return count;
}

fn countRpmPackages() u32 {
    // Try to count from /var/lib/rpm/
    // This is a simplified approach - rpm database is complex
    var dir = std.fs.openDirAbsolute("/var/lib/rpm", .{ .iterate = true }) catch return 0;
    defer dir.close();

    // If the directory exists, assume RPM is available
    // For accurate count, we'd need to parse the RPM database
    // For now, return 0 to skip (run `rpm -qa | wc -l` would be more accurate but requires exec)
    return 0;
}

fn countSnapPackages() u32 {
    var count: u32 = 0;

    var dir = std.fs.openDirAbsolute("/snap", .{ .iterate = true }) catch return 0;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind == .directory) {
            // Skip common non-package directories
            if (!std.mem.eql(u8, entry.name, "bin") and
                !std.mem.eql(u8, entry.name, "core") and
                !std.mem.eql(u8, entry.name, "snapd"))
            {
                count += 1;
            }
        }
    }

    return count;
}

fn countNixPackages() u32 {
    // Count user profile packages
    const home = std.process.getEnvVarOwned(std.heap.page_allocator, "HOME") catch return 0;
    defer std.heap.page_allocator.free(home);

    var path_buf: [512]u8 = undefined;
    const nix_path = std.fmt.bufPrint(&path_buf, "{s}/.nix-profile/manifest.nix", .{home}) catch return 0;

    // If manifest exists, nix is in use
    std.fs.accessAbsolute(nix_path, .{}) catch return 0;

    // For accurate count, we'd need to parse the manifest
    // For now, return 0 to skip
    return 0;
}
