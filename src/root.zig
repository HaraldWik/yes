const std = @import("std");
const builtin = @import("builtin");
pub const opengl = @import("opengl.zig");

const native_os = builtin.os.tag;

pub const Windows = @import("Windows.zig");
pub const Posix = union(Tag) {
    x: X,
    wayland: Wayland,

    pub const Tag = enum { x, wayland };

    pub const X = @import("X.zig");
    pub const Wayland = @import("Wayland.zig");

    pub const session_type = "XDG_SESSION_TYPE";

    pub fn getSessionType() Tag {
        const session = std.posix.getenv(Posix.session_type) orelse "x11";
        return if (std.mem.eql(u8, session, "wayland")) .wayland else .x;
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
        api: GraphicsApi = .none,
    };

    pub fn open(config: Config) !@This() {
        return .{
            .handle = switch (native_os) {
                .windows => handle: {
                    var window: Windows = .{};
                    try window.open(config);
                    break :handle &window;
                },
                else => session_type: switch (Posix.getSessionType()) {
                    .x => .{ .x = (Posix.X.open(config) catch continue :session_type .wayland) },
                    .wayland => .{
                        .wayland = handle: {
                            var window: Posix.Wayland = .{};
                            window.open(config) catch continue :session_type .x;
                            break :handle window;
                        },
                    },
                },
                // .{ .handle = try .open(config) },
            },
        };
    }

    pub fn close(self: @This()) void {
        switch (native_os) {
            .windows => self.handle.close(),
            else => switch (self.handle) {
                inline else => |handle| handle.close(),
            },
        }
    }

    pub fn next(self: @This()) ?Event {
        return switch (native_os) {
            .windows => self.handle.next(),
            else => switch (self.handle) {
                inline else => |handle| handle.next(),
            },
        };
    }

    pub fn getSize(self: @This()) [2]usize {
        return switch (native_os) {
            .windows => self.handle.getSize(),
            else => switch (self.handle) {
                inline else => |handle| handle.getSize(),
            },
        };
    }

    pub fn isKeyDown(self: @This(), key: Key) bool {
        return switch (native_os) {
            .windows => self.handle.isKeyDown(key),
            else => switch (self.handle) {
                inline else => |handle| handle.isKeyDown(key),
            },
        };
    }
};

pub const Event = union(enum) {
    resize: [2]usize,
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

pub const GraphicsApi = enum {
    opengl,
    vulkan,
    none,
};
