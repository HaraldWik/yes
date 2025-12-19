const std = @import("std");
const builtin = @import("builtin");
pub const Size = @import("../root.zig").Size;
pub const Position = @import("../root.zig").Position;
pub const Event = @import("event.zig").Union;
pub const Win32 = @import("Win32.zig");
pub const X11 = @import("X11.zig");
pub const Wayland = @import("Wayland.zig");

handle: Handle,

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

pub const GraphicsApi = union(Tag) {
    opengl: Opengl,
    vulkan: Vulkan,
    none: void,

    pub const Tag = enum {
        opengl,
        vulkan,
        none,
    };

    pub const Opengl = struct {
        version: std.SemanticVersion = .{ .major = 4, .minor = 6, .patch = 0 },
    };
    pub const Vulkan = struct {
        version: std.SemanticVersion = .{ .major = 1, .minor = 3, .patch = 0 },
    };
};

pub const Config = struct {
    title: [:0]const u8,
    size: Size = .{ .width = 420, .height = 260 },
    min_size: ?Size = null,
    max_size: ?Size = null,
    resizable: bool = true,
    api: GraphicsApi = .none,
};

pub fn open(config: Config) !@This() {
    const window: @This() = .{
        .handle = switch (builtin.os.tag) {
            .windows => try .open(config),
            else => switch (Posix.getSessionType() orelse .x11) {
                .x11 => .{ .x11 = try .open(config) },
                .wayland => .{ .wayland = try .open(config) },
            },
        },
    };
    if (builtin.os.tag != .windows) window.setTitle(config.title);
    return window;
}

pub fn close(self: @This()) void {
    switch (builtin.os.tag) {
        .windows => self.handle.close(),
        else => switch (self.handle) {
            inline else => |handle| handle.close(),
        },
    }
}

pub fn poll(self: *@This()) !?Event {
    return switch (builtin.os.tag) {
        .windows => self.handle.poll(),
        else => switch (self.handle) {
            inline else => |*handle| handle.poll(),
        },
    };
}

pub fn getSize(self: @This()) Size {
    return switch (builtin.os.tag) {
        .windows => self.handle.getSize(),
        else => switch (self.handle) {
            inline else => |handle| handle.getSize(),
        },
    };
}

pub fn setTitle(self: @This(), title: [:0]const u8) void {
    switch (builtin.os.tag) {
        .windows => self.handle.setTitle(title),
        else => switch (self.handle) {
            inline else => |handle| handle.setTitle(title),
        },
    }
}

pub fn fullscreen(self: *@This(), state: bool) void {
    switch (builtin.os.tag) {
        .windows => (&self.handle).fullscreen(state),
        else => switch (self.handle) {
            inline else => |*handle| handle.fullscreen(state),
        },
    }
}

pub fn maximize(self: @This(), state: bool) void {
    switch (builtin.os.tag) {
        .windows => self.handle.maximize(state),
        else => switch (self.handle) {
            inline else => |handle| handle.maximize(state),
        },
    }
}

pub fn minimize(self: @This()) void {
    switch (builtin.os.tag) {
        .windows => self.handle.minimize(),
        else => switch (self.handle) {
            inline else => |handle| handle.minimize(),
        },
    }
}
