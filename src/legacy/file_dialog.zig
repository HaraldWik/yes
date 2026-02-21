const std = @import("std");
const root = @import("root.zig");
const native = @import("root.zig").native;
const win32 = @import("root.zig").native.win32.everything;

pub fn open() ?[:0]u8 {
    switch (native.os) {
        .windows => {
            var file_path: [win32.MAX_PATH]u8 = @splat(0);
            var dialog: win32.OPENFILENAMEA = std.mem.zeroInit(win32.OPENFILENAMEA, .{
                .lpstrTitle = "Title!",
                .lpstrFilter = "png files\x00*.png\x00, jpg files\x00*.jpg\x00", // "\x00" if empty
                .nMaxFile = @as(u32, @intCast(file_path.len)),
                .lpstrFile = @as(?[*:0]u8, @ptrCast(&file_path)),
            });

            if (!win32.SUCCEEDED(win32.GetOpenFileNameA(&dialog))) {
                const err = win32.CommDlgExtendedError();
                if (err != .CDERR_GENERALCODES) std.log.err("GetOpenFileName failed: {s}", .{@tagName(err)});
                return null;
            }

            return file_path[0 .. std.mem.indexOfScalar(u8, &file_path, 0) orelse file_path.len :0];
        },
        else => {
            @compileError("unsupported");
        },
    }
}
