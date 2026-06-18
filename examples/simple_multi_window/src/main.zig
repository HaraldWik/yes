const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_desktop: yes.Desktop.Cross = try .init(allocator, io, init.minimal);
    defer cross_desktop.deinit();
    const desktop = cross_desktop.desktop();

    var cross_window_a: yes.Desktop.Cross.Window = .empty(desktop);
    const window_a = cross_window_a.interface(desktop);
    try window_a.open(desktop, .{
        .title = "Window A!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window_a.close(desktop);

    var cross_window_b: yes.Desktop.Cross.Window = .empty(desktop);
    const window_b = cross_window_b.interface(desktop);
    try window_b.open(desktop, .{
        .title = "Window B!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window_b.close(desktop);

    main: while (true) {
        while (try window_a.poll(desktop)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("a: {any}", .{event}),
        };
        while (try window_b.poll(desktop)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("b: {any}", .{event}),
        };
    }
}
