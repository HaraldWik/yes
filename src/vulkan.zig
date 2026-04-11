const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Platform = @import("Platform.zig");
const Window = @import("Window.zig");

pub const Result = enum(c_int) {
    success = 0,
    _,
};

pub const call_conv: std.builtin.CallingConvention = if (builtin.os.tag == .windows and builtin.cpu.arch == .x86)
    .winapi
else if (builtin.abi == .android and (builtin.cpu.arch.isArm() or builtin.cpu.arch.isThumb()) and std.Target.arm.featureSetHas(builtin.cpu.features, .has_v7) and builtin.cpu.arch.ptrBitWidth() == 32)
    .arm_aapcs_vfp
else
    .c;

pub const PfnVoidFunction = ?*const fn () callconv(call_conv) void;
pub const PfnGetInstanceProcAddr = *const fn (
    instance: *anyopaque,
    p_name: [*:0]const u8,
) callconv(call_conv) PfnVoidFunction;

pub const SurfaceCreateInfo = switch (builtin.os.tag) {
    .windows => extern struct {
        stype: c_uint = 1000009000,
        next: ?*const anyopaque = null,
        flags: u32 = 0,
        hinstance: std.os.windows.HINSTANCE,
        hwnd: std.os.windows.HWND,
    },
    else => extern union {
        wayland: Wayland,
        xlib: Xlib,
        xcb: Xcb,

        pub const Wayland = extern struct {
            stype: c_uint = 1000006000,
            next: ?*const anyopaque = null,
            flags: u32 = 0,
            display: *anyopaque,
            surface: *anyopaque,
        };

        pub const Xcb = extern struct {
            stype: c_uint = 1000005000,
            next: ?*const anyopaque = null,
            flags: u32 = 0,
            connection: *anyopaque,
            window: u32,
        };

        pub const Xlib = extern struct {
            stype: c_uint = 1000004000,
            next: ?*const anyopaque = null,
            flags: u32 = 0,
            display: *anyopaque,
            window: c_ulong = 0,
        };
    },
};

pub const SurfaceCreateProc = *const fn (instance: *anyopaque, create_info: *const SurfaceCreateInfo, allocator: ?*const anyopaque, surface: *?*anyopaque) callconv(.c) Result;

pub fn createSurface(platform: Platform, window: *Window, instance: *anyopaque, allocator: ?*const anyopaque, loader: PfnGetInstanceProcAddr) !*anyopaque {
    if (window.surface_type != .vulkan) return error.WrongSurfaceType;
    return platform.vtable.windowVulkanCreateSurface(platform.ptr, window, instance, allocator, loader);
}

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
pub fn getRequiredInstanceExtensions(comptime T: type, platform: Platform, window: *Window) []const T {
    return switch (builtin.os.tag) {
        .windows => &.{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
        },
        .macos => &.{
            "VK_KHR_surface",
            "VK_MVK_macos_surface",
        },
        .ios => &.{
            "VK_KHR_surface",
            "VK_MVK_ios_surface",
        },
        .linux, .freebsd, .netbsd, .openbsd => if (builtin.abi == .android) &.{
            "VK_KHR_surface",
            "VK_KHR_android_surface",
        } else switch (window.native(platform)) {
            .wayland => &.{
                "VK_KHR_surface",
                "VK_KHR_wayland_surface",
            },
            .x11 => switch (build_options.x_backend) {
                .none => &.{
                    "VK_KHR_surface",
                    "VK_KHR_xcb_surface",
                    "VK_KHR_xlib_surface",
                },
                .xcb, .xpz => &.{
                    "VK_KHR_surface",
                    "VK_KHR_xcb_surface",
                },
                .xlib => &.{
                    "VK_KHR_surface",
                    "VK_KHR_xlib_surface",
                },
            },
            else => &.{},
        },
        else => &.{},
    };
}
