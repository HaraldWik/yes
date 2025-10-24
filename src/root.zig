const std = @import("std");
const builtin = @import("builtin");

const native_os = builtin.os.tag;

pub const Windows = @import("Windows.zig");
pub const X11 = @import("X11.zig");

pub const Window = struct {
    handle: Handle,

    pub const Handle = switch (native_os) {
        .windows => Windows,
        else => X11,
    };

    pub const Config = struct {
        title: [:0]const u8,
        width: usize,
        height: usize,
        min_width: ?usize = null,
        min_height: ?usize = null,
        max_width: ?usize = null,
        max_height: ?usize = null,
        resizable: bool = true,
    };

    pub fn open(config: Config) !@This() {
        const handle: Handle = switch (native_os) {
            .windows => try Windows.open(config),
            else => try X11.open(config),
        };
        return .{ .handle = handle };
    }

    pub fn close(self: @This()) void {
        self.handle.close();
    }

    pub fn next(self: @This()) ?Event {
        return self.handle.next();
    }
};

pub const Event = union(enum) {
    none: void,
};
