const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// C imports for getifaddrs
const c = @cImport({
    @cInclude("sys/types.h");
    @cInclude("sys/socket.h");
    @cInclude("ifaddrs.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
});

/// Get local IP address in format "192.168.1.100/en0"
pub fn getLocalIp(allocator: Allocator) !?[]const u8 {
    var ifaddrs: ?*c.struct_ifaddrs = null;

    if (c.getifaddrs(&ifaddrs) != 0) {
        return null;
    }
    defer c.freeifaddrs(ifaddrs);

    var current = ifaddrs;
    while (current) |ifa| {
        const addr = ifa.ifa_addr orelse {
            current = ifa.ifa_next;
            continue;
        };

        // Only IPv4 for now
        if (addr.*.sa_family != c.AF_INET) {
            current = ifa.ifa_next;
            continue;
        }

        const name = std.mem.sliceTo(ifa.ifa_name, 0);

        // Skip loopback interfaces
        if (std.mem.startsWith(u8, name, "lo")) {
            current = ifa.ifa_next;
            continue;
        }

        // Get IP address
        const in_addr: *const c.struct_sockaddr_in = @ptrCast(@alignCast(addr));
        var ip_buf: [c.INET_ADDRSTRLEN]u8 = undefined;
        const ip_ptr = c.inet_ntop(c.AF_INET, &in_addr.sin_addr, &ip_buf, c.INET_ADDRSTRLEN);

        if (ip_ptr == null) {
            current = ifa.ifa_next;
            continue;
        }

        const ip = std.mem.sliceTo(ip_ptr, 0);

        // Skip 127.x.x.x and 0.x.x.x
        if (std.mem.startsWith(u8, ip, "127.") or std.mem.startsWith(u8, ip, "0.")) {
            current = ifa.ifa_next;
            continue;
        }

        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ ip, name });
    }

    return null;
}
