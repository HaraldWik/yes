const std = @import("std");
const yes = @import("yes");

// example args "zig build run -- --xdg=wayland"
// example args "zig build run -- --xdg=x11"
// if none are selected it will detect it in yes.Desktop.unix.SessionType

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var cross_desktop: yes.Desktop.Cross = try .init(gpa, io, init.minimal);
    defer cross_desktop.deinit();
    const desktop = cross_desktop.desktop();

    var cross_window: yes.Desktop.Cross.Window = .empty(desktop);
    const window = cross_window.interface(desktop);
    try window.open(desktop, .{
        .title = "Window!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window.close(desktop);

    main: while (true) {
        while (try window.poll(desktop)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("{any}", .{event}),
        };
    }
}
