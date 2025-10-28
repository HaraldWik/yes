const std = @import("std");
const root = @import("root.zig");
pub const win32 = @import("win32").everything;
// zig build -Dtarget=x86_64-windows && wine zig-out/bin/example.exe

instance: win32.HINSTANCE = undefined,
hwnd: win32.HWND = undefined,
quit: bool = false,

pub fn open(self: *@This(), config: root.Window.Config) !void {
    const instance = win32.GetModuleHandleW(null) orelse return error.GetInstanceHandle;
    self.instance = instance;

    const class_name: [*:0]const u16 = std.unicode.utf8ToUtf16LeStringLiteral("WindowClass");

    var class: win32.WNDCLASSEXW = std.mem.zeroes(win32.WNDCLASSEXW);

    class.cbSize = @sizeOf(win32.WNDCLASSEXW);
    class.lpszClassName = class_name;
    class.lpfnWndProc = handleMessages;
    class.hInstance = instance;
    class.hCursor = win32.LoadCursorW(null, win32.IDC_ARROW);

    _ = win32.RegisterClassExW(@ptrCast(&class));

    var title_buffer: [256]u16 = undefined;
    const title = title_buffer[0..(try std.unicode.utf8ToUtf16Le(&title_buffer, config.title[0 .. config.title.len + 1]))];

    const hwnd = win32.CreateWindowExW(
        .{},
        class.lpszClassName,
        @ptrCast(title),
        win32.WS_OVERLAPPEDWINDOW,
        win32.CW_USEDEFAULT,
        win32.CW_USEDEFAULT,
        @intCast(config.width),
        @intCast(config.height),
        null,
        null,
        instance,
        @ptrCast(self),
    ) orelse return error.CreateWindowFailed;

    self.hwnd = hwnd;

    _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1 });
    _ = win32.UpdateWindow(hwnd);
}

pub fn close(self: @This()) void {
    _ = win32.DestroyWindow(self.hwnd);
}

pub fn next(self: @This()) ?root.Event {
    if (self.quit) return null;

    var msg: win32.MSG = undefined;
    while (win32.PeekMessageW(&msg, self.hwnd, 0, 0, .{ .REMOVE = 1 }) == @intFromBool(true)) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
    return .none;
}

pub fn getSize(self: @This()) [2]usize {
    var rect: win32.RECT = undefined;
    _ = win32.GetClientRect(self.hwnd, &rect);
    return .{ @intCast(rect.right - rect.left), @intCast(rect.bottom - rect.top) };
}

pub fn isKeyDown(self: @This(), key: root.Key) bool {
    _ = self;
    const virtual_key: win32.VIRTUAL_KEY = virtualKeyFromKey(key);
    const state = win32.GetAsyncKeyState(@intCast(@intFromEnum(virtual_key)));
    return (state & @as(i16, @bitCast(@as(u16, 0x8000)))) != 0;
}

fn handleMessages(hwnd: win32.HWND, message: u32, w_param: usize, l_param: isize) callconv(.winapi) win32.LRESULT {
    if (message == win32.WM_NCCREATE) {
        const cs: *const win32.CREATESTRUCTW = @ptrFromInt(@as(usize, @intCast(l_param)));
        _ = win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, @intCast(@intFromPtr(cs.lpCreateParams)));

        return win32.DefWindowProcW(hwnd, message, w_param, l_param);
    }

    const self: *@This() = self: {
        const self_ptr = win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
        if (self_ptr == 0) return win32.DefWindowProcW(hwnd, message, w_param, l_param);
        break :self @ptrFromInt(@as(usize, @intCast(self_ptr)));
    };

    return switch (message) {
        // win32.WM_KEYDOWN => result: {
        //     const vk: u32 = @intCast(w_param);
        //     std.debug.print("Key down: {d}\n", .{vk});
        //     break :result 0;
        // },
        // win32.WM_KEYUP => result: {
        //     const vk: u32 = @intCast(w_param);
        //     std.debug.print("Key up: {d}\n", .{vk});
        //     break :result 0;
        // },
        // win32.WM_CHAR => result: {
        //     const ch: u16 = @intCast(w_param);
        //     std.debug.print("Char: {d} {c}\n", .{ ch, @as(u8, @intCast(ch)) });
        //     break :result 0;
        // },
        win32.WM_DESTROY => result: {
            self.quit = true;

            win32.PostQuitMessage(0);
            break :result 0;
        },
        else => return win32.DefWindowProcW(hwnd, message, w_param, l_param),
    };
}

pub fn virtualKeyFromKey(key: root.Key) win32.VIRTUAL_KEY {
    return switch (key) {
        // Control keys
        .backspace => win32.VK_BACK,
        .tab => win32.VK_TAB,
        .clear => win32.VK_CLEAR,
        .enter => win32.VK_RETURN,
        .escape => win32.VK_ESCAPE,
        .delete => win32.VK_DELETE,

        // Modifiers
        .left_shift => win32.VK_LSHIFT,
        .right_shift => win32.VK_RSHIFT,
        .left_ctrl => win32.VK_LCONTROL,
        .right_ctrl => win32.VK_RCONTROL,
        .left_alt => win32.VK_LMENU,
        .right_alt => win32.VK_RMENU,
        .left_super => win32.VK_LWIN, // Windows / Command key
        .right_super => win32.VK_RWIN,
        .caps_lock => win32.VK_NUMLOCK,

        // Navigation
        .up => win32.VK_UP,
        .down => win32.VK_DOWN,
        .left => win32.VK_LEFT,
        .right => win32.VK_RIGHT,
        .home => win32.VK_HOME,
        .end => win32.VK_END,
        .page_up => win32.VK_PRIOR,
        .page_down => win32.VK_NEXT,
        .insert => win32.VK_INSERT,

        // Function keys
        .f1 => win32.VK_F1,
        .f2 => win32.VK_F2,
        .f3 => win32.VK_F3,
        .f4 => win32.VK_F4,
        .f5 => win32.VK_F5,
        .f6 => win32.VK_F6,
        .f7 => win32.VK_F7,
        .f8 => win32.VK_F8,
        .f9 => win32.VK_F9,
        .f10 => win32.VK_F10,
        .f11 => win32.VK_F11,
        .f12 => win32.VK_F12,

        // Numpad
        .numpad_0 => win32.VK_NUMPAD0,
        .numpad_1 => win32.VK_NUMPAD1,
        .numpad_2 => win32.VK_NUMPAD2,
        .numpad_3 => win32.VK_NUMPAD3,
        .numpad_4 => win32.VK_NUMPAD4,
        .numpad_5 => win32.VK_NUMPAD5,
        .numpad_6 => win32.VK_NUMPAD6,
        .numpad_7 => win32.VK_NUMPAD7,
        .numpad_8 => win32.VK_NUMPAD8,
        .numpad_9 => win32.VK_NUMPAD9,
        .numpad_add => win32.VK_ADD,
        .numpad_subtract => win32.VK_SUBTRACT,
        .numpad_multiply => win32.VK_MULTIPLY,
        .numpad_divide => win32.VK_DIVIDE,
        .numpad_enter => win32.VK_RETURN,
        .numpad_decimal => win32.VK_DECIMAL,
        else => @enumFromInt(@as(u16, @intCast(@intFromEnum(key)))),
    };
}
