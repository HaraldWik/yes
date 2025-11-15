const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const root = @import("../root.zig");
const native = @import("../root.zig").native;

handle: Handle,

pub const Handle = switch (native.os) {
    .windows => Win32,
    else => Posix,
};

pub const Win32 = @import("Win32.zig");
pub const X = @import("X.zig");
pub const Wayland = @import("Wayland.zig");
pub const Posix = union(Tag) {
    x: X,
    wayland: Wayland,

    pub const Tag = enum { x, wayland };

    pub const session_type = "XDG_SESSION_TYPE";

    pub fn getSessionType() ?Tag {
        for (std.os.argv) |arg| {
            const identifier = "--xdg=";
            if (!std.mem.startsWith(u8, std.mem.span(arg), identifier)) continue;
            return std.meta.stringToEnum(Tag, std.mem.span(arg)[identifier.len..]);
        }
        const session = std.posix.getenv(Posix.session_type) orelse "x11";
        return if (std.mem.eql(u8, session, "wayland")) .wayland else .x;
    }
};

pub const Config = struct {
    title: [:0]const u8,
    width: usize,
    height: usize,
    min_width: ?usize = null,
    min_height: ?usize = null,
    max_width: ?usize = null,
    max_height: ?usize = null,
    resizable: bool = true,
    api: root.GraphicsApi = .none,
};

pub fn open(config: Config) !@This() {
    if (config.api == .opengl and !build_options.opengl) @compileError("opengl is not enabled");
    if (config.api == .vulkan and !build_options.vulkan) @compileError("vulkan is not enabled");

    return .{
        .handle = switch (native.os) {
            .windows => try .open(config),
            else => switch (Posix.getSessionType() orelse .x) {
                .x => .{ .x = try .open(config) },
                .wayland => .{ .wayland = try .open(config) },
            },
        },
    };
}

pub fn close(self: @This()) void {
    switch (native.os) {
        .windows => self.handle.close(),
        else => switch (self.handle) {
            inline else => |handle| handle.close(),
        },
    }
}

pub fn poll(self: @This()) !?root.Event {
    return switch (native.os) {
        .windows => try self.handle.poll(),
        else => switch (self.handle) {
            inline else => |handle| handle.poll(),
        },
    };
}

pub fn getSize(self: @This()) [2]usize {
    return switch (native.os) {
        .windows => self.handle.getSize(),
        else => switch (self.handle) {
            inline else => |handle| handle.getSize(),
        },
    };
}
