const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("../Platform.zig");

const Cross = @This();

inner: Inner,

pub const Inner = switch (builtin.os.tag) {
    .windows => Platform.Win32,
    else => union(enum) {
        xpz: Platform.Xpz,
        wayland: Platform.Wayland,
    },
};

pub const Window = struct {
    inner: @This().Inner,

    pub const Inner = switch (builtin.os.tag) {
        .windows => Platform.Win32.Window,
        else => union {
            xpz: Platform.Xpz.Window,
            wayland: Platform.Wayland.Window,
        },
    };

    pub fn empty(p: Platform) @This() {
        const cross: *Cross = @ptrCast(@alignCast(p.ptr));
        return switch (builtin.os.tag) {
            .windows => .{ .inner = .{} },
            else => switch (cross.inner) {
                .xpz => .{ .inner = .{ .xpz = .{} } },
                .wayland => .{ .inner = .{ .wayland = .{} } },
            },
        };
    }

    pub fn interface(self: *@This(), p: Platform) *Platform.Window {
        const cross: *Cross = @ptrCast(@alignCast(p.ptr));
        return switch (builtin.os.tag) {
            .windows => &self.inner.interface,
            else => switch (cross.inner) {
                .xpz => &self.inner.xpz.interface,
                .wayland => &self.inner.wayland.interface,
            },
        };
    }
};

pub fn init(allocator: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    return switch (builtin.os.tag) {
        .windows => .{ .inner = try Platform.Win32.get(allocator) },
        else => try initUnix(allocator, io, minimal),
    };
}

fn initUnix(allocator: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    const session_type = Platform.unix.SessionType.detect(minimal) orelse .x11;
    return switch (session_type) {
        .x11 => .{ .inner = .{ .xpz = try .init(allocator, io, minimal) } },
        .wayland => .{ .inner = .{ .wayland = .{} } },
        else => error.UnsupportedUnixPlatform,
    };
}

pub fn deinit(self: *@This()) void {
    switch (builtin.os.tag) {
        .windows => {},
        else => switch (self.inner) {
            .xpz => self.inner.xpz.deinit(),
            .wayland => {},
        },
    }
}

pub fn platform(self: *@This()) Platform {
    return switch (builtin.os.tag) {
        .windows => self.inner.platform(),
        else => switch (self.inner) {
            .xpz => self.inner.xpz.platform(),
            .wayland => self.inner.wayland.platform(),
        },
    };
}
