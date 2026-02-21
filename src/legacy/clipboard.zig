const std = @import("std");
const root = @import("root.zig");
const builtin = @import("builtin");
const native = @import("root.zig").native;
const win32 = @import("root.zig").native.win32.everything;
const x = @import("root.zig").native.x;

pub fn setAlloc(window: root.Window, allocator: std.mem.Allocator, text: []const u8) !void {
    switch (native.os) {
        .windows => {
            if (win32.OpenClipboard(null) == 0) return;
            defer _ = win32.CloseClipboard();
            const text_utf16 = std.unicode.utf8ToUtf16LeAlloc(allocator, text) catch return error.Utf8ToUtf16LeAlloc;
            defer allocator.free(text_utf16);
            const mem: isize = win32.GlobalAlloc(win32.GMEM_MOVEABLE, (text_utf16.len + 1) * @sizeOf(u16));
            const buf: [*]u16 = @ptrCast(@alignCast(win32.GlobalLock(mem) orelse {
                _ = win32.GlobalFree(mem);
                return;
            }));
            @memcpy(buf, text_utf16);
            buf[text_utf16.len] = 0;
            _ = win32.GlobalUnlock(mem);
            if (win32.SetClipboardData(@intFromEnum(win32.CLIPBOARD_FORMATS.UNICODETEXT), buf) == null) _ = win32.GlobalFree(mem);
        },
        else => switch (window.handle) {
            .x => {
                const clipboard = x.XInternAtom(window.handle.x11.display, "CLIPBOARD", 0);
                const utf8 = x.XInternAtom(window.handle.x11.display, "UTF8_STRING", 0);

                if (x.XSetSelectionOwner(window.handle.x11.display, clipboard, window.handle.x11.window, x.CurrentTime) == 0) return error.SetSelectionOwner;

                var event: x.XEvent = undefined;
                while (true) {
                    _ = x.XNextEvent(window.handle.x11.display, &event);
                    if (event.type == x.SelectionRequest) {
                        const request = &event.xselectionrequest;
                        _ = x.XChangeProperty(
                            window.handle.x11.display,
                            request.requestor,
                            request.property,
                            utf8,
                            8,
                            x.PropModeReplace,
                            @ptrCast(text),
                            @intCast(text.len),
                        );

                        var selection: x.XSelectionEvent = .{
                            .type = x.SelectionNotify,
                            .display = request.display,
                            .requestor = request.requestor,
                            .selection = request.selection,
                            .target = request.target,
                            .property = request.property,
                            .time = request.time,
                        };

                        _ = x.XSendEvent(window.handle.x11.display, request.requestor, 0, 0, @ptrCast(&selection));
                        _ = x.XFlush(window.handle.x11.display);
                        break;
                    }
                }
            },
            .wayland => @panic("wayland not implemented"),
        },
    }
}

pub fn getAlloc(window: root.Window, allocator: std.mem.Allocator) ?[]u8 {
    switch (native.os) {
        .windows => {
            if (win32.OpenClipboard(null) == 0) return null;
            defer _ = win32.CloseClipboard();
            const mem: isize = @intCast(@intFromPtr(win32.GetClipboardData(@intFromEnum(win32.CLIPBOARD_FORMATS.UNICODETEXT)) orelse return null));
            const text: [*:0]const u16 = @ptrCast(@alignCast(win32.GlobalLock(mem) orelse return null));
            defer _ = win32.GlobalUnlock(mem);
            return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.sliceTo(text, 0)) catch null;
        },
        else => switch (window.handle) {
            .x => {
                const clipboard = x.XInternAtom(window.handle.x11.display, "CLIPBOARD", 0);
                const utf8 = x.XInternAtom(window.handle.x11.display, "UTF8_STRING", 0);
                const property = x.XInternAtom(window.handle.x11.display, "XSEL_DATA", 0);

                // Request the selection
                _ = x.XConvertSelection(window.handle.x11.display, clipboard, utf8, property, window.handle.x11.window, x.CurrentTime);

                var event: x.XEvent = undefined;
                while (true) {
                    _ = x.XNextEvent(window.handle.x11.display, &event);
                    if (event.type == x.SelectionNotify) {
                        const sev = event.xselection;
                        if (sev.property == 0) return null; // conversion failed

                        var actual_type: x.Atom = 0;
                        var actual_format: c_int = 0;
                        var nitems: c_ulong = 0;
                        var bytes_after: c_ulong = 0;
                        var text: ?[*]u8 = undefined;

                        _ = x.XGetWindowProperty(window.handle.x11.display, window.handle.x11.window, property, 0, 4096, 0, utf8, &actual_type, &actual_format, &nitems, &bytes_after, &text);

                        return if (text) |t| t[0..@intCast(nitems)] else null;
                    }
                }
            },
            .wayland => @panic("wayland not implemented"),
        },
    }
}
