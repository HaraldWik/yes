const std = @import("std");
const builtin = @import("builtin");
pub const Size = @import("../root.zig").Size;
pub const Position = @import("../root.zig").Position;
pub const Win32 = @import("Win32.zig");
pub const X11 = @import("X11.zig");
pub const Wayland = @import("Wayland.zig");

const Monitor = @This();

name: ?[]const u8 = null,
size: Size = .{},
position: Position(i32) = .{},
/// milimeters
physical_size: ?Size = null,
scale: f32 = 1.0,
primary: bool = false,
orientation: Orientation = .@"0",
manufacturer: ?struct {
    name: []const u8,
    model: ?[]const u8,
} = null,

/// clockwise
pub const Orientation = enum(u2) {
    // NOTE: These values are the same on windows and wayland
    @"0" = 0,
    @"90" = 1,
    @"180" = 2,
    @"270" = 3,

    pub fn fromX11(value: @import("x11").Rotation) @This() {
        return @enumFromInt(@as(std.meta.Tag(@This()), @intCast(std.math.log2(value))));
    }
};

pub const Handle = switch (builtin.os.tag) {
    .windows => Win32,
    else => Posix,
};

pub const Posix = union(Tag) {
    x11: X11,
    wayland: Wayland,

    pub const Tag = enum { x11, wayland };

    pub const session_env = "XDG_SESSION_TYPE";

    pub fn getSessionType() ?Tag {
        for (std.os.argv) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, std.mem.span(arg), identifier)) continue;
            return std.meta.stringToEnum(Tag, std.mem.span(arg)[identifier.len..]);
        }
        const session = std.posix.getenv(session_env) orelse "x11";
        return std.meta.stringToEnum(Tag, session);
    }
};

pub const Iterator = struct {
    index: usize = 0,
    buffer: []u8 = undefined,

    pub fn init(buffer: []u8) @This() {
        return .{ .buffer = buffer };
    }

    pub fn next(self: *@This()) !?Monitor {
        defer self.index += 1;
        return switch (builtin.os.tag) {
            .windows => try Win32.get(self.index, self.buffer),
            else => switch (Posix.getSessionType() orelse .x11) {
                .x11 => X11.get(self.index, self.buffer),
                .wayland => Wayland.get(self.index, self.buffer),
            },
        };
    }
};
