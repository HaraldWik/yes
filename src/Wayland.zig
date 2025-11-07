const std = @import("std");
const root = @import("root.zig");
const c = @cImport({ // TODO: Remove C import
    @cInclude("wayland-client.h");
    @cInclude("wayland-egl.h");
});
// const wayland = @import("wayland");

display: *c.wl_display = undefined,
compositor: *c.wl_compositor = undefined,
surface: *c.wl_surface = undefined,

pub fn open(self: *@This(), config: root.Window.Config) !void {
    _ = config;

    const display: *c.wl_display = c.wl_display_connect(null) orelse return error.ConnectDisplay;
    self.display = display;

    const registry: *c.wl_registry = c.wl_display_get_registry(display) orelse return error.GetDisplayRegistry;
    _ = c.wl_registry_add_listener(registry, &c.wl_registry_listener{ .global = @ptrCast(&initRegistry), .global_remove = @ptrCast(&deinitRegistry) }, @ptrCast(self));
    _ = c.wl_display_roundtrip(display);

    const surface: *c.wl_surface = c.wl_compositor_create_surface(@ptrCast(self.compositor)) orelse return error.CreateSurface;
    self.surface = surface;

    return error.NotImplemented;

    // const window: c.wl_egl_window = undefined;
}

pub fn close(self: @This()) void {
    c.wl_surface_destroy(self.surface);
    c.wl_display_disconnect(self.display);
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

fn initRegistry(self: *@This(), registry: *c.wl_registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void {
    _ = version;

    if (std.mem.eql(u8, std.mem.span(interface), std.mem.span(c.wl_compositor_interface.name)))
        self.compositor = @ptrCast(c.wl_registry_bind(registry, name, &c.wl_compositor_interface, 4));

    std.debug.print("{d}\n", .{name});
}
fn deinitRegistry(self: *@This(), registry: *c.wl_registry, name: u32) callconv(.c) void {
    _ = self;
    _ = registry;
    _ = name;
}
