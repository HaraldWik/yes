const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("Platform.zig");

pub const APIENTRY: std.builtin.CallingConvention = if (builtin.os.tag == .windows) .winapi else .c;

pub const Proc = switch (builtin.os.tag) {
    .windows => *const fn () callconv(.winapi) isize,
    else => *const fn () callconv(.c) void,
};

pub const Version = packed struct(u16) { major: u8, minor: u8 };

pub extern "opengl32" fn wglGetProcAddress(param0: [*:0]const u8) callconv(.winapi) ?Proc;
pub extern "glx" fn glXGetProcAddress(procname: [*:0]const u8) callconv(.c) ?Proc;
pub extern "egl" fn eglGetProcAddress(procname: [*:0]const u8) callconv(.c) ?Proc;

pub fn getProcAddressProc(platform: Platform) *const fn (procname: [*:0]const u8) callconv(APIENTRY) ?Proc {
    return platform.vtable.openglGetProcAddress;
}

pub fn makeCurrent(platform: Platform, window: *Platform.Window) !void {
    if (window.surface_type != .opengl) return error.WrongSurfaceType;
    try platform.vtable.windowOpenglMakeCurrent(platform.ptr, window);
}

pub fn swapBuffers(platform: Platform, window: *Platform.Window) !void {
    if (window.surface_type != .opengl) return error.WrongSurfaceType;
    try platform.vtable.windowOpenglSwapBuffers(platform.ptr, window);
}

pub fn swapInterval(platform: Platform, window: *Platform.Window, interval: i32) !void {
    if (window.surface_type != .opengl) return error.WrongSurfaceType;
    try platform.vtable.windowOpenglSwapInterval(platform.ptr, window, interval);
}
