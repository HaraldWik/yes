const Cocoa = @This();

const std = @import("std");
const vulkan = @import("../root.zig").vulkan;
const Desktop = @import("../Desktop.zig");
const DesktopWindow = @import("../Window.zig");

pub const Window = struct {
    interface: DesktopWindow = .{},
};

pub fn init() !Cocoa {}

pub fn deinit(self: Cocoa) void {
    _ = self;
}

pub fn desktop(self: *Cocoa) Desktop {
    return .{
        .userdata = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowNative = windowNative,
            .windowFramebuffer = windowFramebuffer,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = undefined,
        },
    };
}

fn windowOpen(userdata: ?*anyopaque, desktop_window: *DesktopWindow, options: DesktopWindow.OpenOptions) anyerror!void {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
    _ = options;
}
fn windowClose(userdata: ?*anyopaque, desktop_window: *DesktopWindow) void {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
}
fn windowPoll(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!?DesktopWindow.Event {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;

    return .close;
}
fn windowSetProperty(userdata: ?*anyopaque, desktop_window: *DesktopWindow, property: DesktopWindow.Property) anyerror!void {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;

    switch (property) {
        .title => {},
        .size => {},
        .position => {},
        .resize_policy => |resize_policy| switch (resize_policy) {
            .resizable => |resizable| {
                _ = resizable;
            },
            .specified => |specified| {
                _ = specified;
            },
        },
        .mode => {},
        .always_on_top => {},
        .floating => {},
        .decorated => {},
        .focused => {},
        .cursor => {},
    }
}
fn windowNative(userdata: ?*anyopaque, desktop_window: *DesktopWindow) DesktopWindow.Native {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;

    unreachable;
}
fn windowFramebuffer(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!DesktopWindow.Framebuffer {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
    return .{ .pixels = undefined };
}
fn windowOpenglMakeCurrent(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!void {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapBuffers(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!void {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapInterval(userdata: ?*anyopaque, desktop_window: *DesktopWindow, interval: i32) anyerror!void {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
    _ = interval;
}
fn windowVulkanCreateSurface(userdata: ?*anyopaque, desktop_window: *DesktopWindow, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque {
    const self: *Cocoa = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    _ = self;
    _ = window;
    _ = instance;
    _ = allocator;
    _ = loader;

    return undefined;
}
