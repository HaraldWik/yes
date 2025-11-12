const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

pub const opengl = @import("opengl.zig");
/// only windows support currently (sort of)
pub const clipboard = @import("clipboard.zig");
/// only windows support currently
pub const file_dialog = @import("file_dialog.zig");

pub const native = struct {
    pub const os = builtin.os.tag;

    pub const win32 = @import("win32");
    pub const x = @cImport({ // TODO: Remove c import
        @cInclude("X11/Xlib.h");
        @cInclude("X11/Xutil.h");
        @cInclude("X11/Xatom.h");
        @cInclude("GL/glx.h");
    });
    pub const wayland = @compileError("nothing here");
};

pub const Window = struct {
    handle: Handle,

    pub const Handle = switch (native.os) {
        .windows => Win32,
        else => Posix,
    };

    pub const Win32 = @import("Win32.zig");
    pub const Posix = union(Tag) {
        x: X,
        wayland: Wayland,

        pub const Tag = enum { x, wayland };

        pub const X = @import("X.zig");
        pub const Wayland = @import("Wayland.zig");

        pub const session_type = "XDG_SESSION_TYPE";

        pub fn getSessionType() ?Tag {
            for (std.os.argv) |arg| {
                const identifier = "--xdg=";
                if (!std.mem.startsWith(u8, std.mem.span(arg), identifier)) continue;
                return std.meta.stringToEnum(Tag, std.mem.span(arg)[identifier.len..]);
            }
            const session = std.posix.getenv(Posix.session_type) orelse "x11";
            return if (std.mem.eql(u8, session, "wayland")) .wayland else .x;
        }
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
        if (config.api == .opengl and !build_options.opengl) @compileError("opengl is not enabled");
        if (config.api == .vulkan and !build_options.vulkan) @compileError("vulkan is not enabled");

        return .{
            .handle = switch (native.os) {
                .windows => try .open(config),
                else => switch (Posix.getSessionType() orelse .x) {
                    .x, .wayland => .{ .x = try .open(config) },
                    // .wayland => .{ .wayland = try Posix.Wayland.open(config) },
                },
            },
        };
    }

    pub fn close(self: @This()) void {
        switch (native.os) {
            .windows => self.handle.close(),
            else => switch (self.handle) {
                inline else => |handle| handle.close(),
            },
        }
    }

    pub fn poll(self: @This()) !?Event {
        return switch (native.os) {
            .windows => try self.handle.poll(),
            else => switch (self.handle) {
                inline else => |handle| handle.poll(),
            },
        };
    }

    pub fn getSize(self: @This()) [2]usize {
        return switch (native.os) {
            .windows => self.handle.getSize(),
            else => switch (self.handle) {
                inline else => |handle| handle.getSize(),
            },
        };
    }

    pub fn isKeyDown(self: @This(), key: Key) bool {
        return switch (native.os) {
            .windows => self.handle.isKeyDown(key),
            else => switch (self.handle) {
                inline else => |handle| handle.isKeyDown(key),
            },
        };
    }
};

pub const Event = union(enum) {
    close: void,
    resize: [2]usize,
    mouse: Mouse,
    key_down: Key,
    key_up: Key,
};

pub const Mouse = struct {
    right: bool = false,
    middle: bool = false,
    left: bool = false,
    forward: bool = false,
    backward: bool = false,
    x: usize = 0,
    y: usize = 0,
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
    numpad_decimal,
};

pub const GraphicsApi = enum {
    opengl,
    vulkan,
    none,
};
