const std = @import("std");
const native = @import("root.zig").native;

pub const Union = union(enum) {
    close: void,
    resize: [2]usize,
    mouse: Mouse,
    key_down: Key,
    key_up: Key,

    pub const Mouse = struct {
        right: bool = false,
        middle: bool = false,
        left: bool = false,
        forward: bool = false,
        backward: bool = false,
        x: usize = 0,
        y: usize = 0,
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

        pub fn fromWin32(key: native.win32.everything.VIRTUAL_KEY, lparam: isize) ?@This() {
            const win32 = native.win32.everything;

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
                .SHIFT => return switch (std.enums.fromInt(win32.VIRTUAL_KEY, win32.MapVirtualKeyW(scancode, win32.MAPVK_VSC_TO_VK_EX)) orelse .LSHIFT) {
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

        pub fn fromX(key: native.x.KeySym) ?@This() {
            return switch (key) {
                native.x.XK_A, native.x.XK_a => .a,
                native.x.XK_B, native.x.XK_b => .b,
                native.x.XK_C, native.x.XK_c => .c,
                native.x.XK_D, native.x.XK_d => .d,
                native.x.XK_E, native.x.XK_e => .e,
                native.x.XK_F, native.x.XK_f => .f,
                native.x.XK_G, native.x.XK_g => .g,
                native.x.XK_H, native.x.XK_h => .h,
                native.x.XK_I, native.x.XK_i => .i,
                native.x.XK_J, native.x.XK_j => .j,
                native.x.XK_K, native.x.XK_k => .k,
                native.x.XK_L, native.x.XK_l => .l,
                native.x.XK_M, native.x.XK_m => .m,
                native.x.XK_N, native.x.XK_n => .n,
                native.x.XK_O, native.x.XK_o => .o,
                native.x.XK_P, native.x.XK_p => .p,
                native.x.XK_Q, native.x.XK_q => .q,
                native.x.XK_R, native.x.XK_r => .r,
                native.x.XK_S, native.x.XK_s => .s,
                native.x.XK_T, native.x.XK_t => .t,
                native.x.XK_U, native.x.XK_u => .u,
                native.x.XK_V, native.x.XK_v => .v,
                native.x.XK_W, native.x.XK_w => .w,
                native.x.XK_X, native.x.XK_x => .x,
                native.x.XK_Y, native.x.XK_y => .y,
                native.x.XK_Z, native.x.XK_z => .z,

                native.x.XK_BackSpace => .backspace,
                native.x.XK_Tab => .tab,
                native.x.XK_Clear => .clear,
                native.x.XK_Return => .enter,
                native.x.XK_Escape => .escape,
                native.x.XK_Delete => .delete,

                // Modifiers
                native.x.XK_Shift_L => .left_shift,
                native.x.XK_Shift_R => .right_shift,
                native.x.XK_Control_L => .left_ctrl,
                native.x.XK_Control_R => .right_ctrl,
                native.x.XK_Alt_L => .left_alt,
                native.x.XK_Alt_R => .right_alt,
                native.x.XK_Super_L => .left_super, // Windows / Command key
                native.x.XK_Super_R => .right_super,
                native.x.XK_Caps_Lock => .caps_lock,

                // Navigation
                native.x.XK_Up => .up,
                native.x.XK_Down => .down,
                native.x.XK_Left => .left,
                native.x.XK_Right => .right,
                native.x.XK_Home => .home,
                native.x.XK_End => .end,
                native.x.XK_Page_Up => .page_up,
                native.x.XK_Page_Down => .page_down,
                native.x.XK_Insert => .insert,

                // Function keys
                native.x.XK_F1 => .f1,
                native.x.XK_F2 => .f2,
                native.x.XK_F3 => .f3,
                native.x.XK_F4 => .f4,
                native.x.XK_F5 => .f5,
                native.x.XK_F6 => .f6,
                native.x.XK_F7 => .f7,
                native.x.XK_F8 => .f8,
                native.x.XK_F9 => .f9,
                native.x.XK_F10 => .f10,
                native.x.XK_F11 => .f11,
                native.x.XK_F12 => .f12,

                // Numpad
                native.x.XK_KP_0 => .numpad_0,
                native.x.XK_KP_1 => .numpad_1,
                native.x.XK_KP_2 => .numpad_2,
                native.x.XK_KP_3 => .numpad_3,
                native.x.XK_KP_4 => .numpad_4,
                native.x.XK_KP_5 => .numpad_5,
                native.x.XK_KP_6 => .numpad_6,
                native.x.XK_KP_7 => .numpad_7,
                native.x.XK_KP_8 => .numpad_8,
                native.x.XK_KP_9 => .numpad_9,
                native.x.XK_KP_Add => .numpad_add,
                native.x.XK_KP_Subtract => .numpad_subtract,
                native.x.XK_KP_Multiply => .numpad_multiply,
                native.x.XK_KP_Divide => .numpad_divide,
                native.x.XK_KP_Decimal => .numpad_decimal,
                else => std.enums.fromInt(@This(), key),
            };
        }
    };
};
