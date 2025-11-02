const std = @import("std");
const root = @import("root.zig");
const c = @cImport(@cInclude("wayland-client.h")); // TODO: Remove C import

pub fn open(config: root.Window.Config) !@This() {
    _ = config;

    return .{};
}

pub fn close(self: @This()) void {
    _ = self;
}

pub fn next(self: @This()) ?root.Event {
    _ = self;
    return null;
}

pub fn getSize(self: @This()) [2]usize {
    _ = self;
    return .{ 0, 0 };
}

pub fn isKeyDown(self: @This(), key: root.Key) bool {
    _ = self;
    _ = key;
    return false;
}
