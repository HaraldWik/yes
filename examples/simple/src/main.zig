const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    out: while (true) {
        while (try window.poll()) |event| {
            switch (event) {
                .close => break :out,
                .resize => |size| {
                    const width, const height = size;
                    const width2, const height2 = window.getSize();
                    std.debug.print("width: {d} == {d}, height: {d} == {d}\n", .{ width, width2, height, height2 });
                },
                .mouse => |mouse| {
                    inline for (@typeInfo(yes.Mouse).@"struct".fields) |field| {
                        if (field.type == bool and @field(mouse, field.name))
                            std.debug.print("mouse {s}\n", .{field.name});
                    }
                },
            }
        }

        if (window.isKeyDown(.a)) std.debug.print("A\n", .{});
    } else std.debug.print("Exit!\n", .{});
}
