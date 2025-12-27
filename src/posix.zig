const std = @import("std");

pub const Tag = enum { x11, wayland };

pub const session_env = "XDG_SESSION_TYPE";

pub fn getSessionType() Tag {
    for (std.os.argv) |arg| {
        const identifier = "--xdg=";
        if (!std.mem.startsWith(u8, std.mem.span(arg), identifier)) continue;
        return std.meta.stringToEnum(Tag, std.mem.span(arg)[identifier.len..]) orelse .x11;
    }
    const session = std.posix.getenv(session_env) orelse return .x11;
    return std.meta.stringToEnum(Tag, session) orelse .x11;
}
