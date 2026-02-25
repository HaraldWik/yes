const std = @import("std");
const builtin = @import("builtin");
const UnixSessionType = @import("root.zig").UnixSessionType;

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
pub fn getRequiredInstanceExtensions(comptime T: type, unix_session_type: UnixSessionType) []const T {
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
            },
            else => &.{},
        },
    };
}
