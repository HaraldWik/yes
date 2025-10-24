const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    // next returns null on exit
    while (window.next()) |event| {
        _ = event;
    } else std.debug.print("Exit!\n", .{});
}
