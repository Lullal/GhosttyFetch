const std = @import("std");

var resize_pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

fn sigwinchHandler(_: c_int) callconv(.c) void {
    resize_pending.store(true, .release);
}

pub fn install() void {
    const act = std.posix.Sigaction{
        .handler = .{ .handler = sigwinchHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.WINCH, &act, null);
}

pub fn checkAndClear() bool {
    return resize_pending.swap(false, .acquire);
}
