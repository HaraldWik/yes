const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{
        .title = "Title",
        .size = .{ .width = 900, .height = 600 },
    });
    defer window.close();

    const start_timestamp: std.time.Instant = try .now();

    main_loop: while (true) {
        while (try window.poll()) |event| {
            switch (event) {
                .close => break :main_loop,
                .resize => |size| {
                    const width, const height = window.getSize().toArray();
                    std.debug.print("width: {d} == {d}, height: {d} == {d}\n", .{ size.width, width, size.height, height });
                },
                .mouse => |mouse| switch (mouse) {
                    .button => |button| {
                        std.debug.print("'mouse button {t} {t}'\t", .{ button.code, button.state });
                        std.debug.print("({d}, {d})\n", .{ button.position.x, button.position.y });
                    },
                    .move => |pos| std.debug.print("moved: ({d}, {d})\n", .{ pos.x, pos.y }),
                    .scroll => |scroll| std.debug.print("scroll: {any}\n", .{scroll}),
                },

                .key => |key| {
                    std.debug.print("{t:<7} {t:<10} {d:3} {d:.3}\n", .{
                        key.state,
                        key.sym,
                        key.code,
                        @as(f32, @floatFromInt(@divTrunc((try std.time.Instant.now()).since(start_timestamp), std.time.ns_per_s / 10))) / 10.0,
                    });
                },
            }
        }
    }
}
