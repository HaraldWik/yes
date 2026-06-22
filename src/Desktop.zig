const Desktop = @This();

const build_options = @import("build_options");
const Window = @import("Window.zig");
const opengl = @import("opengl.zig");
const vulkan = @import("vulkan.zig");
const Clipboard = @import("root.zig").Clipboard;

userdata: ?*anyopaque,
vtable: *const VTable,

/// Does not open any windows nor does it execute any 'real' desktop interactions
pub const Dummy = @import("Desktop/Dummy.zig");
/// Cross platform desktop, only uses standard implementations
pub const Cross = @import("Desktop/Cross.zig");
/// Default win32 api interactions
pub const Win32 = @import("Desktop/Win32.zig");
/// Default Wayland Client
pub const Wayland = if (build_options.wayland_backend != .none) @import("Desktop/Wayland.zig") else @compileError("libwayland backend is unavailable unless build options wayland_backend is set to .libwayland");
/// Xcb, more modern Xlib
pub const Xcb = if (build_options.x_backend != .none) @import("Desktop/Xcb.zig") else @compileError("xcb backend is unavailable unless build options x_backend is set to .xcb");
/// Xlib
pub const Xlib = if (build_options.x_backend != .none) @import("Desktop/Xlib.zig") else @compileError("xlib backend is unavailable unless build options x_backend is set to .xlib");
/// X-protocol implementation written in zig
pub const Xpz = if (build_options.x_backend != .none) @import("Desktop/Xpz.zig") else @compileError("xpz backend is unavailable unless build options x_backend is set to .xpz");
/// Currently just a dummy desktop
pub const Cocoa = @import("Desktop/Cocoa.zig");

pub const Glfw = @import("Desktop/Glfw.zig");

pub const unix = @import("Desktop/unix.zig");

pub const VTable = struct {
    windowOpen: *const fn (userdata: ?*anyopaque, window: *Window, options: Window.OpenOptions) anyerror!void,
    windowClose: *const fn (userdata: ?*anyopaque, window: *Window) void,
    windowPoll: *const fn (userdata: ?*anyopaque, window: *Window) anyerror!?Window.Event,
    windowSetProperty: *const fn (userdata: ?*anyopaque, window: *Window, property: Window.Property) anyerror!void,
    windowNative: *const fn (userdata: ?*anyopaque, window: *Window) Window.Native,

    windowFramebuffer: *const fn (userdata: ?*anyopaque, window: *Window) anyerror!Window.Framebuffer,
    windowFramebufferPresent: *const fn (userdata: ?*anyopaque, window: *Window) anyerror!void,

    windowOpenglMakeCurrent: *const fn (userdata: ?*anyopaque, window: *Window) anyerror!void,
    windowOpenglSwapBuffers: *const fn (userdata: ?*anyopaque, window: *Window) anyerror!void,
    windowOpenglSwapInterval: *const fn (userdata: ?*anyopaque, window: *Window, interval: i32) anyerror!void,

    windowVulkanCreateSurface: *const fn (userdata: ?*anyopaque, window: *Window, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque,

    openglGetProcAddress: *const fn (procname: [*:0]const u8) callconv(opengl.APIENTRY) ?opengl.Proc,

    setClipboard: *const fn (userdata: ?*anyopaque, serial: u32, clipboard: Clipboard) anyerror!void = undefined,
};

pub const failing: Desktop = .{
    .userdata = null,
    .vtable = &VTable{
        .windowOpen = noWindowOpen,
        .windowClose = noWindowClose,
        .windowPoll = noWindowPoll,
        .windowSetProperty = noWindowSetProperty,
        .windowNative = unreachableWindowNative,
        .windowFramebuffer = failingWindowFramebuffer,
        .windowFramebufferPresent = noWindowFramebufferPresent,
        .windowOpenglMakeCurrent = noWindowOpenglMakeCurrent,
        .windowOpenglSwapBuffers = failingWindowOpenglSwapBuffers,
        .windowOpenglSwapInterval = failingWindowOpenglSwapInterval,
        .windowVulkanCreateSurface = failingWindowVulkanCreateSurface,
        .openglGetProcAddress = noOpenglGetProcAddress,
    },
};

pub fn noWindowOpen(userdata: ?*anyopaque, window: *Window, options: Window.OpenOptions) anyerror!void {
    _ = userdata;
    _ = window;
    _ = options;
}
pub fn noWindowClose(userdata: ?*anyopaque, window: *Window) void {
    _ = userdata;
    _ = window;
}
pub fn noWindowPoll(userdata: ?*anyopaque, window: *Window) anyerror!?Window.Event {
    _ = userdata;
    _ = window;

    return null;
}
pub fn noWindowSetProperty(userdata: ?*anyopaque, window: *Window, property: Window.Property) anyerror!void {
    _ = userdata;
    _ = window;
    _ = property;
}
pub fn unreachableWindowNative(userdata: ?*anyopaque, window: *Window) Window.Native {
    _ = userdata;
    _ = window;
    unreachable;
}
pub fn failingWindowFramebuffer(userdata: ?*anyopaque, window: *Window) anyerror!Window.Framebuffer {
    _ = userdata;
    _ = window;
    return error.Failing;
}
pub fn noWindowFramebufferPresent(userdata: ?*anyopaque, window: *Window) anyerror!void {
    _ = userdata;
    _ = window;
}
pub fn noWindowOpenglMakeCurrent(userdata: ?*anyopaque, window: *Window) anyerror!void {
    _ = userdata;
    _ = window;
}
pub fn failingWindowOpenglSwapBuffers(userdata: ?*anyopaque, window: *Window) anyerror!void {
    _ = userdata;
    _ = window;
    return error.SwapBuffers;
}
pub fn failingWindowOpenglSwapInterval(userdata: ?*anyopaque, window: *Window, interval: i32) anyerror!void {
    _ = userdata;
    _ = window;
    _ = interval;
    return error.SwapInterval;
}
pub fn failingWindowVulkanCreateSurface(userdata: ?*anyopaque, window: *Window, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque {
    _ = userdata;
    _ = window;
    _ = instance;
    _ = allocator;
    _ = loader;
    return error.CreateSurface;
}
pub fn noOpenglGetProcAddress(procname: [*:0]const u8) callconv(opengl.APIENTRY) ?opengl.Proc {
    _ = procname;
    return null;
}
pub fn failingSetClipboard(userdata: ?*anyopaque, serial: u32, clipboard: Clipboard) anyerror!void {
    _ = userdata;
    _ = serial;
    _ = clipboard;
    return error.SetClipboard;
}
