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
            @intCast(config.size.width), @intCast(config.size.height), // Width, Height
            2, // Border width
            c.BlackPixel(display, screen), // Border color
            c.BlackPixel(display, screen) // Background color
        ),
    };

    _ = c.XStoreName(display, window, config.title.ptr);
    var hints: c.XSizeHints = .{};

    if (config.min_size) |size| {
        hints.flags |= c.PMinSize;
        hints.min_width = @intCast(size.width);
        hints.min_height = @intCast(size.height);
    }

    if (config.max_size) |size| {
        hints.flags |= c.PMaxSize;
        hints.max_width = @intCast(size.width);
        hints.max_height = @intCast(size.height);
    }

    if (!config.resizable) {
        hints.flags = c.PMinSize | c.PMaxSize;
        hints.min_width = @intCast(config.size.width);
        hints.min_height = @intCast(config.size.height);
        hints.max_width = @intCast(config.size.width);
        hints.max_height = @intCast(config.size.height);
    }

    c.XSetWMNormalHints(display, window, &hints);

    var wm_delete_window: c.Atom = c.XInternAtom(display, "WM_DELETE_WINDOW", @intFromBool(false));
    _ = c.XSetWMProtocols(display, window, &wm_delete_window, 1);

    _ = c.XSelectInput(display, window, c.KeyPressMask | c.KeyReleaseMask | c.ButtonPress | c.PointerMotionMask | c.FocusChangeMask | c.ExposureMask | c.StructureNotifyMask);

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

    var attrs: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &attrs);

    { // Send initial resize event
        var event: c.XEvent = .{
            .xconfigure = .{
                .type = c.ConfigureNotify,
                .display = display,
                .event = window,
                .window = window,
                .x = attrs.x,
                .y = attrs.y,
                .width = attrs.width,
                .height = attrs.height,
                .border_width = attrs.border_width,
                .above = c.None,
                .override_redirect = c.False,
            },
        };
        event.type = c.ConfigureNotify;
        _ = c.XSendEvent(display, window, c.False, c.StructureNotifyMask, &event);
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
            .width = @intCast(event.xconfigure.width),
            .height = @intCast(event.xconfigure.height),
        } },
        c.ButtonPress => .{ .mouse = .{ .click = .{
            .button = Event.Mouse.Button.fromX(event.xbutton.button) orelse return null,
            .position = .{
                .x = @intCast(event.xbutton.x),
                .y = @intCast(event.xbutton.y),
            },
        } } },
        c.MotionNotify => .{ .mouse = .{ .move = .{
            .x = @intCast(event.xmotion.x),
            .y = @intCast(event.xmotion.y),
        } } },
        c.KeyPress => .{ .key_down = Event.Key.fromX(c.XLookupKeysym(&event.xkey, if (event.xkey.state & c.ShiftMask == 1) 1 else 0)) orelse return null },
        c.KeyRelease => .{ .key_up = Event.Key.fromX(c.XLookupKeysym(&event.xkey, if (event.xkey.state & c.ShiftMask == 1) 1 else 0)) orelse return null },
        else => null,
    };
}

pub fn getSize(self: @This()) root.Window.Size {
    var root_window: c.Window = undefined;
    var x: c_int = 0;
    var y: c_int = 0;
    var width: c_uint = 0;
    var height: c_uint = 0;
    var border: c_uint = 0;
    var depth: c_uint = 0;

    _ = c.XGetGeometry(self.display, self.window, &root_window, &x, &y, &width, &height, &border, &depth);
    return .{ .width = @intCast(width), .height = @intCast(height) };
}
