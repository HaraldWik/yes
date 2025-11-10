const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    out: while (true) {
        while (try window.poll()) |event| {
            std.debug.print("{s}\t", .{@tagName(event)});
            switch (event) {
                .close => break :out,
                .resize => |size| {
                    const width, const height = window.getSize();
                    std.debug.print("width: {d} == {d}, height: {d} == {d}\n", .{ size[0], width, size[1], height });
                },
                .mouse => |mouse| {
                    inline for (@typeInfo(yes.Mouse).@"struct".fields) |field| {
                        if (@field(mouse, field.name))
                            std.debug.print("{s}\n", .{field.name});
                    }
                },
            }
        }

        if (window.isKeyDown(.a)) std.debug.print("A\n", .{});
    } else std.debug.print("Exit!\n", .{});
}
