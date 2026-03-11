const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Platform = @import("../Platform.zig");

const Cross = @This();

inner: Inner,

pub const Inner = switch (builtin.os.tag) {
    .windows => Platform.Win32,
    else => union(enum) {
        x: if (build_options.xlib) Platform.Xlib else Platform.Xpz,
        wayland: Platform.Wayland,
    },
};

pub const Window = struct {
    inner: @This().Inner,

    pub const Inner = switch (builtin.os.tag) {
        .windows => Platform.Win32.Window,
        else => union {
            x: if (build_options.xlib) Platform.Xlib.Window else Platform.Xpz.Window,
            wayland: Platform.Wayland.Window,
        },
    };

    pub fn empty(p: Platform) @This() {
        const cross: *Cross = @ptrCast(@alignCast(p.ptr));
        return switch (builtin.os.tag) {
            .windows => .{ .inner = .{} },
            else => switch (cross.inner) {
                .x => .{ .inner = .{ .x = .{} } },
                .wayland => .{ .inner = .{ .wayland = .{} } },
            },
        };
    }

    pub fn interface(self: *@This(), p: Platform) *Platform.Window {
        const cross: *Cross = @ptrCast(@alignCast(p.ptr));
        return switch (builtin.os.tag) {
            .windows => &self.inner.interface,
            else => switch (cross.inner) {
                .x => &self.inner.x.interface,
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
        .x11 => if (build_options.xlib)
            .{ .inner = .{ .x = try .init() } }
        else
            .{ .inner = .{ .x = try .init(allocator, io, minimal) } },
        .wayland => .{ .inner = .{ .wayland = try .init() } },
        else => error.UnsupportedUnixPlatform,
    };
}

pub fn deinit(self: *@This()) void {
    switch (builtin.os.tag) {
        .windows => {},
        else => switch (self.inner) {
            .x => self.inner.x.deinit(),
            .wayland => self.inner.wayland.deinit(),
        },
    }
}

pub fn platform(self: *@This()) Platform {
    return switch (builtin.os.tag) {
        .windows => self.inner.platform(),
        else => switch (self.inner) {
            .x => if (build_options.xlib) self.inner.x.platform(),
            .wayland => self.inner.wayland.platform(),
        },
    };
}
