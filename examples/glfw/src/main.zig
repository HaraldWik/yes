const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var glfw_platform: yes.Platform.Glfw = try .init(allocator);
    defer glfw_platform.deinit();
    const platform = glfw_platform.platform();

    var glfw_window: yes.Platform.Glfw.Window = .{};
    const window = &glfw_window.interface;
    try window.open(platform, .{
        .title = "Window!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window.close(platform);

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("{any}", .{event}),
        };
    }
}
