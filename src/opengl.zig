const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const native = @import("root.zig").native;

pub const wgl = @import("root.zig").native.win32.graphics.open_gl;
pub const glx = struct {
    pub const Drawable = c_ulong;
    pub const PFNGLXSWAPINTERVALEXT = *const fn (display: *native.posix.x11.Display, drawable: Drawable, interval: c_int) callconv(.c) void;

    extern fn glXGetProcAddress(name: [*:0]const u8) ?Proc;
    extern fn glXSwapBuffers(display: *native.posix.x11.Display, drawable: Drawable) void;
};
pub const egl = @import("egl");

pub const APIENTRY: std.builtin.CallingConvention = if (builtin.os.tag == .windows) .winapi else .c;

pub const Proc = *const fn () callconv(APIENTRY) void;

pub fn getProcAddress(name: [*:0]const u8) ?Proc {
    return switch (native.os) {
        .windows => @ptrCast(wgl.wglGetProcAddress(name)),
        else => glx.glXGetProcAddress(name) orelse egl.eglGetProcAddress(name),
    };
}

pub fn swapBuffers(window: root.Window) !void {
    switch (native.os) {
        .windows => if (!native.win32.everything.SUCCEEDED(wgl.SwapBuffers(window.handle.api.opengl.dc))) return error.SwapBuffers,
        else => switch (window.handle) {
            .x11 => glx.glXSwapBuffers(@ptrCast(window.handle.x11.display), window.handle.x11.window),
            .wayland => {
                if (egl.eglSwapBuffers(window.handle.wayland.api.opengl.display, window.handle.wayland.api.opengl.surface) != egl.EGL_TRUE) return error.EglSwapBuffers;
                native.posix.wayland.client.wl_surface_commit(window.handle.wayland.surface);
                if (native.posix.wayland.client.wl_display_flush(window.handle.wayland.display) < 0) return error.FlushDisplay;
            },
        },
    }
}

pub fn swapInterval(window: root.Window, interval: i32) !void {
    switch (native.os) {
        .windows => if (window.handle.api.opengl.wgl.swapIntervalEXT(interval) == 0) return error.SwapInterval,
        else => switch (window.handle) {
            .x11 => {
                const glXSwapIntervalEXT: glx.PFNGLXSWAPINTERVALEXT = @ptrCast(glx.glXGetProcAddress("glXSwapIntervalEXT") orelse return error.SwapIntervalLoad);
                glXSwapIntervalEXT(window.handle.x11.display, window.handle.x11.window, @intCast(interval));
            },
            .wayland => if (egl.eglSwapInterval(window.handle.wayland.api.opengl.display, @intCast(interval)) != egl.EGL_TRUE) return error.SwapInterval,
        },
    }
}
