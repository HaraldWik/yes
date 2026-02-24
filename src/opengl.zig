const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("Platform.zig");

pub const APIENTRY: std.builtin.CallingConvention = if (builtin.os.tag == .windows) .winapi else .c;

pub const Proc = switch (builtin.os.tag) {
    .windows => *const fn () callconv(.winapi) isize,
    else => *const fn () callconv(.c) void,
};

extern "opengl32" fn wglGetProcAddress(
    param0: [*:0]const u8,
) callconv(.winapi) ?Proc;

pub fn getProcAddress(name: [*:0]const u8) ?Proc {
    return switch (builtin.os.tag) {
        .windows => proc: {
            const win32 = @import("win32").everything;
            if (wglGetProcAddress(name)) |proc| break :proc @ptrCast(proc);
            const gl = win32.LoadLibraryA("opengl32.dll") orelse return null;
            if (win32.GetProcAddress(gl, name)) |proc| break :proc @ptrCast(proc);
            break :proc null;
        },
        else => null,
        // glx.glXGetProcAddress(name) orelse egl.eglGetProcAddress(name),
    };
}

pub fn makeCurrent(platform: Platform, window: *Platform.Window) !void {
    try platform.vtable.windowOpenglMakeCurrent(platform.ptr, window);
}

pub fn swapBuffers(platform: Platform, window: *Platform.Window) !void {
    try platform.vtable.windowOpenglSwapBuffers(platform.ptr, window);
}

pub fn swapInterval(platform: Platform, window: *Platform.Window, interval: i32) !void {
    try platform.vtable.windowOpenglSwapInterval(platform.ptr, window, interval);
}
