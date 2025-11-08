const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    // next returns null on exit
    while (window.next()) |event| {
        switch (event) {
            .resize => |size| std.debug.print("width: {d}, height: {d}\n", .{ size[0], size[1] }),
            else => {},
        }
        if (window.isKeyDown(.a)) std.debug.print("A\n", .{});
    } else std.debug.print("Exit!\n", .{});
}
