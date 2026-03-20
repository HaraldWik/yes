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
/// X-protocol implementation written in zig
pub const Xpz = @import("Platform/Xpz.zig");
/// Xlib
pub const Xlib = @import("Platform/Xlib.zig");
/// Default Wayland Client
pub const Wayland = @import("Platform/Wayland.zig");
/// Currently just a dummy platform
pub const Cocoa = @import("Platform/Cocoa.zig");

pub const Web = @import("Platform/Web.zig");

pub const unix = @import("Platform/unix.zig");

pub const VTable = struct {
    windowOpen: *const fn (*anyopaque, window: *Window, options: Window.OpenOptions) anyerror!void,
    windowClose: *const fn (*anyopaque, window: *Window) void,
    windowPoll: *const fn (*anyopaque, window: *Window) anyerror!?Window.Event,
    windowSetProperty: *const fn (*anyopaque, window: *Window, property: Window.Property) anyerror!void,

    windowFramebuffer: *const fn (*anyopaque, window: *Window) anyerror!Window.Framebuffer,

    windowOpenglMakeCurrent: *const fn (*anyopaque, window: *Window) anyerror!void,
    windowOpenglSwapBuffers: *const fn (*anyopaque, window: *Window) anyerror!void,
    windowOpenglSwapInterval: *const fn (*anyopaque, window: *Window, interval: i32) anyerror!void,

    windowVulkanCreateSurface: *const fn (*anyopaque, window: *Window, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface,

    openglGetProcAddress: *const fn (procname: [*:0]const u8) callconv(opengl.APIENTRY) ?opengl.Proc,
};

pub const Window = @import("Window.zig");
