const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform = switch (builtin.os.tag) {
        .windows => try yes.Platform.Win32.get(allocator),
        else => platform: {
            var xpz: yes.Platform.Xpz = undefined;
            try xpz.init(io, init.minimal);
            break :platform xpz;
        },
    };
    defer switch (builtin.os.tag) {
        .windows => {},
        else => cross_platform.deinit(io),
    };

    const platform = cross_platform.platform();

    var cross_window: switch (builtin.os.tag) {
        .windows => yes.Platform.Win32.Window,
        else => yes.Platform.Xpz.Window,
    } = .{};
    const window = &cross_window.interface;
    try window.open(platform, .{
        .title = "Window 🇸🇪",
        .size = .{ .width = 600, .height = 400 },
    });
    defer window.close(platform);

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| std.log.info("resize: {d}x{d}", .{ size.width, size.height }),
            .focus => |focus| {
                std.log.info("focus: {t}", .{focus});
            },
            .key => |key| {
                std.log.info("{t:<8} {t}", .{ key.state, key.sym });
                if (key.state == .released and key.sym == .enter)
                    try window.setTitle(platform, "Window! 👺🌶️🫑");
            },
        };
    }
}
