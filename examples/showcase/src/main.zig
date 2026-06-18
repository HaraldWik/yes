const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_desktop: yes.Desktop.Cross = try .init(allocator, io, init.minimal);
    defer cross_desktop.deinit();
    const desktop = cross_desktop.desktop();

    var cross_window: yes.Desktop.Cross.Window = .empty(desktop);
    const window = cross_window.interface(desktop);
    try window.open(desktop, .{
        .title = "Window 🇸🇪👺🌶️🫑",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .max_size = .{ .width = 900, .height = 600 },
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window.close(desktop);
    try window.setAlwaysOnTop(desktop, true);
    try window.setFloating(desktop, true);

    var cursor_index: usize = 0;
    main: while (true) {
        while (try window.poll(desktop)) |event| switch (event) {
            .close => break :main,
            .resize => |size| std.log.info("resize: {d} x {d}", .{ size.width, size.height }),
            .move => |position| std.log.info("move: {d} x {d}", .{ position.x, position.y }),
            .focus => |focus| {
                std.log.info("focus: {}", .{focus});
            },
            .key => |key| {
                std.log.info("{t:<8} {t}", .{ key.state, key.sym });
                if (key.state != .released) continue;

                if (key.sym == .enter) try window.setTitle(desktop, "You pressed enter!");
                if (key.sym == .f1) try window.setMode(desktop, .windowed);
                if (key.sym == .f2) try window.setMode(desktop, .fullscreen);
                if (key.sym == .f3) try window.setMode(desktop, .maximized);
                if (key.sym == .f4) try window.setMode(desktop, .minimized);

                if (key.sym == .r)
                    try window.setResizePolicy(desktop, .{ .resizable = true });
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
                    try window.setCursor(desktop, cursor);
                }
            },
            .mouse_motion => {},
            else => std.log.info("{any}", .{event}),
        };
    }
}
