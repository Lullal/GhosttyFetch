const std = @import("std");
const types = @import("src/types.zig");
const config = @import("src/config.zig");
const frames = @import("src/frames.zig");
const sysinfo = @import("src/sysinfo.zig");
const ui = @import("src/ui.zig");
const shell = @import("src/shell.zig");

const Allocator = types.Allocator;
const clear_screen = types.clear_screen;
const config_file = types.config_file;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var exit_status: ?u8 = null;
    defer if (exit_status) |code| std.process.exit(code);

    const stdout_file = std.fs.File.stdout();
    const cfg = config.loadConfig(allocator) catch |err| {
        if (err == error.MissingConfig) {
            std.debug.print("Config file '{s}' is required. Please create it next to play_animation.zig.\n", .{config_file});
        }
        return err;
    };
    defer config.freeConfig(allocator, cfg);

    const term_size = types.TerminalSize.detect(stdout_file) catch
        types.TerminalSize{ .width = 120, .height = 40 };

    const layout = frames.calculateLayout(term_size);

    const fps = try config.resolveFps(allocator, cfg);
    const prefs = try config.colorPreferences(allocator, cfg, stdout_file.isTty(), fps);
    defer config.freeColorPreferences(allocator, prefs);

    const sysinfo_lines = try sysinfo.loadSystemInfoLines(allocator, cfg.sysinfo);
    defer sysinfo.freeSystemInfoLines(allocator, sysinfo_lines);

    const raw_frames = try frames.loadRawFrames(allocator);
    defer frames.freeFrames(allocator, raw_frames);

    const scaled_frames = try frames.scaleFramesForLayout(
        allocator,
        raw_frames,
        layout.art_width,
        layout.art_height,
    );
    defer frames.freeFrames(allocator, scaled_frames);

    const rendered_frames = try frames.renderFrames(allocator, scaled_frames, prefs);
    defer frames.freeFrames(allocator, rendered_frames);

    const styled_info = try ui.stylizeInfoLines(allocator, sysinfo_lines, layout.info_width, prefs);
    defer sysinfo.freeSystemInfoLines(allocator, styled_info);

    const frame_width = frames.maxFrameVisibleWidth(allocator, rendered_frames) catch 0;
    const info_start_col = frame_width + 4;
    const delay_ns = frames.fpsToDelayNs(fps);

    const info_colors = ui.resolveInfoColors(prefs);
    const prompt_prefix = try shell.buildPromptPrefix(allocator, prefs);
    defer allocator.free(prompt_prefix);

    var input_buffer = std.ArrayList(u8).empty;
    defer input_buffer.deinit(allocator);

    const stdin_file = std.fs.File.stdin();
    var term_mode = try shell.TerminalMode.enable(stdin_file);
    defer term_mode.restore();

    var submitted_command: ?[]u8 = null;
    defer if (submitted_command) |cmd| allocator.free(cmd);

    var keep_running = true;
    while (keep_running) {
        for (rendered_frames) |frame| {
            if (submitted_command == null) {
                submitted_command = try shell.captureInput(allocator, stdin_file, &input_buffer);
            }

            const prompt_line = try shell.renderPromptLine(allocator, prompt_prefix, input_buffer.items, info_colors);
            defer allocator.free(prompt_line);

            const combined = try ui.combineFrameAndInfo(allocator, frame, styled_info, info_start_col);
            defer allocator.free(combined);

            const with_prompt = try ui.appendPromptLines(allocator, combined, prompt_line);
            defer allocator.free(with_prompt);

            try stdout_file.writeAll(clear_screen);
            try stdout_file.writeAll(with_prompt);

            if (submitted_command != null) {
                keep_running = false;
                break;
            }

            std.Thread.sleep(delay_ns);
        }
    }

    term_mode.restore();

    if (submitted_command) |cmd| {
        const command = std.mem.trim(u8, cmd, " \t\r\n");
        if (command.len == 0) return;

        try stdout_file.writeAll(clear_screen);
        try stdout_file.writeAll(prompt_prefix);
        try stdout_file.writeAll(command);
        try stdout_file.writeAll("\n");

        const code = try shell.runCommandInShell(allocator, command);
        exit_status = @as(u8, @intCast(code));
    }
}
