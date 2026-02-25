const std = @import("std");
pub const Platform = @import("Platform.zig");
pub const opengl = @import("opengl.zig");
pub const vulkan = @import("vulkan.zig");

pub const legacy = @import("legacy/root.zig");

pub const UnixSessionType = enum(u2) {
    x11,
    wayland,
    tty,

    pub const session_env = "XDG_SESSION_TYPE";

    pub fn get(init: std.process.Init.Minimal) ?@This() {
        var args = init.args.iterate();
        _ = args.skip();

        const session = while (args.next()) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, arg, identifier)) continue;
            break arg[identifier.len..];
        } else init.environ.getPosix(session_env) orelse return null;

        return std.meta.stringToEnum(@This(), session) orelse null;
    }
};
