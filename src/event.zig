const std = @import("std");
const native = @import("root.zig").native;
const win32 = @import("root.zig").native.win32.everything;
const x11 = @import("root.zig").native.x11;
const Position = @import("root.zig").Window.Position;

pub const Union = union(enum) {
    close: void,
    resize: @import("root.zig").Window.Size,
    mouse: Mouse,
    key_down: Key,
    key_up: Key,

    pub const Mouse = union(enum) {
        move: Position,
        click_down: Click,
        click_up: Click,

        pub const Click = struct {
            button: Button,
            position: Position,
        };

        pub const Button = enum {
            right,
            middle,
            left,
            forward,
            backward,

            pub fn fromWin32(button: u32, wparam: usize) ?@This() {
                return switch (button) {
                    win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP => .right,
                    win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP => .middle,
                    win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP => .left,
                    win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP => {
                        const data: win32.MOUSEHOOKSTRUCTEX_MOUSE_DATA = @bitCast(@as(u32, @intCast(((wparam >> 16) & 0xFFFF))));
                        return if (std.meta.eql(data, win32.XBUTTON1)) .backward else if (std.meta.eql(data, win32.XBUTTON2)) .forward else null;
                    },

                    else => null,
                };
            }

            pub fn fromX(button: c_uint) ?@This() {
                return switch (button) {
                    3 => .right,
                    2 => .middle,
                    1 => .left,
                    9 => .forward,
                    8 => .backward,
                    else => null,
                };
            }
        };
    };

    pub const Key = enum(u32) {
        // Digits
        @"0" = '0',
        @"1" = '1',
        @"2" = '2',
        @"3" = '3',
        @"4" = '4',
        @"5" = '5',
        @"6" = '6',
        @"7" = '7',
        @"8" = '8',
        @"9" = '9',

        // Letters
        a = 'A',
        b = 'B',
        c = 'C',
        d = 'D',
        e = 'E',
        f = 'F',
        g = 'G',
        h = 'H',
        i = 'I',
        j = 'J',
        k = 'K',
        l = 'L',
        m = 'M',
        n = 'N',
        o = 'O',
        p = 'P',
        q = 'Q',
        r = 'R',
        s = 'S',
        t = 'T',
        u = 'U',
        v = 'V',
        w = 'W',
        x = 'X',
        y = 'Y',
        z = 'Z',

        // --- Punctuation / symbols ---
        space = ' ',
        minus = '-',
        equal = '=',
        left_bracket = '[',
        right_bracket = ']',
        backslash = '\\',
        semicolon = ';',
        quote = '\'',
        comma = ',',
        period = '.',
        slash = '/',
        grave = '`',

        // Control keys
        backspace,
        tab,
        clear,
        enter,
        escape,
        delete,

        // Modifiers
        left_shift,
        right_shift,
        left_ctrl,
        right_ctrl,
        left_alt,
        right_alt,
        left_super, // Windows / Command key
        right_super,
        caps_lock,

        // Navigation
        up,
        down,
        left,
        right,
        home,
        end,
        page_up,
        page_down,
        insert,

        // Function keys
        f1,
        f2,
        f3,
        f4,
        f5,
        f6,
        f7,
        f8,
        f9,
        f10,
        f11,
        f12,

        // Numpad
        numpad_0,
        numpad_1,
        numpad_2,
        numpad_3,
        numpad_4,
        numpad_5,
        numpad_6,
        numpad_7,
        numpad_8,
        numpad_9,
        numpad_add,
        numpad_subtract,
        numpad_multiply,
        numpad_divide,
        numpad_decimal,

        pub fn fromWin32(key: win32.VIRTUAL_KEY, lparam: isize) ?@This() {
            const scancode: u32 = (@as(u32, @intCast(lparam)) >> 16) & 0xFF;
            const extended: bool = ((lparam >> 24) & 1) != 0;

            return switch (key) {
                .BACK => .backspace,
                .TAB => .tab,
                .CLEAR => .clear,
                .RETURN => .enter,
                .ESCAPE => .escape,
                .DELETE => .delete,

                // Modifiers
                .SHIFT => switch (std.enums.fromInt(win32.VIRTUAL_KEY, win32.MapVirtualKeyW(scancode, win32.MAPVK_VSC_TO_VK_EX)) orelse .LSHIFT) {
                    .LSHIFT => .left_shift,
                    .RSHIFT => .right_shift,
                    else => .left_shift, // fallback
                },
                .CONTROL => if (extended) .right_ctrl else .left_ctrl,
                .MENU => if (extended) .right_alt else .left_alt,
                .LWIN => .left_super, // Windows / Command key
                .RWIN => .right_super, // Windows / Command key
                .CAPITAL => .caps_lock,

                // Navigation
                .UP => .up,
                .DOWN => .down,
                .LEFT => .left,
                .RIGHT => .right,
                .HOME => .home,
                .END => .end,
                .PRIOR => .page_up,
                .NEXT => .page_down,
                .INSERT => .insert,

                // Function keys
                .F1 => .f1,
                .F2 => .f2,
                .F3 => .f3,
                .F4 => .f4,
                .F5 => .f5,
                .F6 => .f6,
                .F7 => .f7,
                .F8 => .f8,
                .F9 => .f9,
                .F10 => .f10,
                .F11 => .f11,
                .F12 => .f12,

                // Numpad
                .NUMPAD0 => .numpad_0,
                .NUMPAD1 => .numpad_1,
                .NUMPAD2 => .numpad_2,
                .NUMPAD3 => .numpad_3,
                .NUMPAD4 => .numpad_4,
                .NUMPAD5 => .numpad_5,
                .NUMPAD6 => .numpad_6,
                .NUMPAD7 => .numpad_7,
                .NUMPAD8 => .numpad_8,
                .NUMPAD9 => .numpad_9,
                .ADD => .numpad_add,
                .SUBTRACT => .numpad_subtract,
                .MULTIPLY => .numpad_multiply,
                .DIVIDE => .numpad_divide,
                .DECIMAL => .numpad_decimal,
                else => std.enums.fromInt(@This(), @intFromEnum(key)),
            };
        }

        pub fn fromX(key: x11.KeySym) ?@This() {
            return switch (key) {
                x11.XK_A, x11.XK_a => .a,
                x11.XK_B, x11.XK_b => .b,
                x11.XK_C, x11.XK_c => .c,
                x11.XK_D, x11.XK_d => .d,
                x11.XK_E, x11.XK_e => .e,
                x11.XK_F, x11.XK_f => .f,
                x11.XK_G, x11.XK_g => .g,
                x11.XK_H, x11.XK_h => .h,
                x11.XK_I, x11.XK_i => .i,
                x11.XK_J, x11.XK_j => .j,
                x11.XK_K, x11.XK_k => .k,
                x11.XK_L, x11.XK_l => .l,
                x11.XK_M, x11.XK_m => .m,
                x11.XK_N, x11.XK_n => .n,
                x11.XK_O, x11.XK_o => .o,
                x11.XK_P, x11.XK_p => .p,
                x11.XK_Q, x11.XK_q => .q,
                x11.XK_R, x11.XK_r => .r,
                x11.XK_S, x11.XK_s => .s,
                x11.XK_T, x11.XK_t => .t,
                x11.XK_U, x11.XK_u => .u,
                x11.XK_V, x11.XK_v => .v,
                x11.XK_W, x11.XK_w => .w,
                x11.XK_X, x11.XK_x => .x,
                x11.XK_Y, x11.XK_y => .y,
                x11.XK_Z, x11.XK_z => .z,

                x11.XK_BackSpace => .backspace,
                x11.XK_Tab => .tab,
                x11.XK_Clear => .clear,
                x11.XK_Return => .enter,
                x11.XK_Escape => .escape,
                x11.XK_Delete => .delete,

                // Modifiers
                x11.XK_Shift_L => .left_shift,
                x11.XK_Shift_R => .right_shift,
                x11.XK_Control_L => .left_ctrl,
                x11.XK_Control_R => .right_ctrl,
                x11.XK_Alt_L => .left_alt,
                x11.XK_Alt_R => .right_alt,
                x11.XK_Super_L => .left_super, // Windows / Command key
                x11.XK_Super_R => .right_super,
                x11.XK_Caps_Lock => .caps_lock,

                // Navigation
                x11.XK_Up => .up,
                x11.XK_Down => .down,
                x11.XK_Left => .left,
                x11.XK_Right => .right,
                x11.XK_Home => .home,
                x11.XK_End => .end,
                x11.XK_Page_Up => .page_up,
                x11.XK_Page_Down => .page_down,
                x11.XK_Insert => .insert,

                // Function keys
                x11.XK_F1 => .f1,
                x11.XK_F2 => .f2,
                x11.XK_F3 => .f3,
                x11.XK_F4 => .f4,
                x11.XK_F5 => .f5,
                x11.XK_F6 => .f6,
                x11.XK_F7 => .f7,
                x11.XK_F8 => .f8,
                x11.XK_F9 => .f9,
                x11.XK_F10 => .f10,
                x11.XK_F11 => .f11,
                x11.XK_F12 => .f12,

                // Numpad
                x11.XK_KP_0 => .numpad_0,
                x11.XK_KP_1 => .numpad_1,
                x11.XK_KP_2 => .numpad_2,
                x11.XK_KP_3 => .numpad_3,
                x11.XK_KP_4 => .numpad_4,
                x11.XK_KP_5 => .numpad_5,
                x11.XK_KP_6 => .numpad_6,
                x11.XK_KP_7 => .numpad_7,
                x11.XK_KP_8 => .numpad_8,
                x11.XK_KP_9 => .numpad_9,
                x11.XK_KP_Add => .numpad_add,
                x11.XK_KP_Subtract => .numpad_subtract,
                x11.XK_KP_Multiply => .numpad_multiply,
                x11.XK_KP_Divide => .numpad_divide,
                x11.XK_KP_Decimal => .numpad_decimal,
                else => std.enums.fromInt(@This(), key),
            };
        }
    };
};
