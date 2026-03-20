const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
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
    if (!build_options.opengl) invalid();
    return platform.vtable.openglGetProcAddress;
}

pub fn makeCurrent(platform: Platform, window: *Platform.Window) !void {
    if (!build_options.opengl) invalid();
    if (window.surface_type != .opengl) return error.WrongSurfaceType;
    try platform.vtable.windowOpenglMakeCurrent(platform.ptr, window);
}

pub fn swapBuffers(platform: Platform, window: *Platform.Window) !void {
    if (!build_options.opengl) invalid();
    if (window.surface_type != .opengl) return error.WrongSurfaceType;
    try platform.vtable.windowOpenglSwapBuffers(platform.ptr, window);
}

pub fn swapInterval(platform: Platform, window: *Platform.Window, interval: i32) !void {
    if (!build_options.opengl) invalid();
    if (window.surface_type != .opengl) return error.WrongSurfaceType;
    try platform.vtable.windowOpenglSwapInterval(platform.ptr, window, interval);
}

fn invalid() callconv(.c) void {
    std.debug.panic("attempted to call native GLX or EGL function while OpenGL build option is set to false", .{});
}

comptime {
    if (build_options.xlib and !build_options.opengl) {
        @export(&invalid, .{ .name = "glXGetProcAddress" });
        @export(&invalid, .{ .name = "glXQueryExtensionsString" });
        @export(&invalid, .{ .name = "glXChooseFBConfig" });
        @export(&invalid, .{ .name = "glXGetVisualFromFBConfig" });
        @export(&invalid, .{ .name = "glXGetProcAddressARB" });
        @export(&invalid, .{ .name = "glXDestroyContext" });
        @export(&invalid, .{ .name = "glXMakeCurrent" });
        @export(&invalid, .{ .name = "glXSwapBuffers" });
    }

    if (build_options.libwayland and !build_options.opengl) {
        @export(&invalid, .{ .name = "eglGetProcAddress" });
        @export(&invalid, .{ .name = "eglGetDisplay" });
        @export(&invalid, .{ .name = "eglInitialize" });
        @export(&invalid, .{ .name = "eglBindAPI" });
        @export(&invalid, .{ .name = "eglChooseConfig" });
        @export(&invalid, .{ .name = "eglCreateContext" });
        @export(&invalid, .{ .name = "wl_egl_window_create" });
        @export(&invalid, .{ .name = "eglCreateWindowSurface" });
        @export(&invalid, .{ .name = "eglSwapBuffers" });
        @export(&invalid, .{ .name = "eglDestroySurface" });
        @export(&invalid, .{ .name = "wl_egl_window_destroy" });
        @export(&invalid, .{ .name = "eglDestroyContext" });
        @export(&invalid, .{ .name = "eglTerminate" });
        @export(&invalid, .{ .name = "wl_egl_window_resize" });
        @export(&invalid, .{ .name = "eglMakeCurrent" });
        @export(&invalid, .{ .name = "eglSwapInterval" });
    }
}
