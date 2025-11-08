const std = @import("std");
const root = @import("root.zig");
pub const c = @cImport({ // TODO: Remove c import
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/Xatom.h");
    @cInclude("GL/glx.h");
});

window: c.Window,
display: *c.Display,
wm_delete_window: c.Atom,

pub fn open(config: root.Window.Config) !@This() {
    const display: *c.Display = c.XOpenDisplay(null) orelse return error.OpenDisplay;
    const screen = c.DefaultScreen(display);

    var visual: *c.XVisualInfo = undefined;
    const window: c.Window = window: switch (config.api) {
        .opengl => {
            var visual_attribs = [_:0]c_int{
                c.GLX_RGBA,
                c.GLX_DOUBLEBUFFER,
                c.GLX_DEPTH_SIZE,
                24,
                c.GLX_STENCIL_SIZE,
                8,
                c.GLX_NONE,
            };

            visual = c.glXChooseVisual(display, screen, &visual_attribs);

            var swa: c.XSetWindowAttributes = .{
                .colormap = c.XCreateColormap(display, c.RootWindow(display, screen), visual.visual, c.AllocNone),
                .event_mask = c.ExposureMask | c.KeyPressMask | c.StructureNotifyMask,
            };

            const window: c.Window = c.XCreateWindow(
                display,
                c.RootWindow(display, screen),
                0,
                0,
                800,
                600,
                0,
                visual.depth,
                c.InputOutput,
                visual.visual,
                c.CWColormap | c.CWEventMask,
                &swa,
            );
            break :window window;
        },
        .vulkan => return error.NotImplemented, // TODO: add vulkan window for X
        .none => c.XCreateSimpleWindow(display, c.RootWindow(display, screen), // Parent window
            0, 0, // X, Y position
            @intCast(config.width), @intCast(config.height), // Width, Height
            2, // Border width
            c.BlackPixel(display, screen), // Border color
            c.BlackPixel(display, screen) // Background color
        ),
    };

    _ = c.XStoreName(display, window, config.title.ptr);
    var hints: c.XSizeHints = .{};

    if (config.min_width != null and config.min_height != null) {
        hints.flags |= c.PMinSize;
        hints.min_width = @intCast(config.min_width.?);
        hints.min_height = @intCast(config.min_height.?);
    }

    if (config.max_width != null and config.max_height != null) {
        hints.flags |= c.PMaxSize;
        hints.max_width = @intCast(config.max_width.?);
        hints.max_height = @intCast(config.max_height.?);
    }

    c.XSetWMNormalHints(display, window, &hints);

    var wm_delete_window: c.Atom = c.XInternAtom(display, "WM_DELETE_WINDOW", @intFromBool(false));
    _ = c.XSetWMProtocols(display, window, &wm_delete_window, 1);

    _ = c.XSelectInput(display, window, c.ExposureMask | c.KeyPressMask | c.ButtonPressMask | c.StructureNotifyMask);

    _ = c.XMapWindow(display, window);
    _ = c.XFlush(display);

    switch (config.api) {
        .opengl => {
            const ctx: c.GLXContext = c.glXCreateContext(display, visual, null, @intFromBool(true));
            _ = c.glXMakeCurrent(display, window, ctx);
        },
        .vulkan => {},
        .none => {},
    }

    return .{
        .window = window,
        .display = display,
        .wm_delete_window = wm_delete_window,
    };
}

pub fn close(self: @This()) void {
    _ = c.XDestroyWindow(self.display, self.window);
    _ = c.XCloseDisplay(self.display);
}

pub fn next(self: @This()) ?root.Event {
    var event: c.XEvent = undefined;
    while (c.XPending(self.display) > 0) {
        if (c.XNextEvent(self.display, &event) != c.XCSUCCESS) return null;
    }

    return switch (event.type) {
        c.ClientMessage => event: {
            if (@as(c.Atom, @intCast(event.xclient.data.l[0])) == self.wm_delete_window) break :event null;
            break :event .none;
        },
        c.ConfigureNotify => .{ .resize = .{ @intCast(event.xconfigure.width), @intCast(event.xconfigure.height) } },
        // c.Expose => return .expose,
        else => .none,
    };
}

pub fn getSize(self: @This()) [2]usize {
    var root_window: c.Window = undefined;
    var x: c_int = 0;
    var y: c_int = 0;
    var width: c_uint = 0;
    var height: c_uint = 0;
    var border: c_uint = 0;
    var depth: c_uint = 0;

    _ = c.XGetGeometry(self.display, self.window, &root_window, &x, &y, &width, &height, &border, &depth);
    return .{ @intCast(width), @intCast(height) };
}

pub fn isKeyDown(self: *const @This(), key: root.Key) bool {
    const keysym: c.KeySym = keySymFromKey(key);
    const keycode = c.XKeysymToKeycode(self.display, keysym);
    if (keycode == 0) return false;

    _ = c.XSync(self.display, c.False);

    var keys_return: [32]u8 = undefined;
    _ = c.XQueryKeymap(self.display, &keys_return);

    const byte_index: usize = @intCast(@divTrunc(keycode, 8));
    const bit_index: usize = @intCast(keycode % 8);
    const byte = keys_return[byte_index];
    return (byte & (@as(u8, 1) << @intCast(bit_index))) != 0;
}

pub fn keySymFromKey(key: root.Key) c.KeySym {
    return switch (key) {
        .backspace => c.XK_BackSpace,
        .tab => c.XK_Tab,
        .clear => c.XK_Clear,
        .enter => c.XK_Return,
        .escape => c.XK_Escape,
        .delete => c.XK_Delete,

        // Modifiers
        .left_shift => c.XK_Shift_L,
        .right_shift => c.XK_Shift_R,
        .left_ctrl => c.XK_Control_L,
        .right_ctrl => c.XK_Control_R,
        .left_alt => c.XK_Alt_L,
        .right_alt => c.XK_Alt_R,
        .left_super => c.XK_Super_L, // Windows / Command key
        .right_super => c.XK_Super_R,
        .caps_lock => c.XK_Caps_Lock,

        // Navigation
        .up => c.XK_Up,
        .down => c.XK_Down,
        .left => c.XK_Left,
        .right => c.XK_Right,
        .home => c.XK_Home,
        .end => c.XK_End,
        .page_up => c.XK_Page_Up,
        .page_down => c.XK_Page_Down,
        .insert => c.XK_Insert,

        // Function keys
        .f1 => c.XK_F1,
        .f2 => c.XK_F2,
        .f3 => c.XK_F3,
        .f4 => c.XK_F4,
        .f5 => c.XK_F5,
        .f6 => c.XK_F6,
        .f7 => c.XK_F7,
        .f8 => c.XK_F8,
        .f9 => c.XK_F9,
        .f10 => c.XK_F10,
        .f11 => c.XK_F11,
        .f12 => c.XK_F12,

        // Numpad
        .numpad_0 => c.XK_KP_0,
        .numpad_1 => c.XK_KP_1,
        .numpad_2 => c.XK_KP_2,
        .numpad_3 => c.XK_KP_3,
        .numpad_4 => c.XK_KP_4,
        .numpad_5 => c.XK_KP_5,
        .numpad_6 => c.XK_KP_6,
        .numpad_7 => c.XK_KP_7,
        .numpad_8 => c.XK_KP_8,
        .numpad_9 => c.XK_KP_9,
        .numpad_add => c.XK_KP_Add,
        .numpad_subtract => c.XK_KP_Subtract,
        .numpad_multiply => c.XK_KP_Multiply,
        .numpad_divide => c.XK_KP_Divide,
        .numpad_enter => c.XK_KP_Enter,
        .numpad_decimal => c.XK_KP_Decimal,
        else => @intFromEnum(key),
    };
}
