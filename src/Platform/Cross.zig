const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");

const Cross = @This();

inner: Inner,

const is_wasm = builtin.cpu.arch.isWasm();

pub const Inner = if (build_options.glfw) Platform.Glfw else switch (builtin.os.tag) {
    .windows => Platform.Win32,
    .macos, .ios, .tvos => Platform.Cocoa,
    else => if (is_wasm)
        Platform.Web
    else
        union(enum) {
            x: if (build_options.xlib) Platform.Xlib else Platform.Xpz,
            wayland: if (build_options.libwayland) Platform.Wayland else void,
        },
};

pub const Window = struct {
    inner: @This().Inner,

    pub const Inner = if (build_options.glfw) Platform.Glfw.Window else switch (builtin.os.tag) {
        .windows => Platform.Win32.Window,
        .macos, .ios, .tvos => Platform.Cocoa.Window,
        else => if (is_wasm)
            Platform.Web.Window
        else
            union {
                x: if (build_options.xlib) Platform.Xlib.Window else Platform.Xpz.Window,
                wayland: if (build_options.libwayland) Platform.Wayland.Window else void,
            },
    };

    pub fn empty(p: Platform) @This() {
        const cross: *Cross = @ptrCast(@alignCast(p.ptr));
        return if (build_options.glfw) .{ .inner = .{} } else switch (builtin.os.tag) {
            .windows => .{ .inner = .{} },
            .macos, .ios, .tvos => .{ .inner = .{} },
            else => if (is_wasm)
                .{ .inner = .{} }
            else switch (cross.inner) {
                .x => .{ .inner = .{ .x = .{} } },
                .wayland => if (build_options.libwayland) .{ .inner = .{ .wayland = .{} } } else undefined,
            },
        };
    }

    pub fn interface(self: *@This(), p: Platform) *PlatformWindow {
        const cross: *Cross = @ptrCast(@alignCast(p.ptr));
        return if (build_options.glfw) &self.inner.interface else switch (builtin.os.tag) {
            .windows => &self.inner.interface,
            .macos, .ios, .tvos => &self.inner.interface,
            else => if (is_wasm)
                &self.inner.interface
            else switch (cross.inner) {
                .x => &self.inner.x.interface,
                .wayland => if (build_options.libwayland) &self.inner.wayland.interface else unreachable,
            },
        };
    }
};

pub fn init(allocator: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    return if (build_options.glfw) .{ .inner = try Platform.Glfw.init(allocator) } else switch (builtin.os.tag) {
        .windows => .{ .inner = try Platform.Win32.init(allocator) },
        .macos, .ios, .tvos => .{ .inner = try Platform.Cocoa.init() },
        else => if (is_wasm)
            .{ .inner = try Platform.Web.init() }
        else
            try initUnix(allocator, io, minimal),
    };
}

fn initUnix(allocator: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    const session_type: Platform.unix.SessionType = if (build_options.libwayland) Platform.unix.SessionType.detect(minimal) orelse .x11 else .x11;
    return switch (session_type) {
        .x11 => if (build_options.xlib)
            .{ .inner = .{ .x = try .init() } }
        else
            .{ .inner = .{ .x = try .init(allocator, io, minimal) } },
        .wayland => if (build_options.libwayland) .{ .inner = .{ .wayland = try .init(allocator) } } else unreachable,
        else => error.UnsupportedUnixPlatform,
    };
}

pub fn deinit(self: *@This()) void {
    if (build_options.glfw) self.inner.deinit() else switch (builtin.os.tag) {
        .windows => {},
        .macos, .ios, .tvos => self.inner.deinit(),
        else => if (is_wasm)
            self.inner.deinit()
        else switch (self.inner) {
            .x => self.inner.x.deinit(),
            .wayland => if (build_options.libwayland) self.inner.wayland.deinit() else unreachable,
        },
    }
}

pub fn platform(self: *@This()) Platform {
    return if (build_options.glfw) self.inner.platform() else switch (builtin.os.tag) {
        .windows => self.inner.platform(),
        .macos, .ios, .tvos => self.inner.platform(),
        else => if (is_wasm)
            self.inner.platform()
        else switch (self.inner) {
            .x => self.inner.x.platform(),
            .wayland => if (build_options.libwayland) self.inner.wayland.platform() else unreachable,
        },
    };
}
