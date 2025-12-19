const std = @import("std");
const Window = @import("Window.zig");
const x11 = @import("x11");

window: x11.Window,
display: *x11.Display,
wm_delete_window: x11.Atom,
api: GraphicsApi,

pub const GraphicsApi = union(Window.GraphicsApi.Tag) {
    opengl: struct {
        context: @typeInfo(x11.GLXContext).optional.child,
    },
    vulkan: struct {},
    none,
};

pub fn open(config: Window.Config) !@This() {
    const display: *x11.Display = x11.XOpenDisplay(null) orelse return error.OpenDisplay;
    errdefer _ = x11.XCloseDisplay(display);
    const screen = x11.DefaultScreen(display);
    const root = x11.RootWindow(display, screen);

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
                .colormap = x11.XCreateColormap(display, root, visual.visual, x11.AllocNone),
                .event_mask = x11.ExposureMask | x11.KeyPressMask | x11.StructureNotifyMask,
            };

            const window: x11.Window = x11.XCreateWindow(
                display,
                root,
                0,
                0,
                @intCast(config.size.width),
                @intCast(config.size.height),
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
        .none => x11.XCreateSimpleWindow(display, root, // Parent window
            0, 0, // X, Y position
            @intCast(config.size.width), @intCast(config.size.height), // Width, Height
            2, // Border width
            x11.BlackPixel(display, screen), // Border color
            x11.BlackPixel(display, screen) // Background color
        ),
    };
    errdefer _ = x11.XDestroyWindow(display, window);

    // _ = x11.XStoreName(display, window, config.title.ptr);
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
    if (x11.XSetWMProtocols(display, window, &wm_delete_window, 1) == x11.False) return error.SetWMProtocols;

    if (x11.XSelectInput(
        display,
        window,
        // zig fmt: off
        x11.KeyPressMask | x11.KeyReleaseMask |
        x11.ButtonPressMask | x11.ButtonReleaseMask |
        x11.PointerMotionMask |
        x11.FocusChangeMask |
        x11.ExposureMask |
        x11.StructureNotifyMask,
        // zig fmt: on
    ) == x11.False) return error.SelectInput;

    if (x11.XMapWindow(display, window) == x11.False) return error.MapWindow;
    if (x11.XFlush(display) == x11.False) return error.Flush;

    const api: GraphicsApi = switch (config.api) {
        .opengl => .{ .opengl = .{
            .context = x11.glXCreateContext(display, visual, null, @intFromBool(true)) orelse return error.CreateGlxContext,
        } },
        .vulkan => .{ .vulkan = .{} },
        .none => .none,
    };

    { // Send initial resize event
        var attrs: x11.XWindowAttributes = undefined;
        if (x11.XGetWindowAttributes(display, window, &attrs) == x11.False) return error.GetWindowAttributes;

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
        .api = api,
    };
}

pub fn close(self: @This()) void {
    _ = x11.XDestroyWindow(self.display, self.window);
    _ = x11.XCloseDisplay(self.display);
}

pub fn poll(self: @This()) !?Window.Event {
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
        x11.ButtonPress, x11.ButtonRelease => switch (event.xbutton.button) {
            4...7 => |scroll| Window.Event{ .mouse = .{
                .scroll = switch (scroll) {
                    6 => .{ .x = 1 },
                    7 => .{ .x = -1 },
                    4 => .{ .y = 1 },
                    5 => .{ .y = -1 },
                    else => unreachable,
                },
            } },
            else => .{ .mouse = .{ .button = .{
                .state = switch (event.type) {
                    x11.ButtonPress => .press,
                    x11.ButtonRelease => .release,
                    else => unreachable,
                },
                .code = Window.Event.Mouse.Button.Code.fromX11(event.xbutton.button) orelse return null,
                .position = .{
                    .x = @intCast(event.xbutton.x),
                    .y = @intCast(event.xbutton.y),
                },
            } } },
        },
        x11.MotionNotify => .{ .mouse = .{ .move = .{
            .x = @intCast(event.xmotion.x),
            .y = @intCast(event.xmotion.y),
        } } },
        x11.KeyPress, x11.KeyRelease => .{ .key = .{
            .state = switch (event.type) {
                x11.KeyPress => .press,
                x11.KeyRelease => .release,
                else => unreachable,
            },
            .code = @intCast(event.xkey.keycode),
            .sym = Window.Event.Key.Sym.fromXkb(x11.XLookupKeysym(&event.xkey, @intCast(event.xkey.state & x11.ShiftMask))) orelse return null,
        } },
        else => null,
    };
}

pub fn getSize(self: @This()) Window.Size {
    var root: x11.Window = undefined;
    var x: c_int = 0;
    var y: c_int = 0;
    var width: c_uint = 0;
    var height: c_uint = 0;
    var border: c_uint = 0;
    var depth: c_uint = 0;

    _ = x11.XGetGeometry(self.display, self.window, &root, &x, &y, &width, &height, &border, &depth);
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

pub fn setTitle(self: @This(), title: [:0]const u8) void {
    const UTF8_STRING = x11.XInternAtom(self.display, "UTF8_STRING", 0);
    const NET_WM_NAME = x11.XInternAtom(self.display, "_NET_WM_NAME", 0);

    // Set UTF-8 version (required by modern WMs)
    _ = x11.XChangeProperty(
        self.display,
        self.window,
        NET_WM_NAME,
        UTF8_STRING,
        8,
        x11.PropModeReplace,
        @ptrCast(title.ptr),
        @intCast(title.len),
    );

    // Set legacy WM_NAME for older clients
    _ = x11.XChangeProperty(
        self.display,
        self.window,
        x11.XA_WM_NAME,
        x11.XA_STRING,
        8,
        x11.PropModeReplace,
        @ptrCast(title.ptr),
        @intCast(title.len),
    );
}

pub fn fullscreen(self: @This(), state: bool) void {
    const wm_state: x11.Atom = x11.XInternAtom(self.display, "_NET_WM_STATE", x11.False);
    const fs_state: x11.Atom = x11.XInternAtom(self.display, "_NET_WM_STATE_FULLSCREEN", x11.False);

    var event: x11.XEvent = .{ .xclient = .{
        .type = x11.ClientMessage,
        .message_type = wm_state,
        .display = self.display,
        .window = self.window,
        .format = 32,
        .data = .{ .l = .{ @intFromBool(state), @intCast(fs_state), 0, 1, 0 } },
    } };

    _ = x11.XSendEvent(self.display, x11.DefaultRootWindow(self.display), x11.False, x11.SubstructureRedirectMask | x11.SubstructureNotifyMask, &event);
    _ = x11.XFlush(self.display);
}

pub fn maximize(self: @This(), state: bool) void {
    const display = self.display;
    const root = x11.XDefaultRootWindow(display);

    const wm_state = x11.XInternAtom(display, "_NET_WM_STATE", x11.False);
    const horiz = x11.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", x11.False);
    const vert = x11.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", x11.False);

    const action: c_long = if (state) 1 else 0; // add / remove

    var event: x11.XEvent = .{
        .xclient = .{
            .type = x11.ClientMessage,
            .serial = 0,
            .send_event = x11.True,
            .message_type = wm_state,
            .window = self.window,
            .format = 32,
            .data = .{
                .l = .{
                    action,
                    @intCast(horiz),
                    @intCast(vert),
                    1, // normal client source
                    0,
                },
            },
        },
    };

    _ = x11.XSendEvent(
        display,
        root,
        x11.False,
        x11.SubstructureRedirectMask | x11.SubstructureNotifyMask,
        &event,
    );

    _ = x11.XFlush(display);
}

pub fn minimize(self: @This()) void {
    const display = self.display;
    const screen = x11.XDefaultScreen(display);

    _ = x11.XIconifyWindow(display, self.window, screen);
    _ = x11.XFlush(display);
}

pub fn setPosition(self: @This(), position: Window.Position(i32)) void {
    _ = x11.XMoveWindow(self.display, self.window, @intCast(position.x), @intCast(position.y));
    _ = x11.XFlush(self.display);
}
