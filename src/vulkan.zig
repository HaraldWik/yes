const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("Platform.zig");

pub const Result = enum(c_int) {
    success = 0,
    _,
};

pub const Instance = opaque {
    pub const GetProcAddress = *const fn (instance: *Instance, name: [*:0]const u8) callconv(.c) *const fn () callconv(.c) void;
};

pub const AllocationCallbacks = opaque {};

pub const Surface = opaque {
    pub const CreateInfo = switch (builtin.os.tag) {
        .windows => extern struct {
            stype: c_uint = 1000009000,
            next: ?*const anyopaque = null,
            flags: u32 = 0,
            hinstance: std.os.windows.HINSTANCE,
            hwnd: std.os.windows.HWND,
        },
        else => union {
            xlib: Xlib,
            xcb: Xcb,
            wayland: Wayland,

            pub const Xlib = extern struct {
                stype: c_uint = 1000004000,
                next: ?*const anyopaque = null,
                flags: u32 = 0,
                display: *anyopaque,
                window: c_uint = 0,
            };

            pub const Xcb = extern struct {
                stype: c_uint = 1000005000,
                next: ?*const anyopaque = null,
                flags: u32 = 0,
                connection: *anyopaque,
                window: c_uint,
            };

            pub const Wayland = extern struct {
                stype: c_uint = 1000006000,
                next: ?*const anyopaque = null,
                flags: u32 = 0,
                display: *anyopaque,
                surface: *anyopaque,
            };
        },
    };

    pub const CreateProc = *const fn (instance: *Instance, create_info: *const Surface.CreateInfo, allocator: ?*const AllocationCallbacks, surface: *?*Surface) callconv(.c) Result;

    pub fn create(platform: Platform, window: *Platform.Window, instance: *Instance, allocator: ?*const AllocationCallbacks, getProcAddress: Instance.GetProcAddress) !*@This() {
        return platform.vtable.windowVulkanCreateSurface(platform.ptr, window, instance, allocator, getProcAddress);
    }
};

pub fn isSupported() bool {
    var lib_a = std.DynLib.openZ(switch (builtin.os.tag) {
        .windows => "vulkan-1.dll",
        else => "libvulkan.so.1",
    }) catch return false;
    lib_a.close();
    return true;
}

/// T is the string type
/// example of T [*:0]const u8 or [:0]const u8 or [:0]const u8
pub fn getRequiredInstanceExtensions(comptime T: type, unix_session_type: Platform.unix.SessionType) []const T {
    return switch (builtin.os.tag) {
        .windows => &.{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
        },
        else => switch (unix_session_type) {
            .wayland => &.{
                "VK_KHR_surface",
                "VK_KHR_wayland_surface",
            },
            .x11 => &.{
                "VK_KHR_surface",
                "VK_KHR_xlib_surface",
                "VK_KHR_xcb_surface",
            },
            else => &.{},
        },
    };
}
