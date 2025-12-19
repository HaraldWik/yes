const std = @import("std");
const Monitor = @import("Monitor.zig");
const wl = @import("wayland");

var monitors: std.ArrayList(Monitor) = .empty;

fn output_geometry(
    data: *anyopaque,
    _: *wl.wl_output,
    x: i32,
    y: i32,
    physical_width: i32,
    physical_height: i32,
    _: wl.wl_output_subpixel,
    make: [*:0]const u8,
    model: [*:0]const u8,
    transform: wl.wl_output_transform,
) callconv(.c) void {
    // wl.WL_OUTPUT_TRANSFORM_180
    _ = physical_width;
    _ = physical_height;
    const monitor: *Monitor = @ptrCast(@alignCast(data));
    monitor.position = .{ .x = x, .y = y };
    monitor.orientation = @enumFromInt(transform);
    monitor.manufacturer = .{ .model = std.mem.span(model), .name = std.mem.span(make) };
}

fn output_mode(
    data: ?*anyopaque,
    _: *wl.wl_output,
    flags: u32,
    width: i32,
    height: i32,
    _: i32,
) callconv(.c) void {
    if ((flags & wl.WL_OUTPUT_MODE_CURRENT) != 0) {
        const monitor: *Monitor = @ptrCast(@alignCast(data.?));
        monitor.size = .{ .width = @intCast(width), .height = @intCast(height) };
    }
}

fn output_scale(data: ?*anyopaque, _: *wl.wl_output, factor: i32) callconv(.c) void {
    const m: *Monitor = @ptrCast(@alignCast(data.?));
    m.scale = @floatCast(wl.wl_fixed_to_double(factor));
}

fn output_done(_: ?*anyopaque, _: *wl.wl_output) callconv(.c) void {}

const output_listener = wl.wl_output_listener{
    .geometry = @ptrCast(&output_geometry),
    .mode = @ptrCast(&output_mode),
    .done = @ptrCast(&output_done),
    .scale = @ptrCast(&output_scale),
};

fn registry_global(
    _: ?*anyopaque,
    registry: *wl.wl_registry,
    name: u32,
    interface: [*:0]const u8,
    _: u32,
) callconv(.c) void {
    const iface = std.mem.span(interface);

    if (std.mem.eql(u8, iface, "wl_output")) {
        monitors.appendAssumeCapacity(Monitor{});
        const m = &monitors.items[monitors.items.len - 1];

        const output: *wl.wl_output = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_output_interface, 2));

        _ = wl.wl_output_add_listener(output, &output_listener, m);
    }
}

fn registry_remove(
    _: ?*anyopaque,
    _: *wl.wl_registry,
    _: u32,
) callconv(.c) void {}

const registry_listener = wl.wl_registry_listener{
    .global = @ptrCast(&registry_global),
    .global_remove = @ptrCast(&registry_remove),
};

pub fn get(index: usize, buffer: []u8) !?Monitor {
    _ = buffer;
    monitors = try .initCapacity(std.heap.page_allocator, 12);
    defer monitors.deinit(std.heap.page_allocator);
    const display = wl.wl_display_connect(null) orelse
        return error.NoWaylandDisplay;

    defer wl.wl_display_disconnect(display);

    const registry = wl.wl_display_get_registry(display);
    _ = wl.wl_registry_add_listener(registry, &registry_listener, null);

    _ = wl.wl_display_roundtrip(display);
    _ = wl.wl_display_roundtrip(display);

    if (index >= monitors.items.len) return null;

    return monitors.items[index];
}
