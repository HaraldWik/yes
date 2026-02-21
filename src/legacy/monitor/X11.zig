const std = @import("std");
const Monitor = @import("Monitor.zig");
const x11 = @import("x11");

pub fn get(index: usize, buffer: []u8) !?Monitor {
    const display: *x11.Display = x11.XOpenDisplay(null).?;
    const root: x11.Window = x11.DefaultRootWindow(display);

    var count: c_int = undefined;
    const monitors: [*]x11.XRRMonitorInfo = x11.XRRGetMonitors(display, root, x11.True, &count);
    defer x11.XRRFreeMonitors(monitors);

    if (index > @as(usize, @intCast(count))) return null;

    const monitor: x11.XRRMonitorInfo = monitors[index];
    // TODO: add this ig
    // var orientation: Monitor.Orientation = .@"0";

    // if (monitor.noutput > 0) {
    //     const output_id = monitor.outputs[0];
    //     const screen_res = x11.XRRGetScreenResourcesCurrent(display, root);
    //     defer x11.XRRFreeScreenResources(screen_res);
    //     const out_info = x11.XRRGetOutputInfo(display, screen_res, output_id);
    //     defer x11.XRRFreeOutputInfo(out_info);

    //     // Copy name into buffer
    //     // var name_len: usize = 0;
    //     // while (name_len < buffer.len and out_info.name[name_len] != 0) name_len += 1;
    //     // @memcpy(buffer[0..name_len], out_info.name[0..name_len]);
    //     _ = buffer;

    //     // Rotation from associated CRTC
    //     if (out_info.*.crtc != 0) {
    //         const crtc_info = x11.XRRGetCrtcInfo(display, screen_res, out_info.*.crtc);
    //         if (crtc_info != null) {
    //             defer x11.XRRFreeCrtcInfo(crtc_info);
    //             orientation = .fromX11(crtc_info.*.rotation);
    //         }
    //     }
    // }
    const name = try std.fmt.bufPrint(buffer, "{d:.2}", .{monitor.name});
    return .{
        .name = name,
        .size = .{ .width = @intCast(monitor.width), .height = @intCast(monitor.height) },
        .position = .{ .x = @intCast(monitor.x), .y = @intCast(monitor.y) },
        .physical_size = .{ .width = @intCast(monitor.mwidth), .height = @intCast(monitor.mheight) },
        .scale = if (monitor.mwidth != 0 and monitor.mheight != 0)
            @as(f32, @floatFromInt(monitor.width)) / @as(f32, @floatFromInt(monitor.mwidth)) * 25.4 / 96.0
        else
            1.0,
        .is_primary = monitor.primary == x11.True,
        .orientation = .@"0",
    };
}
