const std = @import("std");
const builtin = @import("builtin");
const Platform = @import("Platform.zig");
const opengl = @import("opengl.zig");

const Window = @This();

size: Size = .{},
position: Position = .{},
focus: Focus = .focused,
surface_type: SurfaceType = .empty,
keyboard: Keyboard = .empty,

pub const Event = @import("Window/event.zig").Event;
pub const Keyboard = @import("Window/Keyboard.zig");

pub const Size = packed struct(u64) {
    width: u32 = 0,
    height: u32 = 0,

    pub fn eql(a: @This(), b: @This()) bool {
        return a.width == b.width and a.height == b.height;
    }

    pub fn aspect(self: @This()) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }

    /// Can be constructed into @Vector or [2]u32
    pub fn toTuple(self: @This()) struct { u32, u32 } {
        return .{ self.width, self.height };
    }
};

pub const Position = packed struct(i64) {
    x: i32 = 0,
    y: i32 = 0,

    pub fn eql(a: @This(), b: @This()) bool {
        return a.x == b.x and a.y == b.y;
    }

    /// Can be constructed into @Vector or [2]i32
    pub fn toTuple(self: @This()) struct { i32, i32 } {
        return .{ self.x, self.y };
    }
};

pub const Framebuffer = struct {
    pixels: switch (builtin.os.tag) {
        .windows => [*]align(std.heap.page_size_min) u8,
        .macos, .ios => [*]u8,
        else => [*]align(std.heap.page_size_min) u8,
    },

    const Format = struct {
        r: usize,
        g: usize,
        b: usize,
        a: usize,

        pub const rgba: @This() = .{ .r = 0, .g = 1, .b = 2, .a = 3 };
        pub const argb: @This() = .{ .r = 1, .g = 2, .b = 3, .a = 0 };
        pub const bgra: @This() = .{ .r = 2, .g = 1, .b = 0, .a = 3 };
    };

    pub const format: Format = switch (builtin.os.tag) {
        .windows, .macos, .ios => .bgra, // little-endian BGRA
        else => if (builtin.cpu.arch.endian() == .big) .argb else .bgra,
    };
};
pub const SurfaceType = switch (builtin.os.tag) {
    .windows => union(enum) {
        empty,
        framebuffer,
        opengl: opengl.Version,
        vulkan,
        /// Example version 12 or 11
        direct3d: u8,
    },
    .macos, .ios => union(enum) {
        empty,
        framebuffer,
        /// Max version is 4.1
        opengl: opengl.Version,
        metal,
    },
    else => union(enum) {
        empty,
        framebuffer,
        opengl: opengl.Version,
        vulkan,
    },
};

pub const ResizePolicy = union(enum) {
    resizable: bool,
    specified: Specified,

    pub const Specified = struct {
        max_size: ?Window.Size = null,
        min_size: ?Window.Size = null,
    };
};

pub const Focus = enum(u1) {
    focused,
    unfocused,
};

pub const Cursor = enum(u32) {
    arrow = 1,
    text = 9,
    hand = 16,
    grab = 17,
    crosshair = 8,
    wait = 6,
    resize_ns = 27, // horizontal
    resize_ew = 26, // vertical
    resize_nesw = 28, // top-left  ↘ bottom-right
    resize_nwse = 29, // top-right ↙ bottom-left
    forbidden = 15,
    move = 13,
    _, // Incase you want a platform specific one

    pub const default: @This() = .arrow;
};

pub const Property = union(enum) {
    title: []const u8,
    size: Window.Size,
    position: Window.Position,
    resize_policy: ResizePolicy,
    fullscreen: bool,
    maximized: bool,
    minimized: bool,
    focus: Focus,
    always_on_top: bool,
    floating: bool,
    decorated: bool,
    cursor: Cursor,
};

pub const OpenOptions = struct {
    title: []const u8,
    size: Size,
    position: ?Position = null,
    resize_policy: ResizePolicy = .{ .resizable = true },
    fullscreen: bool = false,
    maximized: bool = false,
    minimized: bool = false,
    focus: Focus = .focused,
    always_on_top: bool = false,
    floating: ?bool = null,
    decorated: bool = true,
    surface_type: SurfaceType = .empty,
};

pub fn open(window: *Window, platform: Platform, options: OpenOptions) anyerror!void {
    if (builtin.os.tag.isDarwin()) switch (options.surface_type) {
        .opengl => |gl| if (gl.major == 4) std.debug.assert(gl <= 1),
        else => {},
    };
    window.size = options.size;
    window.position = options.position orelse .{};
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
        .move => |position| window.position = position,
        .focus => |focus| {
            if (focus == .unfocused) window.keyboard = .empty;
            window.focus = focus;
        },
        .key => |key| {
            if (key.state == window.keyboard.get(key.sym)) return window.poll(platform);
            window.keyboard.set(key.sym, key.state);
        },
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
pub fn setMaximized(window: *Window, platform: Platform, maximize: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .maximized = maximize });
}
pub fn setMinimized(window: *Window, platform: Platform, minimize: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .minimized = minimize });
}
pub fn setFocus(window: *Window, platform: Platform, focus: Focus) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .focus = focus });
}
pub fn setAlwaysOnTop(window: *Window, platform: Platform, always_on_top: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .always_on_top = always_on_top });
}
pub fn setFloating(window: *Window, platform: Platform, floating: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .floating = floating });
}
pub fn setDecorated(window: *Window, platform: Platform, decorated: bool) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .decorated = decorated });
}
pub fn setCursor(window: *Window, platform: Platform, cursor: Cursor) anyerror!void {
    try platform.vtable.windowSetProperty(platform.ptr, window, .{ .cursor = cursor });
}

/// Returns a pointer to the current framebuffer for the given window.
/// Note: The framebuffer pointer may change after a resize event,
/// so it’s best to retrieve it either each time it’s needed or on each resize event.
pub fn framebuffer(window: *Window, platform: Platform) anyerror!Framebuffer {
    if (window.surface_type != .framebuffer) return error.WrongSurfaceType;
    return platform.vtable.windowFramebuffer(platform.ptr, window);
}
