const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    while (window.next()) |event| {
        _ = event;
        if (window.isKeyDown(.a)) std.debug.print("A\n", .{});
        if (window.isKeyDown(.escape)) std.debug.print("ESC\n", .{});
        if (window.isKeyDown(.left_ctrl)) std.debug.print("LCTRL\n", .{});
    } else std.debug.print("Exit!\n", .{});
}
