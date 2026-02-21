const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var platform_impl = impl: switch (builtin.os.tag) {
        .windows, .wasi => try yes.Platform.Win32.get(allocator),
        else => {
            var xpz_platform: yes.Platform.Xpz = undefined;
            try xpz_platform.init(io, init.minimal);
            break :impl xpz_platform;
        },
    };
    defer switch (builtin.os.tag) {
        .windows, .wasi => {},
        else => platform_impl.deinit(io),
    };

    const platform = platform_impl.platform();

    var window_impl = switch (builtin.os.tag) {
        .windows, .wasi => yes.Platform.Win32.Window{},
        else => yes.Platform.Xpz.Window{},
    };
    const window = &window_impl.interface;
    try window.open(platform, .{
        .title = "Lucas",
        .size = .{ .width = 600, .height = 400 },
    });
    defer window.close(platform);

    try window.setTitle(platform, "Big window?");

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| std.log.info("resize: {d}x{d}", .{ size.width, size.height }),
            .focus => |focus| std.log.info("focus: {t}", .{focus}),
        };
    }
}
