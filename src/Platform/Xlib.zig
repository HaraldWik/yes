const std = @import("std");
const build_options = @import("build_options");
const xlib = @import("xlib");
const vulkan = @import("../vulkan.zig");
const Platform = @import("../Platform.zig");

comptime {
    if (!build_options.xlib) @compileError("xlib backend not available unless build options xlib is set to true");
}

display: *xlib.Display,
atom_table: AtomTable,

pub const AtomTable = struct {
    utf8_string: xlib.Atom,
    net_wm_name: xlib.Atom,

    net_wm_state: xlib.Atom,
    net_wm_state_fullscreen: xlib.Atom,

    net_wm_state_maximized_horz: xlib.Atom,
    net_wm_state_maximized_vert: xlib.Atom,

    pub fn load(display: *xlib.Display) @This() {
        return .{
            .utf8_string = xlib.XInternAtom(display, "UTF8_STRING", xlib.False),
            .net_wm_name = xlib.XInternAtom(display, "_NET_WM_NAME", xlib.False),
            .net_wm_state = xlib.XInternAtom(display, "_NET_WM_STATE", xlib.False),
            .net_wm_state_fullscreen = xlib.XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", xlib.False),
            .net_wm_state_maximized_horz = xlib.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", xlib.False),
            .net_wm_state_maximized_vert = xlib.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", xlib.False),
        };
    }
};

pub const Window = struct {
    interface: Platform.Window = .{},
    handle: xlib.Window = 0,
    wm_delete_window: xlib.Atom = 0,
    glx_context: ?*anyopaque = null,
    move_event: ?Platform.Window.Position = null,
};

pub fn init() !@This() {
    const display: *xlib.Display = xlib.XOpenDisplay(null) orelse return error.OpenDisplay;
    return .{ .display = display, .atom_table = .load(display) };
}

pub fn deinit(self: @This()) void {
    _ = xlib.XCloseDisplay(self.display);
}

pub fn platform(self: *@This()) Platform {
    return .{
        .ptr = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const screen = xlib.DefaultScreen(self.display);
    const root = xlib.RootWindow(self.display, screen);

    const visual: *xlib.XVisualInfo = visual: switch (options.surface_type) {
        .opengl => {
            var attribute_list = [_]c_int{
                xlib.GLX_RGBA,
                xlib.GLX_DOUBLEBUFFER,
                xlib.GLX_DEPTH_SIZE,
                24,
                xlib.GLX_STENCIL_SIZE,
                8,
                xlib.GLX_NONE,
            };
            break :visual xlib.glXChooseVisual(self.display, screen, &attribute_list) orelse return error.ChooseVisual;
        },
        else => {
            var visual: xlib.XVisualInfo = .{
                .visual = xlib.XDefaultVisual(self.display, screen),
                .depth = xlib.DefaultDepth(self.display, screen),
            };
            break :visual &visual;
        },
    };

    const colormap = xlib.XCreateColormap(self.display, root, visual.visual, xlib.AllocNone);
    var window_attributes: xlib.XSetWindowAttributes = .{
        .colormap = colormap,
        .event_mask =
        // zig fmt: off
            xlib.FocusChangeMask |
            xlib.EnterWindowMask | xlib.LeaveWindowMask |
            xlib.KeyPressMask | xlib.KeyReleaseMask |
            xlib.ButtonPressMask | xlib.ButtonReleaseMask |
            xlib.PointerMotionMask |
            xlib.ExposureMask |
            xlib.StructureNotifyMask,
        // zig fmt: on
    };

    window.handle = xlib.XCreateWindow(
        self.display,
        root,
        0,
        0,
        @intCast(options.size.width),
        @intCast(options.size.height),
        0,
        visual.depth,
        xlib.InputOutput,
        visual.visual,
        xlib.CWColormap | xlib.CWEventMask,
        &window_attributes,
    );
    errdefer _ = xlib.XDestroyWindow(self.display, window.handle);

    try windowSetProperty(context, platform_window, .{ .title = options.title });

    var hints: xlib.XSizeHints = .{};
    if (options.min_size) |size| {
        hints.flags |= xlib.PMinSize;
        hints.min_width = @intCast(size.width);
        hints.min_height = @intCast(size.height);
    }

    if (options.max_size) |size| {
        hints.flags |= xlib.PMaxSize;
        hints.max_width = @intCast(size.width);
        hints.max_height = @intCast(size.height);
    }

    if (!options.resizable) {
        hints.flags = xlib.PMinSize | xlib.PMaxSize;
        hints.base_width = @intCast(options.size.width);
        hints.base_height = @intCast(options.size.height);
        hints.min_width = @intCast(options.size.width);
        hints.min_height = @intCast(options.size.height);
        hints.max_width = @intCast(options.size.width);
        hints.max_height = @intCast(options.size.height);
    }

    xlib.XSetWMNormalHints(self.display, window.handle, &hints);

    window.wm_delete_window = xlib.XInternAtom(self.display, "WM_DELETE_WINDOW", @intFromBool(false));
    if (xlib.XSetWMProtocols(self.display, window.handle, &window.wm_delete_window, 1) == xlib.False) return error.SetWMProtocols;

    const MotifWmHints = extern struct {
        flags: c_ulong,
        functions: c_ulong,
        decorations: c_ulong,
        input_mode: c_ulong,
        status: c_ulong,
    };
    const MWM_HINTS_DECORATIONS = 1 << 1;

    var motif_hints: MotifWmHints = .{
        .flags = MWM_HINTS_DECORATIONS,
        .functions = 0,
        .decorations = @intFromBool(options.decoration),
        .input_mode = 0,
        .status = 0,
    };

    const motif = xlib.XInternAtom(self.display, "_MOTIF_WM_HINTS", xlib.False);

    _ = xlib.XChangeProperty(
        self.display,
        window.handle,
        motif,
        motif,
        32,
        xlib.PropModeReplace,
        @ptrCast(&motif_hints),
        5,
    );

    if (xlib.XMapWindow(self.display, window.handle) == xlib.False) return error.MapWindow;
    if (xlib.XFlush(self.display) == xlib.False) return error.Flush;

    if (options.surface_type == .opengl)
        window.glx_context = xlib.glXCreateContext(self.display, visual, null, @intFromBool(true)) orelse return error.CreateGlxContext;

    { // Send initial resize event
        var attrs: xlib.XWindowAttributes = undefined;
        if (xlib.XGetWindowAttributes(self.display, window.handle, &attrs) == xlib.False) return error.GetWindowAttributes;

        var event: xlib.XEvent = .{
            .xconfigure = .{
                .type = xlib.ConfigureNotify,
                .display = self.display,
                .event = window.handle,
                .window = window.handle,
                .x = attrs.x,
                .y = attrs.y,
                .width = attrs.width,
                .height = attrs.height,
                .border_width = attrs.border_width,
                .above = xlib.None,
                .override_redirect = xlib.False,
            },
        };
        event.type = xlib.ConfigureNotify;
        _ = xlib.XSendEvent(self.display, window.handle, xlib.False, xlib.StructureNotifyMask, &event);
    }
}

fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = xlib.XDestroyWindow(self.display, window.handle);
    window.* = undefined;
}

fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.move_event) |move_event| {
        window.move_event = null;
        return .{ .move = move_event };
    }

    var event: xlib.XEvent = undefined;
    while (xlib.XPending(self.display) > 0) {
        if (xlib.XNextEvent(self.display, &event) != xlib.XCSUCCESS) return null;
    }

    return switch (event.type) {
        xlib.ClientMessage => if (@as(xlib.Atom, @intCast(event.xclient.data.l[0])) == window.wm_delete_window) .close else null,
        xlib.FocusIn => .{ .focus = .enter },
        xlib.FocusOut => .{ .focus = .leave },
        xlib.ConfigureNotify => {
            var attrs: xlib.XWindowAttributes = undefined;
            _ = xlib.XGetWindowAttributes(self.display, window.handle, &attrs);

            var root_x: c_int = 0;
            var root_y: c_int = 0;
            var child: xlib.Window = 0;
            _ = xlib.XTranslateCoordinates(self.display, window.handle, xlib.XDefaultRootWindow(self.display), 0, 0, &root_x, &root_y, &child);

            const size: Platform.Window.Size = .{ .width = @intCast(attrs.width), .height = @intCast(attrs.height) };
            const position: Platform.Window.Position = .{ .x = @intCast(root_x), .y = @intCast(root_y) };

            if (window.interface.size.eql(size)) return .{ .move = position };
            if (window.interface.position.x != position.x or window.interface.position.y != position.y) {
                window.move_event = position;
                // update the stored position
                window.interface.position = position;
            }
            return .{ .resize = size };
        },
        xlib.ButtonPress, xlib.ButtonRelease => switch (event.xbutton.button) {
            4...7 => |scroll| .{ .mouse_scroll = switch (scroll) {
                6 => .{ .x = 1 },
                7 => .{ .x = -1 },
                4 => .{ .y = 1 },
                5 => .{ .y = -1 },
                else => unreachable,
            } },
            else => .{ .mouse_button = .{
                .state = switch (event.type) {
                    xlib.ButtonPress => .pressed,
                    xlib.ButtonRelease => .released,
                    else => unreachable,
                },
                .type = Platform.Window.Event.MouseButton.Type.fromX(event.xbutton.button) orelse return null,
                .position = .{
                    .x = @intCast(event.xbutton.x),
                    .y = @intCast(event.xbutton.y),
                },
            } },
        },
        xlib.MotionNotify => .{ .mouse_move = .{
            .x = @intCast(event.xmotion.x),
            .y = @intCast(event.xmotion.y),
        } },
        xlib.KeyPress, xlib.KeyRelease => .{ .key = .{
            .state = switch (event.type) {
                xlib.KeyPress => .pressed,
                xlib.KeyRelease => .released,
                else => unreachable,
            },
            .code = @intCast(event.xkey.keycode),
            .sym = Platform.Window.Event.Key.Sym.fromXkb(xlib.XLookupKeysym(&event.xkey, @intCast(event.xkey.state & xlib.ShiftMask))) orelse return null,
        } },
        else => null,
    };
}

fn windowSetProperty(context: *anyopaque, platform_window: *Platform.Window, property: Platform.Window.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (property) {
        .title => |title| {
            // Set legacy WM_NAME for older clients
            _ = xlib.XChangeProperty(
                self.display,
                window.handle,
                xlib.XA_WM_NAME,
                xlib.XA_STRING,
                8,
                xlib.PropModeReplace,
                @ptrCast(title.ptr),
                @intCast(title.len),
            );

            _ = xlib.XChangeProperty(
                self.display,
                window.handle,
                self.atom_table.net_wm_name,
                self.atom_table.utf8_string,
                8,
                xlib.PropModeReplace,
                @ptrCast(title.ptr),
                @intCast(title.len),
            );
        },
        .size => |size| {
            _ = xlib.XResizeWindow(self.display, window.handle, size.width, size.height);
            _ = xlib.XFlush(self.display);
        },
        .position => |position| {
            _ = xlib.XMoveWindow(self.display, window.handle, @intCast(position.x), @intCast(position.y));
            _ = xlib.XFlush(self.display);
        },
        .fullscreen => |fullscreen| {
            var event: xlib.XEvent = .{ .xclient = .{
                .type = xlib.ClientMessage,
                .message_type = self.atom_table.net_wm_state,
                .display = self.display,
                .window = window.handle,
                .format = 32,
                .data = .{ .l = .{ @intFromBool(fullscreen), @intCast(self.atom_table.net_wm_state_fullscreen), 0, 1, 0 } },
            } };

            _ = xlib.XSendEvent(self.display, xlib.DefaultRootWindow(self.display), xlib.False, xlib.SubstructureRedirectMask | xlib.SubstructureNotifyMask, &event);
            _ = xlib.XFlush(self.display);
        },
        .maximize => |maximize| {
            const root_screen = xlib.XDefaultRootWindow(self.display);

            var event: xlib.XEvent = .{
                .xclient = .{
                    .type = xlib.ClientMessage,
                    .serial = 0,
                    .send_event = xlib.True,
                    .message_type = self.atom_table.net_wm_state,
                    .window = window.handle,
                    .format = 32,
                    .data = .{
                        .l = .{
                            @intFromBool(maximize),
                            @intCast(self.atom_table.net_wm_state_maximized_horz),
                            @intCast(self.atom_table.net_wm_state_maximized_vert),
                            1, // normal client source
                            0,
                        },
                    },
                },
            };

            _ = xlib.XSendEvent(
                self.display,
                root_screen,
                xlib.False,
                xlib.SubstructureRedirectMask | xlib.SubstructureNotifyMask,
                &event,
            );
            _ = xlib.XFlush(self.display);
        },
        .minimize => |minimize| {
            const display = self.display;
            const root_screen = xlib.XDefaultScreen(display);

            if (minimize)
                _ = xlib.XIconifyWindow(display, window.handle, root_screen)
            else
                _ = xlib.XMapWindow(display, window.handle);
            _ = xlib.XFlush(display);
        },
        .always_on_top => {},
        .floating => {},
    }
}

fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *Platform.Window, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
    _ = interval;
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *Platform.Window, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const vkCreateXlibSurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateXlibSurfaceKHR"));

    const create_info: vulkan.Surface.CreateInfo = .{ .xlib = .{
        .display = self.display,
        .window = window.handle,
    } };

    var surface: ?*vulkan.Surface = null;
    if (vkCreateXlibSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateXlibSurfaceKHR;
    return surface orelse error.InvalidSurface;
}
