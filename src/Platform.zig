ptr: *anyopaque,
vtable: *const VTable,

/// Does not open any windows nor does it execute any 'real' platform interaction
pub const Dummy = @import("Platform/Dummy.zig");
/// Default win32 api interactions
pub const Win32 = @import("Platform/Win32.zig");
/// X-protocol implementation written in zig
pub const Xpz = @import("Platform/Xpz.zig");

pub const VTable = struct {
    windowOpen: *const fn (*anyopaque, window: *Window, options: Window.OpenOptions) anyerror!void,
    windowClose: *const fn (*anyopaque, window: *Window) void,
    windowPoll: *const fn (*anyopaque, window: *Window) anyerror!?Window.Event,
    windowSetProperty: *const fn (*anyopaque, window: *Window, property: Window.Property) anyerror!void,
};

pub const Window = @import("Window.zig");
