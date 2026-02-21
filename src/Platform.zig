ptr: *anyopaque,
vtable: *const VTable,

pub const Dummy = @import("Platform/Dummy.zig");
pub const Win32 = @import("Platform/Win32.zig");
pub const Xpz = @import("Platform/Xpz.zig");

pub const VTable = struct {
    windowOpen: *const fn (*anyopaque, window: *Window, options: Window.OpenOptions) anyerror!void,
    windowClose: *const fn (*anyopaque, window: *Window) void,
    windowPoll: *const fn (*anyopaque, window: *Window) anyerror!?Window.Event,
    windowSetTitle: *const fn (*anyopaque, window: *Window, title: []const u8) anyerror!void,
};

pub const Window = @import("Window.zig");
