const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

// example args "zig build run -- --xdg=x11"

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
        .min_size = .{ .width = 300, .height = 200 },
        .max_size = .{ .width = 900, .height = 600 },
    });
    defer window.close(platform);

    var fullscreen: bool = false;
    var maximize: bool = false;
    var minimize: bool = false;

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| std.log.info("resize: {d} x {d}", .{ size.width, size.height }),
            .move => |position| std.log.info("move: {d} x {d}", .{ position.x, position.y }),
            .focus => |focus| {
                std.log.info("focus: {t}", .{focus});
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
                    try window.setMaximize(platform, fullscreen);
                }
                if (key.sym == .n) {
                    minimize = !minimize;
                    try window.setMinimize(platform, fullscreen);
                }
            },
            .mouse_move => {},
            .mouse_button => |button| {
                std.log.info("{t:<8} mouse button {t:<8} at {d} x {d}", .{ button.state, button.type, button.position.x, button.position.y });
                if (button.state == .pressed and button.type == .left)
                    try window.setTitle(platform, "Window! 👺🌶️🫑");
                if (button.state == .pressed and button.type == .right)
                    try window.setTitle(platform, "Window 🇸🇪");

                if (button.state == .released and button.type == .middle) {
                    fullscreen = !fullscreen;
                    try window.setFullscreen(platform, fullscreen);
                }
            },
            .mouse_scroll => |scroll| {
                std.log.info("mouse scroll: {t}: {d:2}", .{ scroll, switch (scroll) {
                    .x => scroll.x,
                    .y => scroll.y,
                } });
            },
        };
    }
}
