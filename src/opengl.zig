const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const native = @import("root.zig").native;

pub const wgl = @import("root.zig").native.win32.graphics.open_gl;
pub const glx = struct {
    pub const Drawable = c_ulong;
    pub const PFNGLXSWAPINTERVALEXT = *const fn (display: *native.x.Display, drawable: Drawable, interval: c_int) callconv(.c) void;

    extern fn glXGetProcAddress(name: [*:0]const u8) ?Proc;
    extern fn glXSwapBuffers(display: *native.x.Display, drawable: Drawable) void;
};
pub const egl = struct {
    pub const FALSE = 0;
    extern fn eglGetProcAddress(name: [*:0]const u8) ?Proc;
    extern fn eglSwapBuffers(display: *anyopaque, surface: *anyopaque) c_uint;
    extern fn eglSwapInterval(display: *anyopaque, interval: c_int) i32;
    extern fn eglGetError() i32;
};

pub const Proc = *const fn () callconv(.c) void;

pub fn getProcAddress(name: [*:0]const u8) ?Proc {
    return switch (native.os) {
        .windows => @ptrCast(wgl.wglGetProcAddress(name) orelse {
            // Always try wglGetProcAddress first \u2014 this is how you get all 1.2+ functions
            const ptr = wgl.wglGetProcAddress(name);
            const ptr_address = @intFromPtr(ptr);
            if (ptr != null and ptr_address != 1 and ptr_address != 2 and ptr_address != 3 and ptr_address != -1)
                return @ptrCast(ptr);

            return null;

            // std.debug.print("{s}\n", .{name});

            // const module = win32.GetModuleHandleW(win32.L("opengl32.dll")) orelse return null;
            // return @ptrCast(win32.GetProcAddress(module, name));
        }),
        else => glx.glXGetProcAddress(name) orelse egl.eglGetProcAddress(name),
    };
}

pub fn swapBuffers(window: root.Window) !void {
    switch (native.os) {
        .windows => _ = wgl.SwapBuffers(window.handle.api.opengl.dc),
        else => switch (window.handle) {
            .x => glx.glXSwapBuffers(@ptrCast(window.handle.x.display), window.handle.x.window),
            .wayland => {
                if (egl.eglSwapBuffers(window.handle.wayland.api.opengl.display, window.handle.wayland.api.opengl.surface) == egl.FALSE) return error.EglSwapBuffers;
                root.Window.Wayland.wl.wl_surface_commit(window.handle.wayland.surface);
                if (root.Window.Wayland.wl.wl_display_flush(window.handle.wayland.display) < 0) return error.FlushDisplay;
            },
        },
    }
}

pub fn swapInterval(window: root.Window, interval: i32) !void {
    switch (native.os) {
        .windows => if (window.handle.api.opengl.wgl.swapIntervalEXT(interval) == 0) return error.SwapInterval,
        else => switch (window.handle) {
            .x => {
                const glXSwapIntervalEXT: glx.PFNGLXSWAPINTERVALEXT = @ptrCast(glx.glXGetProcAddress("glXSwapIntervalEXT") orelse return error.SwapIntervalLoad);
                glXSwapIntervalEXT(window.handle.x.display, window.handle.x.window, @intCast(interval));
            },
            .wayland => if (egl.eglSwapInterval(window.handle.wayland.display, @intCast(interval)) == egl.FALSE) return error.SwapInterval,
        },
    }
}
