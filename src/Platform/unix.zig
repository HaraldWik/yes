const std = @import("std");
const Platform = @import("../Platform.zig");

pub const SessionType = enum(u2) {
    x11,
    wayland,
    tty,

    pub const env = "XDG_SESSION_TYPE";

    pub fn detect(init: std.process.Init.Minimal) ?@This() {
        var args = init.args.iterate();
        _ = args.skip();

        const session = while (args.next()) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, arg, identifier)) continue;
            break arg[identifier.len..];
        } else init.environ.getPosix(env) orelse return null;

        return std.meta.stringToEnum(@This(), session) orelse null;
    }
};

pub const MultiPlatform = union(enum) {
    xpz: Platform.Xpz,
    wayland: Platform.Wayland,

    pub fn init(io: std.Io, minimal: std.process.Init.Minimal) !@This() {
        const unix_session_type = SessionType.detect(minimal) orelse .x11;
        std.log.info("unix session type: {t}", .{unix_session_type});

        var self: @This() = undefined;
        switch (unix_session_type) {
            .x11 => {
                self = .{ .xpz = undefined };
                try self.xpz.init(io, minimal);
            },
            .wayland => {
                self = .{ .wayland = .{} };
            },
            else => return error.UnsupportedUnixPlatform,
        }
        return self;
    }

    pub fn deinit(self: @This(), io: std.Io) void {
        switch (self) {
            .xpz => |xpz| xpz.deinit(io),
            .wayland => {},
        }
    }

    pub fn platform(self: *@This()) Platform {
        return switch (self.*) {
            .xpz => self.xpz.platform(),
            .wayland => self.wayland.platform(),
        };
    }
};
