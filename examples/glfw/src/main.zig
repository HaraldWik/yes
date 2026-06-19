const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var glfw: yes.Desktop.Glfw = try .init(gpa);
    defer glfw.deinit();
    const desktop = glfw.desktop();

    var glfw_window: yes.Desktop.Glfw.Window = .{};
    const window = &glfw_window.interface;
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
