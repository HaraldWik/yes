const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{
        .title = "Title",
        .size = .{ .width = 900, .height = 600 },
    });
    defer window.close();

    main_loop: while (true) {
        while (try window.poll()) |event| {
            switch (event) {
                .close => break :main_loop,
                .resize => |size| {
                    const width, const height = window.getSize().toArray();
                    std.debug.print("width: {d} == {d}, height: {d} == {d}\n", .{ size.width, width, size.height, height });
                },
                .mouse => |mouse| switch (mouse) {
                    .click_down => |click| {
                        std.debug.print("'{t} mouse' down\t", .{click.button});
                        std.debug.print("({d}, {d})\n", .{ click.position.x, click.position.y });
                    },
                    .click_up => |click| {
                        std.debug.print("'{t} mouse' up  \t", .{click.button});
                        std.debug.print("({d}, {d})\n", .{ click.position.x, click.position.y });
                    },
                    .move => |pos| std.debug.print("moved: ({d}, {d})\n", .{ pos.x, pos.y }),
                },

                .key_down => |key| std.debug.print("'{t}' down\n", .{key}),
                .key_up => |key| std.debug.print("'{t}' up\n", .{key}),
            }
        }
    }
}
