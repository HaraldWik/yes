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
        .title = "Window B!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
        .surface_type = .framebuffer,
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
        .surface_type = .framebuffer,
    });
    defer window_b.close(platform);
    try window_b.setCursor(platform, .wait);

    var scroll_x: usize = 0;
    var scroll_y: usize = 0;

    main: while (true) {
        while (try window_a.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| {
                std.log.info("a: resize: {d}x{d}", .{ size.width, size.height });
                const framebuffer = try window_a.framebuffer(platform);
                const format = yes.Window.Framebuffer.format;

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
            else => std.log.info("a: {any}", .{event}),
        };

        while (try window_b.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| {
                std.log.info("b: resize: {d}x{d}", .{ size.width, size.height });
                const framebuffer = try window_b.framebuffer(platform);
                const format = yes.Window.Framebuffer.format;
                const block_size: usize = 20;

                for (0..size.height) |y| {
                    const by = (y + scroll_y) / block_size;

                    for (0..size.width) |x| {
                        const bx = (x + scroll_x) / block_size;
                        const i = y * size.width + x;
                        const offset = i * 4;

                        const checker = (bx + by) % 2 == 0;

                        framebuffer.pixels[offset + format.r] = if (checker) 240 else 30;
                        framebuffer.pixels[offset + format.g] = if (checker) 240 else 30;
                        framebuffer.pixels[offset + format.b] = if (checker) 240 else 30;
                        framebuffer.pixels[offset + format.a] = 255;
                    }
                }
            },
            .move => |position| {
                scroll_x = @intCast(@abs(position.x));
                scroll_y = @intCast(@abs(position.y));
            },
            else => std.log.info("b: {any}", .{event}),
        };
    }
}
