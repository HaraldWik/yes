const std = @import("std");
const builtin = @import("builtin");
const posix = @import("posix.zig");

pub fn isSupported() bool {
    var lib_a = std.DynLib.openZ(switch (builtin.os.tag) {
        .windows => "vulkan-1.dll",
        else => "libvulkan.so.1",
    }) catch return false;
    lib_a.close();
    return true;
}

pub fn getRequiredInstanceExtensions() []const [:0]const u8 {
    return switch (builtin.os.tag) {
        .windows => &.{
            "VK_KHR_surface",
            "VK_KHR_win32_surface",
        },
        else => switch (posix.getPlatform()) {
            .wayland => &.{
                "VK_KHR_surface",
                "VK_KHR_wayland_surface",
            },
            .x11 => &.{
                "VK_KHR_surface",
                "VK_KHR_xcb_surface",
            },
        },
    };
}
