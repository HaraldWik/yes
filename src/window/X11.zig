const std = @import("std");
const root = @import("../root.zig");
const x11 = @import("../root.zig").native.x11;
const Window = @import("Window.zig");
const Event = @import("../event.zig").Union;

window: x11.Window,
display: *x11.Display,
wm_delete_window: x11.Atom,

pub fn open(config: Window.Config) !@This() {
    const display: *x11.Display = x11.XOpenDisplay(null) orelse return error.OpenDisplay;
    const screen = x11.DefaultScreen(display);

    var visual: *x11.XVisualInfo = undefined;
    const window: x11.Window = window: switch (config.api) {
        .opengl => {
            var visual_attribs = [_:0]c_int{
                x11.GLX_RGBA,
                x11.GLX_DOUBLEBUFFER,
                x11.GLX_DEPTH_SIZE,
                24,
                x11.GLX_STENCIL_SIZE,
                8,
                x11.GLX_NONE,
            };

            visual = x11.glXChooseVisual(display, screen, &visual_attribs);

            var swa: x11.XSetWindowAttributes = .{
                .colormap = x11.XCreateColormap(display, x11.RootWindow(display, screen), visual.visual, x11.AllocNone),
                .event_mask = x11.ExposureMask | x11.KeyPressMask | x11.StructureNotifyMask,
            };

            const window: x11.Window = x11.XCreateWindow(
                display,
                x11.RootWindow(display, screen),
                0,
                0,
                800,
                600,
                0,
                visual.depth,
                x11.InputOutput,
                visual.visual,
                x11.CWColormap | x11.CWEventMask,
                &swa,
            );
            break :window window;
        },
        .vulkan => return error.NotImplemented, // TODO: add vulkan window for X
        .none => x11.XCreateSimpleWindow(display, x11.RootWindow(display, screen), // Parent window
            0, 0, // X, Y position
            @intCast(config.size.width), @intCast(config.size.height), // Width, Height
            2, // Border width
            x11.BlackPixel(display, screen), // Border color
            x11.BlackPixel(display, screen) // Background color
        ),
    };

    _ = x11.XStoreName(display, window, config.title.ptr);
    var hints: x11.XSizeHints = .{};

    if (config.min_size) |size| {
        hints.flags |= x11.PMinSize;
        hints.min_width = @intCast(size.width);
        hints.min_height = @intCast(size.height);
    }

    if (config.max_size) |size| {
        hints.flags |= x11.PMaxSize;
        hints.max_width = @intCast(size.width);
        hints.max_height = @intCast(size.height);
    }

    if (!config.resizable) {
        hints.flags = x11.PMinSize | x11.PMaxSize;
        hints.base_width = @intCast(config.size.width);
        hints.base_height = @intCast(config.size.height);
        hints.min_width = @intCast(config.size.width);
        hints.min_height = @intCast(config.size.height);
        hints.max_width = @intCast(config.size.width);
        hints.max_height = @intCast(config.size.height);
    }

    x11.XSetWMNormalHints(display, window, &hints);

    var wm_delete_window: x11.Atom = x11.XInternAtom(display, "WM_DELETE_WINDOW", @intFromBool(false));
    _ = x11.XSetWMProtocols(display, window, &wm_delete_window, 1);

    _ = x11.XSelectInput(display, window, x11.KeyPressMask | x11.KeyReleaseMask | x11.ButtonPressMask | x11.ButtonReleaseMask | x11.PointerMotionMask | x11.FocusChangeMask | x11.ExposureMask | x11.StructureNotifyMask);

    _ = x11.XMapWindow(display, window);
    _ = x11.XFlush(display);

    switch (config.api) {
        .opengl => {
            const ctx: x11.GLXContext = x11.glXCreateContext(display, visual, null, @intFromBool(true));
            _ = x11.glXMakeCurrent(display, window, ctx);
        },
        .vulkan => {},
        .none => {},
    }

    var attrs: x11.XWindowAttributes = undefined;
    _ = x11.XGetWindowAttributes(display, window, &attrs);

    { // Send initial resize event
        var event: x11.XEvent = .{
            .xconfigure = .{
                .type = x11.ConfigureNotify,
                .display = display,
                .event = window,
                .window = window,
                .x = attrs.x,
                .y = attrs.y,
                .width = attrs.width,
                .height = attrs.height,
                .border_width = attrs.border_width,
                .above = x11.None,
                .override_redirect = x11.False,
            },
        };
        event.type = x11.ConfigureNotify;
        _ = x11.XSendEvent(display, window, x11.False, x11.StructureNotifyMask, &event);
    }

    return .{
        .window = window,
        .display = display,
        .wm_delete_window = wm_delete_window,
    };
}

pub fn close(self: @This()) void {
    _ = x11.XDestroyWindow(self.display, self.window);
    _ = x11.XCloseDisplay(self.display);
}

pub fn poll(self: @This()) ?Event {
    var event: x11.XEvent = undefined;
    while (x11.XPending(self.display) > 0) {
        if (x11.XNextEvent(self.display, &event) != x11.XCSUCCESS) return null;
    }

    return switch (event.type) {
        x11.ClientMessage => if (@as(x11.Atom, @intCast(event.xclient.data.l[0])) == self.wm_delete_window) .close else null,
        x11.ConfigureNotify => .{ .resize = .{
            .width = @intCast(event.xconfigure.width),
            .height = @intCast(event.xconfigure.height),
        } },
        x11.ButtonPress => .{ .mouse = .{ .click_down = .{
            .button = Event.Mouse.Button.fromX(event.xbutton.button) orelse return null,
            .position = .{
                .x = @intCast(event.xbutton.x),
                .y = @intCast(event.xbutton.y),
            },
        } } },
        x11.ButtonRelease => .{ .mouse = .{ .click_up = .{
            .button = Event.Mouse.Button.fromX(event.xbutton.button) orelse return null,
            .position = .{
                .x = @intCast(event.xbutton.x),
                .y = @intCast(event.xbutton.y),
            },
        } } },
        x11.MotionNotify => .{ .mouse = .{ .move = .{
            .x = @intCast(event.xmotion.x),
            .y = @intCast(event.xmotion.y),
        } } },
        x11.KeyPress => .{ .key_down = Event.Key.fromXkb(x11.XLookupKeysym(&event.xkey, if (event.xkey.state & x11.ShiftMask == 1) 1 else 0)) orelse return null },
        x11.KeyRelease => .{ .key_up = Event.Key.fromXkb(x11.XLookupKeysym(&event.xkey, if (event.xkey.state & x11.ShiftMask == 1) 1 else 0)) orelse return null },
        else => null,
    };
}

pub fn getSize(self: @This()) Window.Size {
    var root_window: x11.Window = undefined;
    var x: c_int = 0;
    var y: c_int = 0;
    var width: c_uint = 0;
    var height: c_uint = 0;
    var border: c_uint = 0;
    var depth: c_uint = 0;

    _ = x11.XGetGeometry(self.display, self.window, &root_window, &x, &y, &width, &height, &border, &depth);
    return .{ .width = @intCast(width), .height = @intCast(height) };
}
