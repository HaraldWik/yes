const std = @import("std");

pub const Platform = enum {
    x11,
    wayland,

    pub const fallback: @This() = .x11;

    pub const session_env = "XDG_SESSION_TYPE";

    pub fn get(init: std.process.Init.Minimal) @This() {
        var args = init.args.iterate();
        _ = args.skip();
        while (args.next()) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, arg, identifier)) continue;
            return std.meta.stringToEnum(@This(), arg[identifier.len..]) orelse .fallback;
        }
        const session = init.environ.getPosix(session_env) orelse return .fallback;
        return std.meta.stringToEnum(@This(), session) orelse .fallback;
    }
};
