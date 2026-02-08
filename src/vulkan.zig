const std = @import("std");
const builtin = @import("builtin");
const posix = @import("posix.zig");
const Context = @import("Context.zig");

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
pub fn getRequiredInstanceExtensions(context: Context, comptime T: type) []const T {
    return switch (builtin.os.tag) {
        .windows => &.{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
        },
        else => switch (context.posix_platform) {
            .wayland => &.{
                "VK_KHR_surface",
                "VK_KHR_wayland_surface",
            },
            .x11 => &.{
                "VK_KHR_surface",
                "VK_KHR_xlib_surface",
            },
        },
    };
}
