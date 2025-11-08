const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");

pub const win32 = @import("win32").everything;
pub const glx = struct {
    pub const Drawable = c_ulong;
    pub extern fn glXGetProcAddress(name: [*:0]const u8) ?Proc;
    pub extern fn glXSwapBuffers(display: *root.Posix.X.c.Display, drawable: Drawable) void;
};

const native_os = builtin.os.tag;

pub const Proc = *const fn () callconv(.c) void;

pub fn getProcAddress(name: [*:0]const u8) ?Proc {
    return switch (native_os) {
        .windows => @ptrCast(win32.wglGetProcAddress(name) orelse proc: {
            const gl = win32.LoadLibraryW(win32.L("opengl32.dll")) orelse break :proc null;
            defer _ = win32.FreeLibrary(gl);
            break :proc win32.GetProcAddress(gl, name);
        }),

        else => glx.glXGetProcAddress(name),
    };
}

pub fn swapBuffers(window: root.Window) void {
    switch (native_os) {
        .windows => _ = win32.SwapBuffers(window.handle.api.opengl.hdc),
        else => switch (window.handle) {
            .x => glx.glXSwapBuffers(@ptrCast(window.handle.x.display), window.handle.x.window),
            .wayland => unreachable,
        },
    }
}
