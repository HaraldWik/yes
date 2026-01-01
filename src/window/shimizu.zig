const std = @import("std");
const Window = @import("Window.zig");
const shimizu = @import("shimizu");
const wp = @import("wayland-protocols");
const xdg_shell = wp.xdg_shell;

pub fn open(config: Window.Config) !@This() {
    _ = config;
}

pub fn close(self: @This()) void {
    _ = self;
}

pub fn poll(self: *@This()) !?Window.io.Event {
    _ = self;
    return null;
}

pub fn getSize(self: @This()) Window.Size {
    _ = self;
    return .{};
}

pub fn setTitle(self: @This(), title: [:0]const u8) void {
    _ = self;
    _ = title;
}

pub fn fullscreen(self: *@This(), state: bool) void {
    _ = self;
    _ = state;
}

pub fn maximize(self: @This(), state: bool) void {
    _ = self;
    _ = state;
}

pub fn minimize(self: @This()) void {
    _ = self;
}

pub fn setPosition(self: @This(), position: Window.Position(i32)) !void {
    _ = self;
    _ = position;
}
