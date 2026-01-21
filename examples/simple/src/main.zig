const std = @import("std");
const yes = @import("yes");

pub fn main(init: std.process.Init.Minimal) !void {
    const context: yes.Context = .get(init);

    var buffer: [128]u8 = undefined;
    var it: yes.Monitor.Iterator = .init(context, &buffer);
    while (it.next() catch null) |monitor| {
        std.debug.print("monitor: {s}\n\tsize: {any}, physical size: {any}\n\tposition: {any}\n\tscale: {d:.3}\n\torientation: {t}\n", .{
            monitor.name orelse "unknown",
            monitor.size,
            monitor.physical_size,
            monitor.position,
            monitor.scale,
            monitor.orientation,
        });
    }
    std.debug.print("\n", .{});

    const monitor: yes.Monitor = .primary(context, &buffer);

    var window: yes.Window = try .open(context, .{
        .title = "Title 😀✅♥",
        .size = .{ .width = 900, .height = 600 },
        .decoration = true,
    });
    defer window.close();
    try window.setPosition(monitor.position);

    const start_timestamp: std.time.Instant = try .now();

    var is_fullscreen: bool = false;
    var is_maximize: bool = false;
    main_loop: while (true) {
        while (try window.poll()) |event| switch (event) {
            .close => break :main_loop,
            .focus => |focus| std.debug.print("Focus {t}\n", .{focus}),
            .resize => |size| {
                const width, const height = window.getSize().toArray();
                std.debug.print("width: {d} == {d}, height: {d} == {d}\n", .{ size.width, width, size.height, height });
            },
            .mouse => |mouse| switch (mouse) {
                .button => |button| {
                    std.debug.print("'mouse button {t} {t}'\t", .{ button.code, button.state });
                    std.debug.print("({d}, {d})\n", .{ button.position.x, button.position.y });
                },
                .move => |pos| {
                    if (window.keyboard.get(.@"1") == .pressed) std.debug.print("moved: ({d}, {d})\n", .{ pos.x, pos.y });
                },
                .scroll => |scroll| std.debug.print("scroll: {any}\n", .{scroll}),
            },
            .key => |key| {
                std.debug.print("{t:<7} {t:<10} {d:3} {d:.3}\n", .{
                    key.state,
                    key.sym,
                    key.code,
                    @as(f32, @floatFromInt(@divTrunc((try std.time.Instant.now()).since(start_timestamp), std.time.ns_per_s / 10))) / 10.0,
                });

                if (key.state == .released) switch (key.sym) {
                    .f => {
                        is_fullscreen = !is_fullscreen;
                        window.fullscreen(is_fullscreen);
                    },
                    .m => {
                        is_maximize = !is_maximize;
                        window.maximize(is_maximize);
                    },
                    .n => window.minimize(),
                    .t => window.setTitle("You pressed T!"),
                    else => {},
                };
            },
        };

        if (window.keyboard.get(.escape) == .pressed) break;
    }
}
