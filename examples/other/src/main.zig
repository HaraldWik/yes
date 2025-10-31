const std = @import("std");
const yes = @import("yes");
const gl = @import("opengl");

pub fn main() !void {
    const window: yes.Window = try .open(.{
        .title = "Title",
        .width = 900,
        .height = 600,
        .renderer = .opengl,
    });
    defer window.close();

    try gl.init(yes.opengl.getProcAddress);

    while (window.next()) |event| {
        _ = event;

        gl.clear.buffer(.{ .color = true });
        gl.clear.color(0.1, 0.4, 0.5, 1.0);

        if (window.isKeyDown(.a)) {
            gl.clear.color(1.0, 0.4, 0.5, 1.0);
        }
        if (window.isKeyDown(.escape)) std.debug.print("ESC\n", .{});
        if (window.isKeyDown(.left_ctrl)) std.debug.print("LCTRL\n", .{});

        yes.opengl.swapBuffers(window);
    } else std.debug.print("Exit!\n", .{});
}
