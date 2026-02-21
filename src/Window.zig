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
};

pub const Property = union(enum) {
    title: []const u8,
    size: Window.Size,
    position: Window.Position,
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
