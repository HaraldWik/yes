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
        .title = "Window!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
        .surface_type = .framebuffer,
    });
    defer window.close(platform);

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| {
                const framebuffer = try window.framebuffer(platform);
                const format = yes.Platform.Window.Framebuffer.format;

                for (0..size.width * size.height) |i| {
                    const x = i % size.width;
                    const y = i / size.width;
                    const offset = i * 4;
                    framebuffer.pixels[offset + format.r] = @intCast(x * 255 / size.width);
                    framebuffer.pixels[offset + format.g] = @intCast(y * 255 / size.height);
                    framebuffer.pixels[offset + format.b] = 128;
                    framebuffer.pixels[offset + format.a] = 255;
                }
            },
            else => std.log.info("{any}", .{event}),
        };
    }
}
