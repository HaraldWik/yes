const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");

const native_os = builtin.os.tag;

pub const win32 = @import("win32").everything;
pub const glx = struct {
    pub const Drawable = c_ulong;
    pub const getProcAddress = glXGetProcAddress;
    pub const swapBuffers = glXSwapBuffers;

    extern fn glXGetProcAddress(name: [*:0]const u8) ?Proc;
    extern fn glXSwapBuffers(display: *root.Posix.X.c.Display, drawable: Drawable) void;
};
pub const egl = struct {
    pub const FALSE = 0;
    pub const getProcAddress = eglGetProcAddress;
    pub const swapBuffers = eglSwapBuffers;
    pub const getError = eglGetError;

    extern fn eglGetProcAddress(name: [*:0]const u8) ?Proc;
    extern fn eglSwapBuffers(display: *anyopaque, surface: *anyopaque) c_uint;
    extern fn eglGetError() i32;
};

pub const Proc = *const fn () callconv(.c) void;

pub fn getProcAddress(name: [*:0]const u8) ?Proc {
    return switch (native_os) {
        .windows => @ptrCast(win32.wglGetProcAddress(name) orelse proc: {
            const gl = win32.LoadLibraryW(win32.L("opengl32.dll")) orelse break :proc null;
            defer _ = win32.FreeLibrary(gl);
            break :proc win32.GetProcAddress(gl, name);
        }),
        else => glx.getProcAddress(name) orelse egl.getProcAddress(name),
    };
}

pub fn swapBuffers(window: root.Window) !void {
    switch (native_os) {
        .windows => _ = win32.SwapBuffers(window.handle.api.opengl.hdc),
        else => switch (window.handle) {
            .x => glx.swapBuffers(@ptrCast(window.handle.x.display), window.handle.x.window),
            .wayland => {
                if (egl.swapBuffers(window.handle.wayland.api.opengl.display, window.handle.wayland.api.opengl.surface) == egl.FALSE) return error.EglSwapBuffers;
                root.Posix.Wayland.wl.wl_surface_commit(window.handle.wayland.surface);
                if (root.Posix.Wayland.wl.wl_display_flush(window.handle.wayland.display) < 0) return error.FlushDisplay;
            },
        },
    }
}
