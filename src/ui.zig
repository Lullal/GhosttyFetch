const std = @import("std");
const types = @import("types.zig");
const frames = @import("frames.zig");

const Allocator = types.Allocator;
const ColorPreferences = types.ColorPreferences;
const InfoColors = types.InfoColors;
const reset_code = types.reset_code;
const visibleWidth = frames.visibleWidth;
const normalizePanelWidth = frames.normalizePanelWidth;

pub fn combineFrameAndInfo(allocator: Allocator, frame: []const u8, info_lines: []const []const u8, info_start_col: usize) ![]u8 {
    var art_lines = std.ArrayList([]const u8).empty;
    defer art_lines.deinit(allocator);

    var it = std.mem.splitScalar(u8, frame, '\n');
    while (it.next()) |line| {
        try art_lines.append(allocator, line);
    }

    const total = @max(art_lines.items.len, info_lines.len);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    for (0..total) |idx| {
        const art = if (idx < art_lines.items.len) art_lines.items[idx] else "";
        const info = if (idx < info_lines.len) info_lines[idx] else "";

        try out.appendSlice(allocator, art);
        const move_col = try std.fmt.allocPrint(allocator, "\x1b[{d}G", .{info_start_col});
        defer allocator.free(move_col);
        try out.appendSlice(allocator, move_col);
        try out.appendSlice(allocator, info);
        try out.append(allocator, '\n');
    }

    return try out.toOwnedSlice(allocator);
}

pub fn appendPromptLines(allocator: Allocator, combined: []const u8, prompt_line: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, combined);
    try out.appendSlice(allocator, prompt_line);

    return try out.toOwnedSlice(allocator);
}

pub fn stylizeInfoLines(allocator: Allocator, lines: []const []const u8, width: usize, prefs: ColorPreferences) ![]const []const u8 {
    if (lines.len == 0) {
        var list = std.ArrayList([]const u8).empty;
        return try list.toOwnedSlice(allocator);
    }

    const colors = resolveInfoColors(prefs);
    const panel_width = normalizePanelWidth(width);
    const inner_width = if (panel_width > 4) panel_width - 4 else panel_width;

    const max_label_width = blk: {
        if (inner_width > 28) break :blk inner_width - 20;
        if (inner_width > 14) break :blk inner_width - 10;
        break :blk inner_width / 2;
    };
    var label_width = computeLabelColumnWidth(lines, max_label_width);
    if (label_width < 6) label_width = 6;

    const prefix_width = 2 + label_width + 2;
    const value_width = if (inner_width > prefix_width) inner_width - prefix_width else 1;

    var out = std.ArrayList([]const u8).empty;
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit(allocator);
    }

    try out.append(allocator, try buildBorderLine(allocator, panel_width, "▛", "▜", "▀", colors));
    try out.append(allocator, try renderBannerLine(allocator, panel_width, inner_width, colors));
    try out.append(allocator, try buildBorderLine(allocator, panel_width, "█", "█", "┈", colors));

    for (lines) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) continue;

        var label_text: []const u8 = "";
        var value_text = trimmed;

        if (std.mem.indexOfScalar(u8, trimmed, ':')) |idx| {
            label_text = std.mem.trimRight(u8, trimmed[0..idx], " \t");
            value_text = std.mem.trimLeft(u8, trimmed[idx + 1 ..], " \t");
        }

        var wrapped = std.ArrayList([]const u8).empty;
        errdefer {
            for (wrapped.items) |item| allocator.free(item);
            wrapped.deinit(allocator);
        }
        try wrapLineTo(&wrapped, allocator, value_text, value_width);
        if (wrapped.items.len == 0) {
            try wrapped.append(allocator, try allocator.dupe(u8, ""));
        }

        for (wrapped.items, 0..) |part, idx| {
            const label_for_row = if (idx == 0) label_text else "";
            const row = try renderInfoRow(allocator, panel_width, inner_width, label_for_row, part, label_width, colors);
            try out.append(allocator, row);
        }

        for (wrapped.items) |item| allocator.free(item);
        wrapped.deinit(allocator);
    }

    try out.append(allocator, try buildBorderLine(allocator, panel_width, "▙", "▟", "▄", colors));

    return try out.toOwnedSlice(allocator);
}

fn computeLabelColumnWidth(lines: []const []const u8, max_width: usize) usize {
    var width: usize = 0;
    for (lines) |line| {
        if (std.mem.indexOfScalar(u8, line, ':')) |idx| {
            const label = std.mem.trim(u8, line[0..idx], " \t");
            const w = visibleWidth(label);
            if (w > width) width = w;
        }
    }
    if (width == 0) width = 6;
    if (width > max_width) width = max_width;
    return width;
}

pub fn resolveInfoColors(prefs: ColorPreferences) InfoColors {
    if (prefs.enable and prefs.color_code != null) {
        return .{
            .accent = prefs.color_code.?,
            .muted = "\x1b[38;5;245m",
            .value = "\x1b[38;5;252m",
            .strong = "\x1b[1m",
            .reset = reset_code,
        };
    }
    return .{ .accent = "", .muted = "", .value = "", .strong = "", .reset = "" };
}

fn buildBorderLine(allocator: Allocator, width: usize, left: []const u8, right: []const u8, fill: []const u8, colors: InfoColors) ![]const u8 {
    const panel_width = normalizePanelWidth(width);
    const fill_count = if (panel_width > 2) panel_width - 2 else panel_width;

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    if (colors.accent.len > 0) try out.appendSlice(allocator, colors.accent);
    try out.appendSlice(allocator, left);
    try appendRepeatGlyph(&out, allocator, fill, fill_count);
    try out.appendSlice(allocator, right);
    if (colors.reset.len > 0) try out.appendSlice(allocator, colors.reset);

    return try out.toOwnedSlice(allocator);
}

fn renderBannerLine(allocator: Allocator, panel_width: usize, inner_width: usize, colors: InfoColors) ![]const u8 {
    var banner = std.ArrayList(u8).empty;
    errdefer banner.deinit(allocator);

    if (colors.accent.len > 0) try banner.appendSlice(allocator, colors.accent);
    if (colors.strong.len > 0) try banner.appendSlice(allocator, colors.strong);
    try banner.appendSlice(allocator, "Ghostty Fetch");
    if (colors.reset.len > 0) try banner.appendSlice(allocator, colors.reset);

    try banner.appendSlice(allocator, " ");
    if (colors.muted.len > 0) try banner.appendSlice(allocator, colors.muted);
    try banner.appendSlice(allocator, "// System Info");
    if (colors.reset.len > 0) try banner.appendSlice(allocator, colors.reset);

    const content = try banner.toOwnedSlice(allocator);
    defer allocator.free(content);
    return try frameContentLine(allocator, panel_width, inner_width, content, colors);
}

fn frameContentLine(allocator: Allocator, panel_width: usize, inner_width: usize, content: []const u8, colors: InfoColors) ![]const u8 {
    var row = std.ArrayList(u8).empty;
    errdefer row.deinit(allocator);

    const safe_inner = if (inner_width == 0) panel_width else inner_width;
    const content_width = visibleWidth(content);
    const pad = if (safe_inner > content_width) safe_inner - content_width else 0;

    if (colors.accent.len > 0) try row.appendSlice(allocator, colors.accent);
    try row.appendSlice(allocator, "█");
    if (colors.reset.len > 0) try row.appendSlice(allocator, colors.reset);
    try row.append(allocator, ' ');
    try row.appendSlice(allocator, content);
    try appendSpaces(&row, allocator, pad);
    try row.append(allocator, ' ');
    if (colors.accent.len > 0) try row.appendSlice(allocator, colors.accent);
    try row.appendSlice(allocator, "█");
    if (colors.reset.len > 0) try row.appendSlice(allocator, colors.reset);

    return try row.toOwnedSlice(allocator);
}

fn renderInfoRow(allocator: Allocator, panel_width: usize, inner_width: usize, label: []const u8, value: []const u8, label_width: usize, colors: InfoColors) ![]const u8 {
    var content = std.ArrayList(u8).empty;
    errdefer content.deinit(allocator);

    const label_visible = visibleWidth(label);
    try content.append(allocator, ' ');

    if (label_visible > 0) {
        if (colors.accent.len > 0) try content.appendSlice(allocator, colors.accent);
        if (colors.strong.len > 0) try content.appendSlice(allocator, colors.strong);
        try content.appendSlice(allocator, label);
        if (colors.reset.len > 0) try content.appendSlice(allocator, colors.reset);
        const pad = if (label_visible < label_width) label_width - label_visible else 0;
        try appendSpaces(&content, allocator, pad);
    } else {
        try appendSpaces(&content, allocator, label_width);
    }

    if (colors.accent.len > 0) {
        try content.appendSlice(allocator, colors.accent);
    } else if (colors.muted.len > 0) {
        try content.appendSlice(allocator, colors.muted);
    }
    try content.appendSlice(allocator, "│ ");
    if (colors.reset.len > 0) try content.appendSlice(allocator, colors.reset);

    if (colors.value.len > 0) try content.appendSlice(allocator, colors.value);
    try content.appendSlice(allocator, value);
    if (colors.reset.len > 0) try content.appendSlice(allocator, colors.reset);

    const content_slice = try content.toOwnedSlice(allocator);
    defer allocator.free(content_slice);
    return try frameContentLine(allocator, panel_width, inner_width, content_slice, colors);
}

fn wrapLineTo(out: *std.ArrayList([]const u8), allocator: Allocator, line: []const u8, width: usize) !void {
    var remaining = std.mem.trim(u8, line, " \t");
    if (visibleWidth(remaining) <= width or width == 0) {
        const duped = try allocator.dupe(u8, remaining);
        try out.append(allocator, duped);
        return;
    }

    while (remaining.len > 0) {
        var cut: usize = if (remaining.len < width) remaining.len else width;
        if (cut < remaining.len) {
            var space_idx: ?usize = null;
            var i: usize = cut;
            while (i > 0) : (i -= 1) {
                if (remaining[i - 1] == ' ') {
                    space_idx = i - 1;
                    break;
                }
            }
            if (space_idx) |s| cut = s;
        }
        const chunk = std.mem.trimRight(u8, remaining[0..cut], " ");
        if (chunk.len > 0) {
            try out.append(allocator, try allocator.dupe(u8, chunk));
        }
        remaining = std.mem.trimLeft(u8, remaining[cut..], " ");
        if (visibleWidth(remaining) <= width) {
            if (remaining.len > 0) try out.append(allocator, try allocator.dupe(u8, remaining));
            break;
        }
    }
}

fn appendSpaces(list: *std.ArrayList(u8), allocator: Allocator, count: usize) !void {
    if (count == 0) return;
    const buf = try allocator.alloc(u8, count);
    defer allocator.free(buf);
    @memset(buf, ' ');
    try list.appendSlice(allocator, buf);
}

fn appendRepeatGlyph(list: *std.ArrayList(u8), allocator: Allocator, glyph: []const u8, count: usize) !void {
    if (count == 0) return;
    for (0..count) |_| try list.appendSlice(allocator, glyph);
}
