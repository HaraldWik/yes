const std = @import("std");
const root = @import("../root.zig");

// https://nilsbrause.github.io/waylandpp_docs/egl_8cpp-example.html
// Last supported branch https://github.com/HaraldWik/yes/tree/7699b77785f641670d1b320c3d548466a6eaa4a2 will be re implemented

display: *anyopaque,
surface: *anyopaque,
api: struct { opengl: struct {
    display: *anyopaque,
    surface: *anyopaque,
} },

pub const wl = struct {
    pub fn wl_surface_commit(_: *anyopaque) void {}
    pub fn wl_display_flush(_: *anyopaque) i32 {
        return 0;
    }
};

pub fn open(config: root.Window.Config) !@This() {
    _ = config;
    return error.NotImplemented;
}

pub fn close(_: @This()) void {}

pub fn poll(_: @This()) ?root.Event {
    return null;
}

pub fn getSize(self: @This()) root.Window.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}
