const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    // next returns null on exit
    while (window.next()) |event| {
        _ = event;
        const width: usize, const height: usize = window.getSize();
        if (window.isKeyDown(.a)) std.debug.print("A, ", .{});
        std.debug.print("Size {d} {d}\r", .{ width, height });
    } else std.debug.print("\x1b[2K{s}\n", .{"Exit!"});
}
