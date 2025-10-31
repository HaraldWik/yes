const builtin = @import("builtin");
const root = @import("root.zig");

pub const win32 = @import("win32").everything;
pub const glx = struct {
    pub const Drawable = c_ulong;
    pub extern fn glXGetProcAddress(name: [*:0]const u8) ?*const fn () callconv(.c) void;
    pub extern fn glXSwapBuffers(display: *root.X.c.Display, drawable: Drawable) void;
};

const native_os = builtin.os.tag;

pub fn getProcAddress(name: [*:0]const u8) ?*const fn () callconv(.c) void {

    // if (glClear == null) @panic("FUCK");
    return switch (native_os) {
        .windows => @ptrCast(win32.wglGetProcAddress(name)),
        else => glx.glXGetProcAddress(name),
    };
}

pub fn swapBuffers(window: root.Window) void {
    switch (native_os) {
        .windows => _ = win32.SwapBuffers(window.handle.hdc),
        else => glx.glXSwapBuffers(@ptrCast(window.handle.display), window.handle.window),
    }
}
