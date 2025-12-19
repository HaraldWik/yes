const std = @import("std");
const Monitor = @import("Monitor.zig");
const wl = @import("wayland");

const output = struct {
    const listener: *const wl.wl_output_listener = &.{
        .geometry = @ptrCast(&outputGeometry),
        .mode = @ptrCast(&outputMode),
        .done = @ptrCast(&outputDone),
        .scale = @ptrCast(&outputScale),
    };

    fn outputGeometry(monitor: *Monitor, _: *wl.wl_output, x: i32, y: i32, physical_width: i32, physical_height: i32, _: wl.wl_output_subpixel, make: [*:0]const u8, _: [*:0]const u8, transform: wl.wl_output_transform) callconv(.c) void {
        monitor.name = std.mem.span(make);
        monitor.physical_size = .{ .width = @intCast(physical_width), .height = @intCast(physical_height) };
        monitor.position = .{ .x = x, .y = y };
        monitor.orientation = @enumFromInt(transform);
    }

    fn outputMode(monitor: *Monitor, _: *wl.wl_output, flags: u32, width: i32, height: i32, _: i32) callconv(.c) void {
        if ((flags & wl.WL_OUTPUT_MODE_CURRENT) != 0) monitor.size = .{ .width = @intCast(width), .height = @intCast(height) };
    }

    fn outputScale(data: ?*anyopaque, _: *wl.wl_output, factor: i32) callconv(.c) void {
        const m: *Monitor = @ptrCast(@alignCast(data.?));
        m.scale = @floatFromInt(factor);
    }

    fn outputDone(_: ?*anyopaque, _: *wl.wl_output) callconv(.c) void {}
};

const registry = struct {
    const listener: *const wl.wl_registry_listener = &.{
        .global = @ptrCast(&global),
        .global_remove = @ptrCast(&remove),
    };

    fn global(monitors: *std.ArrayList(Monitor), registry_handle: *wl.wl_registry, name: u32, interface: [*:0]const u8, _: u32) callconv(.c) void {
        const iface = std.mem.span(interface);

        if (std.mem.eql(u8, iface, "wl_output")) {
            monitors.appendAssumeCapacity(Monitor{});
            const monitor = &monitors.items[monitors.items.len - 1];

            _ = wl.wl_output_add_listener(@ptrCast(wl.wl_registry_bind(registry_handle, name, &wl.wl_output_interface, 2)), output.listener, monitor);
        }
    }

    fn remove(_: ?*anyopaque, _: *wl.wl_registry, _: u32) callconv(.c) void {}
};

pub fn get(index: usize, buffer: []u8) !?Monitor {
    _ = buffer;
    var monitors_buffer: [12]Monitor = undefined;
    var monitors: std.ArrayList(Monitor) = .initBuffer(&monitors_buffer);
    const display = wl.wl_display_connect(null) orelse return error.NoWaylandDisplay;
    defer wl.wl_display_disconnect(display);

    const registry_handle = wl.wl_display_get_registry(display);
    _ = wl.wl_registry_add_listener(registry_handle, registry.listener, &monitors);

    _ = wl.wl_display_roundtrip(display);
    _ = wl.wl_display_roundtrip(display);

    if (index >= monitors.items.len) return null;

    return monitors.items[index];
}
