const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform: yes.Desktop.Cross = try .init(allocator, io, init.minimal);
    defer cross_platform.deinit();
    const desktop = cross_platform.desktop();

    var cross_window: yes.Desktop.Cross.Window = .empty(desktop);
    const window = cross_window.interface(desktop);
    try window.open(desktop, .{
        .title = "Window!",
        .size = .{ .width = 600, .height = 400 },
        .resize_policy = .{
            .specified = .{
                .min_size = .{ .width = 300, .height = 200 },
            },
        },
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
            .drag_motion => {},
            .drag_drop => |drop| {
                var buf: [256]u8 = undefined;
                const read = buf[0..@intCast(std.posix.system.read(drop.fd, &buf, buf.len))];
                std.debug.print("drop:\n{s}\n", .{read});
            },
            else => std.log.info("{any}", .{event}),
        };

        const wayland: *yes.Desktop.Wayland = @ptrCast(@alignCast(desktop.userdata.?));

        if (wayland.io_manager.clipboard.fd != 0) {
            const fd = wayland.io_manager.clipboard.fd;
            var buffer: [128]u8 = undefined;
            const read = buffer[0..@intCast(try std.posix.read(fd, &buffer))];
            std.log.info("clipboard:\n{s}", .{std.mem.trimEnd(u8, read, "\n\r")});

            wayland.io_manager.clipboard.fd = 0;
        }

        if (wayland.io_manager.clipboard.offer) |offer| {
            var fds: [2]std.posix.fd_t = undefined;
            _ = std.posix.system.pipe(&fds);

            const read_fd = fds[0];
            const write_fd = fds[1];

            offer.receive("text/plain;charset=utf-8", write_fd);
            _ = std.posix.system.close(write_fd);

            wayland.io_manager.clipboard.fd = read_fd;
            wayland.io_manager.clipboard.offer = null;
        }
    }
}
