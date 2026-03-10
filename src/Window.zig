const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("Platform.zig");
const opengl = @import("opengl.zig");

const Window = @This();

size: Size = .{},
position: Position = .{},
surface_type: SurfaceType = .empty,

pub const Event = @import("event.zig").Event;

pub const Size = extern struct {
    width: u32 = 0,
    height: u32 = 0,

    pub fn eql(a: @This(), b: @This()) bool {
        return a.width == b.width and a.height == b.height;
    }

    pub fn aspect(self: @This()) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }
};

pub const Position = extern struct {
    x: i32 = 0,
    y: i32 = 0,

    pub fn eql(a: @This(), b: @This()) bool {
        return a.x == b.x and a.y == b.y;
    }
};

pub const SurfaceType = switch (builtin.os.tag) {
    .windows => union(enum) {
        empty,
        software,
        opengl: opengl.Version,
        vulkan,
        /// Example version 12 or 11
        direct3d: u8,
    },
    .macos, .ios => union(enum) {
        empty,
        software,
        /// Max version is 4.1
        opengl: opengl.Version,
        metal,
    },
    else => union(enum) {
        empty,
        software,
        opengl: opengl.Version,
        vulkan,
    },
};

pub const ResizePolicy = union(enum) {
    resizable: bool,
    specified: Specified,

    pub const Specified = struct {
        max_size: ?Window.Size,
        min_size: ?Window.Size,
    };
};

pub const Property = union(enum) {
    title: []const u8,
    size: Window.Size,
    position: Window.Position,
    resize_policy: ResizePolicy,
    fullscreen: bool,
    maximize: bool,
    minimize: bool,
    always_on_top: bool,
    floating: bool,
};

pub const OpenOptions = struct {
    title: []const u8,
    size: Size,
    position: Position = .{},
    resize_policy: ResizePolicy,
    decoration: bool = true,
    surface_type: SurfaceType = .empty,
};

pub fn open(window: *Window, platform: Platform, options: OpenOptions) anyerror!void {
    window.surface_type = options.surface_type;
    try platform.vtable.windowOpen(platform.ptr, window, options);
}
pub fn close(window: *Window, platform: Platform) void {
    platform.vtable.windowClose(platform.ptr, window);
}
pub fn poll(window: *Window, platform: Platform) anyerror!?Event {
    const event = try platform.vtable.windowPoll(platform.ptr, window) orelse return null;
    switch (event) {
        .resize => |size| window.size = size,
        else => {},
    }
    return event;
}

pub fn setProperties(window: *Window, platform: Platform, properties: []const Property) anyerror!void {
    for (properties) |property| try platform.vtable.windowSetProperty(platform.ptr, window, property);
}

pub fn setTitle(window: *Window, platform: Platform, title: []const u8) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .title = title });
}
pub fn setSize(window: *Window, platform: Platform, size: Size) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .size = size });
}
pub fn setPosition(window: *Window, platform: Platform, position: Position) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .position = position });
}
pub fn setResizePolicy(window: *Window, platform: Platform, resize_policy: ResizePolicy) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .resize_policy = resize_policy });
}
pub fn setFullscreen(window: *Window, platform: Platform, fullscreen: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .fullscreen = fullscreen });
}
pub fn setMaximize(window: *Window, platform: Platform, maximize: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .maximize = maximize });
}
pub fn setMinimize(window: *Window, platform: Platform, minimize: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .minimize = minimize });
}
pub fn setAlwaysOnTop(window: *Window, platform: Platform, always_on_top: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .always_on_top = always_on_top });
}
pub fn setFloating(window: *Window, platform: Platform, floating: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .floating = floating });
}
