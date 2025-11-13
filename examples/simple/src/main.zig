const std = @import("std");
const yes = @import("yes");

pub fn main() !void {
    const window: yes.Window = try .open(.{ .title = "Title", .width = 900, .height = 600 });
    defer window.close();

    // if (yes.file_dialog.open()) |file_path| {
    //     try yes.clipboard.setAlloc(window, std.heap.page_allocator, file_path);
    // }

    // const got = yes.clipboard.getAlloc(window, std.heap.page_allocator) orelse "what";
    // std.debug.print("{s}\n", .{got});
    // std.heap.page_allocator.free(got);

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
                    inline for (@typeInfo(yes.Event.Mouse).@"struct".fields) |field| {
                        if (field.type == bool and @field(mouse, field.name))
                            std.debug.print("mouse {s}\n", .{field.name});
                    }
                },
                .key_down => |key| std.debug.print("'{t}' down\n", .{key}),
                .key_up => |key| std.debug.print("'{t}' up\n", .{key}),
            }
        }
    } else std.debug.print("Exit!\n", .{});
}
