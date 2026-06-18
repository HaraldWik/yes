const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const Desktop = @import("../Desktop.zig");
const DesktopWindow = @import("../Window.zig");

const Cross = @This();

inner: Inner,

const is_wasm = builtin.cpu.arch.isWasm();

pub const Inner = if (build_options.glfw) Desktop.Glfw else switch (builtin.os.tag) {
    .windows => Desktop.Win32,
    .macos, .ios, .tvos => Desktop.Cocoa,
    else => if (is_wasm)
        Desktop.Web
    else
        union(enum) {
            wayland: switch (build_options.wayland_backend) {
                .none => void,
                .libwayland => Desktop.Wayland,
            },
            x: switch (build_options.x_backend) {
                .none => void,
                .xcb => Desktop.Xcb,
                .xlib => Desktop.Xlib,
                .xpz => Desktop.Xpz,
            },
        },
};

pub const Window = struct {
    inner: if (@hasDecl(Inner, "Window")) Inner.Window else union {
        wayland: switch (build_options.wayland_backend) {
            .none => void,
            .libwayland => Desktop.Wayland.Window,
        },
        x: switch (build_options.x_backend) {
            .none => void,
            .xcb => Desktop.Xcb.Window,
            .xlib => Desktop.Xlib.Window,
            .xpz => Desktop.Xpz.Window,
        },
    },

    pub fn empty(p: Desktop) @This() {
        const cross: *Cross = @ptrCast(@alignCast(p.userdata));
        return if (build_options.glfw) .{ .inner = .{} } else switch (builtin.os.tag) {
            .windows => .{ .inner = .{} },
            .macos, .ios, .tvos => .{ .inner = .{} },
            else => if (is_wasm)
                .{ .inner = .{} }
            else switch (cross.inner) {
                .wayland => if (build_options.wayland_backend != .none) .{ .inner = .{ .wayland = .{} } } else unreachable,
                .x => if (build_options.x_backend != .none) .{ .inner = .{ .x = .{} } } else unreachable,
            },
        };
    }

    pub fn interface(self: *@This(), p: Desktop) *DesktopWindow {
        const cross: *Cross = @ptrCast(@alignCast(p.userdata));
        return if (build_options.glfw) &self.inner.interface else switch (builtin.os.tag) {
            .windows => &self.inner.interface,
            .macos, .ios, .tvos => &self.inner.interface,
            else => if (is_wasm)
                &self.inner.interface
            else switch (cross.inner) {
                .wayland => if (build_options.wayland_backend != .none) &self.inner.wayland.interface else unreachable,
                .x => if (build_options.x_backend != .none) &self.inner.x.interface else unreachable,
            },
        };
    }
};

pub fn init(gpa: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    return if (build_options.glfw) .{ .inner = try Desktop.Glfw.init(gpa) } else switch (builtin.os.tag) {
        .windows => .{ .inner = try Desktop.Win32.init(gpa) },
        .macos, .ios, .tvos => .{ .inner = try Desktop.Cocoa.init() },
        else => if (is_wasm)
            .{ .inner = try Desktop.Web.init() }
        else
            try initUnix(gpa, io, minimal),
    };
}

fn initUnix(gpa: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    const session_type: Desktop.unix.SessionType =
        if (build_options.wayland_backend != .none and build_options.x_backend != .none)
            Desktop.unix.SessionType.detect(minimal) orelse .wayland
        else if (build_options.wayland_backend != .none) .wayland else if (build_options.x_backend != .none) .x11 else @compileError("no x or wayland backend available");

    return switch (session_type) {
        .wayland => .{ .inner = .{ .wayland = try switch (build_options.wayland_backend) {
            .none => return error.WaylandUnsupported,
            .libwayland => Desktop.Wayland.connect(gpa),
        } } },
        .x11 => .{ .inner = .{ .x = try switch (build_options.x_backend) {
            .none => return error.XUnsupported,
            .xcb => Desktop.Xcb.connect(gpa, minimal),
            .xlib => Desktop.Xlib.open(),
            .xpz => Desktop.Xpz.connect(gpa, io, minimal),
        } } },
        else => error.UnsupportedPlatform,
    };
}

pub fn deinit(self: *@This()) void {
    if (build_options.glfw) self.inner.deinit() else switch (builtin.os.tag) {
        .windows => {},
        .macos, .ios, .tvos => self.inner.deinit(),
        else => if (is_wasm)
            self.inner.deinit()
        else switch (self.inner) {
            .wayland => if (build_options.wayland_backend != .none) self.inner.wayland.disconnect(),
            .x => if (build_options.x_backend != .none) self.inner.x.disconnect(),
        },
    }
}

pub fn desktop(self: *@This()) Desktop {
    return if (build_options.glfw) self.inner.platform() else switch (builtin.os.tag) {
        .windows => self.inner.platform(),
        .macos, .ios, .tvos => self.inner.platform(),
        else => if (is_wasm)
            self.inner.platform()
        else switch (self.inner) {
            .wayland => if (build_options.wayland_backend != .none) self.inner.wayland.desktop() else unreachable,
            .x => if (build_options.x_backend != .none) self.inner.x.desktop() else unreachable,
        },
    };
}
