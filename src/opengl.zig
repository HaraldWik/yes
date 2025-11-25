const std = @import("std");
const builtin = @import("builtin");
const Window = @import("window/Window.zig");
const native = @import("root.zig").native;

pub const wgl = @import("root.zig").native.win32.graphics.open_gl;
pub const glx = @import("root.zig").native.posix.x11;
pub const egl = @import("egl");

pub const APIENTRY: std.builtin.CallingConvention = if (builtin.os.tag == .windows) .winapi else .c;

pub const Proc = *const fn () callconv(APIENTRY) void;

pub fn getProcAddress(name: [*:0]const u8) ?Proc {
    return switch (native.os) {
        .windows => @ptrCast(wgl.wglGetProcAddress(name)),
        else => glx.glXGetProcAddress(name) orelse egl.eglGetProcAddress(name),
    };
}

/// set to null to remove the context
pub fn makeCurrent(window: ?Window) !void {
    if (window != null) switch (native.os) {
        .windows => if (wgl.wglMakeCurrent(window.?.handle.api.opengl.dc, window.?.handle.api.opengl.ctx) == wgl.GL_FALSE) return error.WglMakeCurrent,
        else => switch (window.?.handle) {
            .x11 => |handle| if (glx.glXMakeCurrent(handle.display, handle.window, handle.api.opengl.context) == glx.False) return error.GlxMakeCurrent,
            .wayland => |handle| if (egl.eglMakeCurrent(handle.api.opengl.display, handle.api.opengl.surface, handle.api.opengl.surface, handle.api.opengl.context) != egl.EGL_TRUE) return error.EglMakeCurrent,
        },
    } else switch (native.os) {
        .windows => _ = wgl.wglMakeCurrent(null, null),
        else => switch (window.?.handle) {
            .x11 => _ = glx.glXMakeCurrent(null, glx.None, null),
            .wayland => _ = egl.eglMakeCurrent(null, null, null, null),
        },
    }
}

pub fn swapBuffers(window: Window) !void {
    switch (native.os) {
        .windows => if (!native.win32.everything.SUCCEEDED(wgl.SwapBuffers(window.handle.api.opengl.dc))) return error.SwapBuffers,
        else => switch (window.handle) {
            .x11 => |handle| glx.glXSwapBuffers(@ptrCast(handle.display), handle.window),
            .wayland => |handle| {
                if (egl.eglSwapBuffers(handle.api.opengl.display, handle.api.opengl.surface) != egl.EGL_TRUE) return error.EglSwapBuffers;
                native.posix.wayland.client.wl_surface_commit(handle.surface);
                if (native.posix.wayland.client.wl_display_flush(handle.display) < 0) return error.FlushDisplay;
            },
        },
    }
}

pub fn swapInterval(window: Window, interval: i32) !void {
    switch (native.os) {
        .windows => if (window.handle.api.opengl.wgl.swapIntervalEXT(interval) == 0) return error.SwapInterval,
        else => switch (window.handle) {
            .x11 => {
                const glXSwapIntervalEXT: *const fn (display: *glx.Display, drawable: glx.Drawable, interval: c_int) callconv(.c) void = @ptrCast(glx.glXGetProcAddress("glXSwapIntervalEXT") orelse return error.SwapIntervalLoad);
                glXSwapIntervalEXT(window.handle.x11.display, window.handle.x11.window, @intCast(interval));
            },
            .wayland => if (egl.eglSwapInterval(window.handle.wayland.api.opengl.display, @intCast(interval)) != egl.EGL_TRUE) return error.SwapInterval,
        },
    }
}
