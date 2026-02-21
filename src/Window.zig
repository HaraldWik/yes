const Platform = @import("Platform.zig");

const Window = @This();

keyboard: [256]bool = @splat(false),
size: Size = .{},

pub const Size = extern struct {
    width: u32 = 0,
    height: u32 = 0,
};

pub const OpenOptions = struct {
    title: []const u8,
    size: Size,
};

pub const Event = union(enum) {
    close,
    resize: Size,
    focus: Focus,

    pub const Focus = enum {
        enter,
        leave,
    };
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
    try p.vtable.windowSetTitle(p.ptr, w, title);
}
