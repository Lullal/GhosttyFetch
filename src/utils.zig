const std = @import("std");

pub fn stringField(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |v| {
        switch (v) {
            .string => |s| return std.mem.trim(u8, s, " \t\r\n"),
            .number_string => |s| return std.mem.trim(u8, s, " \t\r\n"),
            else => return null,
        }
    }
    return null;
}

pub fn parseI64Field(obj: std.json.ObjectMap, key: []const u8) ?i64 {
    if (obj.get(key)) |v| return parseI64(v);
    return null;
}

pub fn parseF64Field(obj: std.json.ObjectMap, key: []const u8) ?f64 {
    if (obj.get(key)) |v| return parseF64(v);
    return null;
}

pub fn parseU64Field(obj: std.json.ObjectMap, key: []const u8) ?u64 {
    if (obj.get(key)) |v| return parseU64(v);
    return null;
}

pub fn boolField(obj: std.json.ObjectMap, key: []const u8) ?bool {
    if (obj.get(key)) |v| {
        switch (v) {
            .bool => |b| return b,
            else => return null,
        }
    }
    return null;
}

pub fn parseI64(value: std.json.Value) ?i64 {
    switch (value) {
        .integer => |i| return i,
        .float => |f| return @as(i64, @intFromFloat(f)),
        .number_string => |s| return std.fmt.parseInt(i64, s, 10) catch null,
        else => return null,
    }
}

pub fn parseF64(value: std.json.Value) ?f64 {
    switch (value) {
        .float => |f| return f,
        .integer => |i| return @as(f64, @floatFromInt(i)),
        .number_string => |s| return std.fmt.parseFloat(f64, s) catch null,
        else => return null,
    }
}

pub fn parseU64(value: std.json.Value) ?u64 {
    switch (value) {
        .integer => |i| {
            if (i < 0) return null;
            return @as(u64, @intCast(i));
        },
        .float => |f| {
            if (f < 0) return null;
            return @as(u64, @intFromFloat(f));
        },
        .number_string => |s| return std.fmt.parseInt(u64, s, 10) catch null,
        else => return null,
    }
}
