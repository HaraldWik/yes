const std = @import("std");
const root = @import("../root.zig");
const c = @import("../root.zig").native.x;
const Event = @import("../event.zig").Union;

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

    _ = c.XSelectInput(display, window, c.KeyPressMask | c.KeyReleaseMask | c.FocusChangeMask | c.ExposureMask | c.StructureNotifyMask);

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

pub fn poll(self: @This()) ?Event {
    var event: c.XEvent = undefined;
    while (c.XPending(self.display) > 0) {
        if (c.XNextEvent(self.display, &event) != c.XCSUCCESS) return null;
    }

    return switch (event.type) {
        c.ClientMessage => if (@as(c.Atom, @intCast(event.xclient.data.l[0])) == self.wm_delete_window) .close else null,
        c.ConfigureNotify => .{ .resize = .{
            @intCast(event.xconfigure.width),
            @intCast(event.xconfigure.height),
        } },
        c.ButtonPress => .{ .mouse = .{
            .right = event.xbutton.button == 3,
            .middle = event.xbutton.button == 2,
            .left = event.xbutton.button == 1,
            .forward = event.xbutton.button == 9,
            .backward = event.xbutton.button == 8,
            .x = @intCast(event.xbutton.x),
            .y = @intCast(event.xbutton.y),
        } },
        c.KeyPress => .{ .key_down = .fromX(c.XLookupKeysym(&event.xkey, if (event.xkey.state & c.ShiftMask == 1) 1 else 0)) },
        c.KeyRelease => .{ .key_up = .fromX(c.XLookupKeysym(&event.xkey, if (event.xkey.state & c.ShiftMask == 1) 1 else 0)) },
        else => null,
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
