const Window = @This();

const std = @import("std");
const builtin = @import("builtin");
const Desktop = @import("Desktop.zig");
const opengl = @import("opengl.zig");

size: Size = .{},
position: Position = .{},
mode: Property.Mode = .windowed,
unminimized_mode: Property.Mode = .windowed,
focused: bool = false,
surface_type: SurfaceType = .empty,
keyboard: Keyboard = .empty,
mouse_position: Event.MouseMotion = .{},

pub const Event = @import("Window/event.zig").Event;
pub const Keyboard = @import("Window/Keyboard.zig");

pub const Size = packed struct(u64) {
    width: u32 = 0,
    height: u32 = 0,

    pub fn eql(a: Size, b: Size) bool {
        return a.width == b.width and a.height == b.height;
    }

    pub fn aspect(self: Size) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }

    /// Can be constructed into @Vector or [2]u32
    pub fn toTuple(self: Size) struct { u32, u32 } {
        return .{ self.width, self.height };
    }
};

pub const Position = packed struct(i64) {
    x: i32 = 0,
    y: i32 = 0,

    pub fn eql(a: Position, b: Position) bool {
        return a.x == b.x and a.y == b.y;
    }

    /// Can be constructed into @Vector or [2]i32
    pub fn toTuple(self: Position) struct { i32, i32 } {
        return .{ self.x, self.y };
    }
};

pub const Native = switch (builtin.os.tag) {
    .windows => struct {
        hinstance: std.os.windows.HINSTANCE,
        hwnd: std.os.windows.HWND,
    },
    .macos => struct {
        ns_app: *anyopaque, // NSApplication*
        ns_window: *anyopaque, // NSWindow*
        ns_view: *anyopaque, // NSView* (or CAMetalLayer host)
    },
    .ios => struct {
        ui_app: *anyopaque, // UIApplication*
        ui_window: *anyopaque, // UIWindow*
        ui_view: *anyopaque, // UIView*
    },

    .linux, .freebsd, .netbsd, .openbsd => if (builtin.abi == .android) struct {
        app: *anyopaque, // android_app*
        window: *anyopaque, // ANativeWindow*
        activity: *anyopaque, // ANativeActivity*
    } else union(enum) {
        wayland: struct {
            display: *anyopaque,
            surface: *anyopaque,
            compositor: *anyopaque,
        },
        x11: struct {
            display: *anyopaque,
            window: u64,
            screen: i32,
        },
        drm: struct {
            fd: std.posix.fd_t,
            crtc_id: u32,
            connector_id: u32,
        },
    },

    .haiku => struct {
        app: *anyopaque, // BApplication*
        window: *anyopaque, // BWindow*
        view: *anyopaque, // BView*
    },

    .emscripten => struct {
        canvas: []const u8, // HTML canvas selector (e.g. "#canvas")
    },

    else => struct {},
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

        pub const rgba: Format = .{ .r = 0, .g = 1, .b = 2, .a = 3 };
        pub const argb: Format = .{ .r = 1, .g = 2, .b = 3, .a = 0 };
        pub const bgra: Format = .{ .r = 2, .g = 1, .b = 0, .a = 3 };
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

    pub const default: Cursor = .arrow;
};

pub const Property = union(enum) {
    title: [:0]const u8,
    size: Window.Size,
    position: Window.Position,
    resize_policy: ResizePolicy,
    mode: Mode,
    focused: bool,
    always_on_top: bool,
    floating: bool,
    decorated: bool,
    cursor: Cursor,

    pub const Mode = enum {
        windowed,
        fullscreen,
        maximized,
        minimized,
    };
};

pub const OpenOptions = struct {
    title: [:0]const u8,
    size: Size,
    position: ?Position = null,
    resize_policy: ResizePolicy = .{ .resizable = true },
    decorated: bool = true,
    surface_type: SurfaceType = .empty,
};

pub fn open(window: *Window, desktop: Desktop, options: OpenOptions) anyerror!void {
    if (builtin.os.tag.isDarwin()) switch (options.surface_type) {
        .opengl => |gl| if (gl.major == 4) std.debug.assert(gl <= 1),
        else => {},
    };
    window.size = options.size;
    window.position = options.position orelse .{};
    window.surface_type = options.surface_type;
    try desktop.vtable.windowOpen(desktop.userdata, window, options);
}
pub fn close(window: *Window, desktop: Desktop) void {
    desktop.vtable.windowClose(desktop.userdata, window);
}
pub fn poll(window: *Window, desktop: Desktop) anyerror!?Event {
    const event = try desktop.vtable.windowPoll(desktop.userdata, window) orelse return null;
    switch (event) {
        .resize => |size| window.size = size,
        .move => |position| window.position = position,
        .focus => |focus| {
            if (!focus) window.keyboard = .empty;
            window.focused = focus;
        },
        .key => |key| {
            if (key.state == window.keyboard.get(key.sym)) return window.poll(desktop);
            window.keyboard.set(key.sym, key.state);
        },
        .mouse_motion => |motion| window.mouse_position = motion,
        else => {},
    }
    return event;
}

pub fn setProperties(window: *Window, desktop: Desktop, properties: []const Property) anyerror!void {
    for (properties) |property| try desktop.vtable.windowSetProperty(desktop.userdata, window, property);
}

pub fn native(window: *Window, desktop: Desktop) Native {
    return desktop.vtable.windowNative(desktop.userdata, window);
}

pub fn setTitle(window: *Window, desktop: Desktop, title: [:0]const u8) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .title = title });
}
pub fn setSize(window: *Window, desktop: Desktop, size: Size) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .size = size });
}
pub fn setPosition(window: *Window, desktop: Desktop, position: Position) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .position = position });
}
pub fn setResizePolicy(window: *Window, desktop: Desktop, resize_policy: ResizePolicy) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .resize_policy = resize_policy });
}
pub fn setMode(window: *Window, desktop: Desktop, mode: Window.Property.Mode) anyerror!void {
    if (mode == window.unminimized_mode) return;
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .mode = mode });
    window.mode = mode;
    if (mode != .minimized) window.unminimized_mode = mode;
}
pub fn setFocused(window: *Window, desktop: Desktop, focused: bool) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .focused = focused });
}
pub fn setAlwaysOnTop(window: *Window, desktop: Desktop, always_on_top: bool) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .always_on_top = always_on_top });
}
pub fn setFloating(window: *Window, desktop: Desktop, floating: bool) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .floating = floating });
}
pub fn setDecorated(window: *Window, desktop: Desktop, decorated: bool) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .decorated = decorated });
}
pub fn setCursor(window: *Window, desktop: Desktop, cursor: Cursor) anyerror!void {
    try desktop.vtable.windowSetProperty(desktop.userdata, window, .{ .cursor = cursor });
}

/// Returns a pointer to the current framebuffer for the given window.
/// Note: The framebuffer pointer may change after a resize event,
/// so it’s best to retrieve it either each time it’s needed or on each resize event.
pub fn framebuffer(window: *Window, desktop: Desktop) anyerror!Framebuffer {
    if (window.surface_type != .framebuffer) return error.WrongSurfaceType;
    return desktop.vtable.windowFramebuffer(desktop.userdata, window);
}
