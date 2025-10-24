const std = @import("std");
const c = @cImport({ // TODO: Remove c import
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/Xatom.h");
});

window: c.Window,
display: *c.Display,
wm_delete_window: c.Atom,

pub fn open(config: @import("root.zig").Window.Config) !@This() {
    const display: *c.Display = c.XOpenDisplay(null) orelse return error.OpenDisplay;
    const screen = c.DefaultScreen(display);

    const root: c.Window = c.RootWindow(display, screen);

    const window: c.Window = c.XCreateSimpleWindow(display, root, // Parent window
        0, 0, // X, Y position
        @intCast(config.width), @intCast(config.width), // Width, Height
        2, // Border width
        c.BlackPixel(display, screen), // Border color
        c.BlackPixel(display, screen) // Background color
    );

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

pub fn next(self: @This()) ?@import("root.zig").Event {
    var event: c.XEvent = undefined;
    if (c.XNextEvent(self.display, &event) != c.XCSUCCESS) return null;

    return switch (event.type) {
        c.Expose => expose: {
            // The window needs redrawing. This is where your rendering code goes.
            // (e.g., draw text, graphics)
            break :expose .none;
        },

        c.KeyPress => key: {
            // Handle keyboard input
            break :key .none;
        },

        c.ClientMessage => if (event.xclient.data.l[0] == self.wm_delete_window) null else .none,
        else => .none,
    };
}
