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
        .title = "Window!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
        .surface_type = .framebuffer,
    });
    defer window.close(desktop);

    main: while (true) {
        while (try window.poll(desktop)) |event| switch (event) {
            .close => break :main,
            .resize => |size| {
                std.log.info("resize: {d}x{d}", .{ size.width, size.height });
                const framebuffer = try window.framebuffer(desktop);
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
            .mouse_motion => {},
            else => std.log.info("{any}", .{event}),
        };
    }
}
