const std = @import("std");
const builtin = @import("builtin");
pub const opengl = @import("opengl.zig");

const native_os = builtin.os.tag;

pub const Windows = @import("Windows.zig");
pub const Posix = union(enum) {
    x: X,
    wayland: Wayland,

    pub const X = @import("X.zig");
    pub const Wayland = @import("Wayland.zig");

    pub fn close(self: @This()) void {
        switch (self) {
            inline else => |a| a.close(),
        }
    }

    pub fn next(self: @This()) ?Event {
        return switch (self) {
            inline else => |a| return a.next(),
        };
    }

    pub fn getSize(self: @This()) [2]usize {
        return switch (self) {
            inline else => |a| a.getSize(),
        };
    }

    pub fn isKeyDown(self: @This(), key: Key) bool {
        return switch (self) {
            inline else => |a| a.isKeyDown(key),
        };
    }
};

pub const Window = struct {
    handle: Handle,

    pub const Handle = switch (native_os) {
        .windows => *Windows,
        else => Posix,
    };

    pub const Config = struct {
        title: [:0]const u8,
        width: usize,
        height: usize,
        min_width: ?usize = null,
        min_height: ?usize = null,
        max_width: ?usize = null,
        max_height: ?usize = null,
        resizable: bool = true,
        renderer: Renderer = .none,

        pub const Renderer = enum {
            none,
            opengl,
            vulkan,
        };
    };

    pub fn open(config: Config) !@This() {
        return switch (native_os) {
            .windows => handle: {
                var window: Windows = .{};
                try window.open(config);
                break :handle .{ .handle = &window };
            },
            else => handle: {
                const session = std.posix.getenv("XDG_SESSION_TYPE") orelse "x11";
                std.debug.print("Session: {s}\n", .{session});

                if (std.mem.eql(u8, session, "x11"))
                    break :handle .{ .handle = .{ .x = try .open(config) } };

                if (std.mem.eql(u8, session, "wayland"))
                    break :handle .{ .handle = .{ .wayland = try .open(config) } };

                return error.None;
            },
            // .{ .handle = try .open(config) },
        };
    }

    pub fn close(self: @This()) void {
        self.handle.close();
    }

    pub fn next(self: @This()) ?Event {
        return self.handle.next();
    }

    pub fn getSize(self: @This()) [2]usize {
        return self.handle.getSize();
    }

    pub fn isKeyDown(self: @This(), key: Key) bool {
        return self.handle.isKeyDown(key);
    }
};

pub const Event = union(enum) {
    none: void,
};

pub const Key = enum(u8) {
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
    numpad_enter,
    numpad_decimal,
};
