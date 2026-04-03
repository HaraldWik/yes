const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform: yes.Platform.Cross = try .init(allocator, io, init.minimal);
    defer cross_platform.deinit();
    const platform = cross_platform.platform();

    var cross_window: yes.Platform.Cross.Window = .empty(platform);
    const window = cross_window.interface(platform);
    try window.open(platform, .{
        .title = "Window 🇸🇪👺🌶️🫑",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .max_size = .{ .width = 900, .height = 600 },
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window.close(platform);
    try window.setAlwaysOnTop(platform, true);
    try window.setFloating(platform, true);

    var fullscreen: bool = false;
    var maximize: bool = false;
    var minimize: bool = false;

    var cursor_index: usize = 0;
    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| std.log.info("resize: {d} x {d}", .{ size.width, size.height }),
            .move => |position| std.log.info("move: {d} x {d}", .{ position.x, position.y }),
            .focus => |focus| {
                std.log.info("focus: {}", .{focus});
            },
            .key => |key| {
                std.log.info("{t:<8} {t}", .{ key.state, key.sym });
                if (key.state != .released) continue;

                if (key.sym == .enter)
                    try window.setTitle(platform, "You pressed enter!");

                if (key.sym == .f) {
                    fullscreen = !fullscreen;
                    try window.setFullscreen(platform, fullscreen);
                }
                if (key.sym == .m) {
                    maximize = !maximize;
                    try window.setMaximized(platform, fullscreen);
                }
                if (key.sym == .n) {
                    minimize = !minimize;
                    try window.setMinimized(platform, fullscreen);
                }
                if (key.sym == .r)
                    try window.setResizePolicy(platform, .{ .resizable = true });
            },
            .mouse_button => |button| {
                if (button.state == .pressed and button.button == .left) {
                    cursor_index += 1;
                    const cursor: yes.Window.Cursor = switch (cursor_index) {
                        0 => .arrow,
                        1 => .text,
                        2 => .hand,
                        3 => .grab,
                        4 => .crosshair,
                        5 => .wait,
                        6 => .resize_ns,
                        7 => .resize_ew,
                        8 => .resize_nesw,
                        9 => .resize_nwse,
                        10 => .forbidden,
                        11 => .move,
                        else => blk: {
                            cursor_index = 0;
                            break :blk .arrow;
                        },
                    };
                    try window.setCursor(platform, cursor);
                }
            },
            .mouse_motion => {},
            else => std.log.info("{any}", .{event}),
        };
    }
}
