const std = @import("std");
const win32 = @import("win32").everything;
const xkb = @import("xkb");
const Size = @import("Window.zig").Size;
const Position = @import("Window.zig").Position;

pub const Union = union(enum) {
    close: void,
    resize: Size,
    key: Key,
    mouse: Mouse,

    pub const Key = struct {
        state: State,
        code: Code,
        sym: Sym,

        pub const State = enum {
            press,
            release,
        };

        pub const Code = usize;

        pub const Sym = enum(u32) {
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

            pub fn fromXkb(key: anytype) ?@This() {
                return switch (@as(xkb.xkb_keysym_t, @intCast(key))) {
                    xkb.XKB_KEY_A, xkb.XKB_KEY_a => .a,
                    xkb.XKB_KEY_B, xkb.XKB_KEY_b => .b,
                    xkb.XKB_KEY_C, xkb.XKB_KEY_c => .c,
                    xkb.XKB_KEY_D, xkb.XKB_KEY_d => .d,
                    xkb.XKB_KEY_E, xkb.XKB_KEY_e => .e,
                    xkb.XKB_KEY_F, xkb.XKB_KEY_f => .f,
                    xkb.XKB_KEY_G, xkb.XKB_KEY_g => .g,
                    xkb.XKB_KEY_H, xkb.XKB_KEY_h => .h,
                    xkb.XKB_KEY_I, xkb.XKB_KEY_i => .i,
                    xkb.XKB_KEY_J, xkb.XKB_KEY_j => .j,
                    xkb.XKB_KEY_K, xkb.XKB_KEY_k => .k,
                    xkb.XKB_KEY_L, xkb.XKB_KEY_l => .l,
                    xkb.XKB_KEY_M, xkb.XKB_KEY_m => .m,
                    xkb.XKB_KEY_N, xkb.XKB_KEY_n => .n,
                    xkb.XKB_KEY_O, xkb.XKB_KEY_o => .o,
                    xkb.XKB_KEY_P, xkb.XKB_KEY_p => .p,
                    xkb.XKB_KEY_Q, xkb.XKB_KEY_q => .q,
                    xkb.XKB_KEY_R, xkb.XKB_KEY_r => .r,
                    xkb.XKB_KEY_S, xkb.XKB_KEY_s => .s,
                    xkb.XKB_KEY_T, xkb.XKB_KEY_t => .t,
                    xkb.XKB_KEY_U, xkb.XKB_KEY_u => .u,
                    xkb.XKB_KEY_V, xkb.XKB_KEY_v => .v,
                    xkb.XKB_KEY_W, xkb.XKB_KEY_w => .w,
                    xkb.XKB_KEY_X, xkb.XKB_KEY_x => .x,
                    xkb.XKB_KEY_Y, xkb.XKB_KEY_y => .y,
                    xkb.XKB_KEY_Z, xkb.XKB_KEY_z => .z,

                    xkb.XKB_KEY_BackSpace => .backspace,
                    xkb.XKB_KEY_Tab => .tab,
                    xkb.XKB_KEY_Clear => .clear,
                    xkb.XKB_KEY_Return => .enter,
                    xkb.XKB_KEY_Escape => .escape,
                    xkb.XKB_KEY_Delete => .delete,

                    // Modifiers
                    xkb.XKB_KEY_Shift_L => .left_shift,
                    xkb.XKB_KEY_Shift_R => .right_shift,
                    xkb.XKB_KEY_Control_L => .left_ctrl,
                    xkb.XKB_KEY_Control_R => .right_ctrl,
                    xkb.XKB_KEY_Alt_L => .left_alt,
                    xkb.XKB_KEY_Alt_R => .right_alt,
                    xkb.XKB_KEY_Super_L => .left_super, // Windows / Command key
                    xkb.XKB_KEY_Super_R => .right_super,
                    xkb.XKB_KEY_Caps_Lock => .caps_lock,

                    // Navigation
                    xkb.XKB_KEY_Up => .up,
                    xkb.XKB_KEY_Down => .down,
                    xkb.XKB_KEY_Left => .left,
                    xkb.XKB_KEY_Right => .right,
                    xkb.XKB_KEY_Home => .home,
                    xkb.XKB_KEY_End => .end,
                    xkb.XKB_KEY_Page_Up => .page_up,
                    xkb.XKB_KEY_Page_Down => .page_down,
                    xkb.XKB_KEY_Insert => .insert,

                    // Function keys
                    xkb.XKB_KEY_F1 => .f1,
                    xkb.XKB_KEY_F2 => .f2,
                    xkb.XKB_KEY_F3 => .f3,
                    xkb.XKB_KEY_F4 => .f4,
                    xkb.XKB_KEY_F5 => .f5,
                    xkb.XKB_KEY_F6 => .f6,
                    xkb.XKB_KEY_F7 => .f7,
                    xkb.XKB_KEY_F8 => .f8,
                    xkb.XKB_KEY_F9 => .f9,
                    xkb.XKB_KEY_F10 => .f10,
                    xkb.XKB_KEY_F11 => .f11,
                    xkb.XKB_KEY_F12 => .f12,

                    // Numpad
                    xkb.XKB_KEY_KP_0 => .numpad_0,
                    xkb.XKB_KEY_KP_1 => .numpad_1,
                    xkb.XKB_KEY_KP_2 => .numpad_2,
                    xkb.XKB_KEY_KP_3 => .numpad_3,
                    xkb.XKB_KEY_KP_4 => .numpad_4,
                    xkb.XKB_KEY_KP_5 => .numpad_5,
                    xkb.XKB_KEY_KP_6 => .numpad_6,
                    xkb.XKB_KEY_KP_7 => .numpad_7,
                    xkb.XKB_KEY_KP_8 => .numpad_8,
                    xkb.XKB_KEY_KP_9 => .numpad_9,
                    xkb.XKB_KEY_KP_Add => .numpad_add,
                    xkb.XKB_KEY_KP_Subtract => .numpad_subtract,
                    xkb.XKB_KEY_KP_Multiply => .numpad_multiply,
                    xkb.XKB_KEY_KP_Divide => .numpad_divide,
                    xkb.XKB_KEY_KP_Decimal => .numpad_decimal,
                    else => std.enums.fromInt(@This(), key),
                };
            }
        };
    };

    pub const Mouse = union(enum) {
        move: Position(u32),
        scroll: Scroll,
        button: Button,

        pub const Scroll = union(enum) {
            x: isize, // horizontal
            y: isize, // vertical
        };

        pub const Button = struct {
            state: State,
            code: Code,
            position: Position(u32),

            pub const State = Key.State;

            pub const Code = enum {
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

                pub fn fromX11(button: c_uint) ?@This() {
                    return switch (button) {
                        3 => .right,
                        2 => .middle,
                        1 => .left,
                        9 => .forward,
                        8 => .backward,
                        else => null,
                    };
                }

                pub fn fromWayland(button: u32) ?@This() {
                    return switch (button) {
                        272 => .left,
                        274 => .middle,
                        273 => .right,
                        276 => .forward,
                        275 => .backward,
                        else => null,
                    };
                }
            };
        };
    };
};
