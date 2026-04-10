const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform: yes.Platform.Cross = try .init(allocator, io, init.minimal);
    defer cross_platform.deinit();
    const platform = cross_platform.platform();

    var cross_window_a: yes.Platform.Cross.Window = .empty(platform);
    const window_a = cross_window_a.interface(platform);
    try window_a.open(platform, .{
        .title = "Window A!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window_a.close(platform);

    var cross_window_b: yes.Platform.Cross.Window = .empty(platform);
    const window_b = cross_window_b.interface(platform);
    try window_b.open(platform, .{
        .title = "Window B!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
    });
    defer window_b.close(platform);

    main: while (true) {
        while (try window_a.poll(platform)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("a: {any}", .{event}),
        };
        while (try window_b.poll(platform)) |event| switch (event) {
            .close => break :main,
            else => std.log.info("b: {any}", .{event}),
        };
    }
}
