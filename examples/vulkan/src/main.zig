const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    var window: yes.Window = try .open(.{
        .title = "Title",
        .size = .{ .width = 900, .height = 600 },
        .api = .{ .vulkan = .{} },
    });
    defer window.close();

    if (!yes.vulkan.isSupported()) return error.VulkanUnsupported;

    main_loop: while (true) {
        while (try window.poll()) |event| switch (event) {
            .close => break :main_loop,
            else => {},
        };
    }
}
