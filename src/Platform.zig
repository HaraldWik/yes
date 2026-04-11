const build_options = @import("build_options");
const Window = @import("Window.zig");
const opengl = @import("opengl.zig");
const vulkan = @import("vulkan.zig");

ptr: *anyopaque,
vtable: *const VTable,

/// Does not open any windows nor does it execute any 'real' platform interaction
pub const Dummy = @import("Platform/Dummy.zig");
/// Cross platform, only uses standard implementation
pub const Cross = @import("Platform/Cross.zig");
/// Default win32 api interactions
pub const Win32 = @import("Platform/Win32.zig");
/// Default Wayland Client
pub const Wayland = if (build_options.wayland_backend != .none) @import("Platform/Wayland.zig") else @compileError("libwayland backend is unavailable unless build options wayland_backend is set to .libwayland");
/// Xcb, more modern Xlib
pub const Xcb = if (build_options.x_backend != .none) @import("Platform/Xcb.zig") else @compileError("xcb backend is unavailable unless build options x_backend is set to .xcb");
/// Xlib
pub const Xlib = if (build_options.x_backend != .none) @import("Platform/Xlib.zig") else @compileError("xlib backend is unavailable unless build options x_backend is set to .xlib");
/// X-protocol implementation written in zig
pub const Xpz = if (build_options.x_backend != .none) @import("Platform/Xpz.zig") else @compileError("xpz backend is unavailable unless build options x_backend is set to .xpz");
/// Currently just a dummy platform
pub const Cocoa = @import("Platform/Cocoa.zig");

pub const Web = @import("Platform/Web.zig");

pub const Glfw = @import("Platform/Glfw.zig");

pub const unix = @import("Platform/unix.zig");

pub const VTable = struct {
    windowOpen: *const fn (*anyopaque, window: *Window, options: Window.OpenOptions) anyerror!void,
    windowClose: *const fn (*anyopaque, window: *Window) void,
    windowPoll: *const fn (*anyopaque, window: *Window) anyerror!?Window.Event,
    windowSetProperty: *const fn (*anyopaque, window: *Window, property: Window.Property) anyerror!void,
    windowNative: *const fn (*anyopaque, window: *Window) Window.Native,

    windowFramebuffer: *const fn (*anyopaque, window: *Window) anyerror!Window.Framebuffer,

    windowOpenglMakeCurrent: *const fn (*anyopaque, window: *Window) anyerror!void,
    windowOpenglSwapBuffers: *const fn (*anyopaque, window: *Window) anyerror!void,
    windowOpenglSwapInterval: *const fn (*anyopaque, window: *Window, interval: i32) anyerror!void,

    windowVulkanCreateSurface: *const fn (*anyopaque, window: *Window, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque,

    openglGetProcAddress: *const fn (procname: [*:0]const u8) callconv(opengl.APIENTRY) ?opengl.Proc,
};
