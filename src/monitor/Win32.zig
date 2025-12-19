const std = @import("std");
const win32 = @import("win32").everything;
const Monitor = @import("Monitor.zig");

pub fn get(index: usize, buffer: []u8) !?Monitor {
    var target = index;
    var dev_num: u32 = 0;

    while (true) {
        var dd: win32.DISPLAY_DEVICEW = std.mem.zeroes(win32.DISPLAY_DEVICEW);
        dd.cb = @sizeOf(win32.DISPLAY_DEVICEW);

        if (win32.EnumDisplayDevicesW(null, dev_num, &dd, 0) == 0)
            break;

        if ((dd.StateFlags & win32.DISPLAY_DEVICE_ACTIVE) == 0) {
            dev_num += 1;
            continue;
        }

        if (target == 0) {
            var dm: win32.DEVMODEW = std.mem.zeroes(win32.DEVMODEW);
            dm.dmSize = @sizeOf(win32.DEVMODEW);

            _ = win32.EnumDisplaySettingsExW(
                @ptrCast(dd.DeviceName[0..]),
                win32.ENUM_CURRENT_SETTINGS,
                &dm,
                0,
            );
            var device_name_len: usize = 0;
            while (device_name_len <= dd.DeviceName.len and dd.DeviceName[device_name_len] != 0) device_name_len += 1;
            const name = buffer[0..try std.unicode.utf16LeToUtf8(buffer, dd.DeviceName[0..device_name_len])];

            _ = win32.MessageBoxW(null, @ptrCast(dd.DeviceString[0..]), win32.L("Device string"), .{});

            return .{
                .name = name,
                .size = .{ .width = @intCast(dm.dmPelsWidth), .height = @intCast(dm.dmPelsHeight) },
                .position = .{ .x = dm.Anonymous1.Anonymous2.dmPosition.x, .y = dm.Anonymous1.Anonymous2.dmPosition.y },
                .physical_size = null,
                .scale = 1.0,
                .primary = (dd.StateFlags & win32.DISPLAY_DEVICE_PRIMARY_DEVICE) != 0,
            };
        }

        target -= 1;
        dev_num += 1;
    }

    return null;
}
