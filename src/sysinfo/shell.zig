const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const darwin = if (builtin.os.tag == .macos) @import("../platform/darwin.zig") else undefined;
const linux = if (builtin.os.tag == .linux) @import("../platform/linux.zig") else undefined;

/// Get shell info in format "zsh 5.9" or "bash 5.2.15"
pub fn getShell(allocator: Allocator) !?[]const u8 {
    // First try SHELL environment variable
    const shell_path = std.process.getEnvVarOwned(allocator, "SHELL") catch {
        // Fallback: try to detect from parent process
        return try detectShellFromProcess(allocator);
    };
    defer allocator.free(shell_path);

    const shell_name = std.fs.path.basename(shell_path);
    if (shell_name.len == 0) return null;

    // Get version
    const version = getShellVersion(allocator, shell_path, shell_name) catch null;
    defer if (version) |v| allocator.free(v);

    if (version) |ver| {
        return try std.fmt.allocPrint(allocator, "{s} {s}", .{ shell_name, ver });
    }

    return try allocator.dupe(u8, shell_name);
}

fn detectShellFromProcess(allocator: Allocator) !?[]const u8 {
    const shell_names = [_][]const u8{
        "zsh", "bash", "fish", "ksh", "tcsh", "csh", "dash", "sh",
        "nu", "pwsh", "elvish", "xonsh", "ion",
    };

    if (builtin.os.tag == .macos) {
        var pid = std.c.getpid();
        var iterations: u32 = 0;

        while (iterations < 20) : (iterations += 1) {
            const info = darwin.getProcessInfo(pid) catch break;
            const name = info.name[0..info.name_len];

            for (shell_names) |shell| {
                if (std.ascii.eqlIgnoreCase(name, shell)) {
                    return try allocator.dupe(u8, shell);
                }
            }

            if (info.ppid <= 1) break;
            pid = info.ppid;
        }
    } else if (builtin.os.tag == .linux) {
        var pid: i32 = @intCast(std.c.getpid());
        var iterations: u32 = 0;

        while (iterations < 20) : (iterations += 1) {
            const info = linux.getProcessInfo(allocator, pid) catch break;
            defer allocator.free(info.name);

            for (shell_names) |shell| {
                if (std.ascii.eqlIgnoreCase(info.name, shell)) {
                    return try allocator.dupe(u8, shell);
                }
            }

            if (info.ppid <= 1) break;
            pid = info.ppid;
        }
    }

    return null;
}

fn getShellVersion(allocator: Allocator, shell_path: []const u8, shell_name: []const u8) ![]const u8 {
    // Run shell --version and parse output
    var child = std.process.Child.init(&.{ shell_path, "--version" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;

    child.spawn() catch return error.SpawnFailed;

    const stdout = child.stdout orelse return error.NoStdout;
    const output = stdout.readToEndAlloc(allocator, 8192) catch return error.ReadFailed;
    defer allocator.free(output);

    _ = child.wait() catch {};

    return parseVersionFromOutput(allocator, shell_name, output);
}

fn parseVersionFromOutput(allocator: Allocator, shell_name: []const u8, output: []const u8) ![]const u8 {
    const first_line = blk: {
        const newline = std.mem.indexOfScalar(u8, output, '\n');
        break :blk if (newline) |n| output[0..n] else output;
    };

    // Look for version pattern in output
    var iter = std.mem.tokenizeScalar(u8, first_line, ' ');
    while (iter.next()) |token| {
        // Skip the shell name
        if (std.ascii.eqlIgnoreCase(token, shell_name)) continue;

        // Look for something that looks like a version
        if (token.len > 0 and (std.ascii.isDigit(token[0]) or token[0] == 'v')) {
            // Clean up common prefixes
            var version = token;
            if (version[0] == 'v' or version[0] == 'V') {
                version = version[1..];
            }

            // Remove trailing comma, parenthesis, etc.
            while (version.len > 0) {
                const last = version[version.len - 1];
                if (last == ',' or last == ')' or last == '(' or last == '-') {
                    version = version[0 .. version.len - 1];
                } else {
                    break;
                }
            }

            if (version.len > 0 and std.ascii.isDigit(version[0])) {
                return try allocator.dupe(u8, version);
            }
        }
    }

    return error.NoVersion;
}
