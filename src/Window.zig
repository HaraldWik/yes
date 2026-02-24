const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("Platform.zig");

const Window = @This();

size: Size = .{},
position: Position = .{},

pub const Event = @import("event.zig").Event;

pub const Size = extern struct {
    width: u32 = 0,
    height: u32 = 0,
};

pub const Position = extern struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const OpenOptions = struct {
    title: []const u8,
    size: Size,
    position: Position = .{},
    min_size: ?Size = null,
    max_size: ?Size = null,
    resizable: bool = true,
    decoration: bool = true,
    surface_type: SurfaceType = .empty,

    pub const SurfaceType = switch (builtin.os.tag) {
        .windows => union(enum) {
            empty,
            framebuffer,
            opengl: std.SemanticVersion,
            vulkan: std.SemanticVersion,
            direct3d: std.SemanticVersion,
        },
        .macos, .ios => union(enum) {
            empty,
            framebuffer,
            opengl: std.SemanticVersion,
            metal: std.SemanticVersion,
        },
        else => union(enum) {
            empty,
            framebuffer,
            opengl: std.SemanticVersion,
            vulkan: std.SemanticVersion,
        },
    };
};

pub const Property = union(enum) {
    title: []const u8,
    size: Window.Size,
    position: Window.Position,
    fullscreen: bool,
    maximize: bool,
    minimize: bool,
    always_on_top: bool,
    floating: bool,
};

pub fn open(w: *Window, p: Platform, options: OpenOptions) anyerror!void {
    try p.vtable.windowOpen(p.ptr, w, options);
}
pub fn close(w: *Window, p: Platform) void {
    p.vtable.windowClose(p.ptr, w);
}
pub fn poll(w: *Window, p: Platform) anyerror!?Event {
    const event = try p.vtable.windowPoll(p.ptr, w) orelse return null;
    switch (event) {
        .resize => |size| w.size = size,
        else => {},
    }
    return event;
}
pub fn setTitle(w: *Window, p: Platform, title: []const u8) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .title = title });
}
pub fn setSize(w: *Window, p: Platform, size: Size) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .size = size });
}
pub fn setPosition(w: *Window, p: Platform, position: Position) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .position = position });
}
pub fn setFullscreen(w: *Window, p: Platform, fullscreen: bool) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .fullscreen = fullscreen });
}
pub fn setMaximize(w: *Window, p: Platform, maximize: bool) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .maximize = maximize });
}
pub fn setMinimize(w: *Window, p: Platform, minimize: bool) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .minimize = minimize });
}
pub fn setAlwaysOnTop(w: *Window, p: Platform, always_on_top: bool) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .always_on_top = always_on_top });
}
pub fn setFloating(w: *Window, p: Platform, floating: bool) anyerror!void {
    try p.vtable.windowSetProperty(p.ptr, w, .{ .floating = floating });
}
