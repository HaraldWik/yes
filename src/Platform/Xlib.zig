const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const xlib = @import("xlib");
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");

comptime {
    if (!build_options.xlib) @compileError("xlib backend not available unless build options xlib is set to true");
}

display: *xlib.Display,
atom_table: AtomTable,
extensions_info: ExtensionsInfo,
cursor_table: CursorTable,

pub const AtomTable = struct {
    utf8_string: xlib.Atom,
    net_wm: struct {
        name: xlib.Atom,
        state: xlib.Atom,
        state_above: xlib.Atom,
        state_fullscreen: xlib.Atom,
        state_maximized_horz: xlib.Atom,
        state_maximized_vert: xlib.Atom,
        window_type: xlib.Atom,
        window_type_normal: xlib.Atom,
        window_type_dialog: xlib.Atom,
    },
    net: struct {
        active_window: xlib.Atom,
    },
    motif_wm: struct {
        hints: xlib.Atom,
    },

    pub fn load(display: *xlib.Display) @This() {
        return .{
            .utf8_string = xlib.XInternAtom(display, "UTF8_STRING", xlib.False),
            .net_wm = .{
                .name = xlib.XInternAtom(display, "_NET_WM_NAME", xlib.False),
                .state = xlib.XInternAtom(display, "_NET_WM_STATE", xlib.False),
                .state_above = xlib.XInternAtom(display, "_NET_WM_STATE_ABOVE", xlib.False),
                .state_fullscreen = xlib.XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", xlib.False),
                .state_maximized_horz = xlib.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", xlib.False),
                .state_maximized_vert = xlib.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", xlib.False),
                .window_type = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE", xlib.False),
                .window_type_normal = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE_NORMAL", xlib.False),
                .window_type_dialog = xlib.XInternAtom(display, "_NET_WM_WINDOW_TYPE_DIALOG", xlib.False),
            },
            .net = .{
                .active_window = xlib.XInternAtom(display, " _NET_ACTIVE_WINDOW", xlib.False),
            },
            .motif_wm = .{
                .hints = xlib.XInternAtom(display, "_MOTIF_WM_HINTS", xlib.False),
            },
        };
    }
};

pub const ExtensionsInfo = struct {
    xi_opcode: u8,
    xi_supported: bool,
};

pub const CursorTable = struct {
    left_ptr: xlib.Cursor,
    xterm: xlib.Cursor,
    hand2: xlib.Cursor,
    openhand: xlib.Cursor,
    crosshair: xlib.Cursor,
    watch: xlib.Cursor,
    sb_v_double_arrow: xlib.Cursor,
    sb_h_double_arrow: xlib.Cursor,
    bottom_left_corner: xlib.Cursor,
    top_left_corner: xlib.Cursor,
    no: xlib.Cursor,
    fleur: xlib.Cursor,

    pub const Cursor = union(enum) {
        font: xlib.Cursor,
        image: xlib.XcursorImage,
    };

    pub fn load(display: *xlib.Display) @This() {
        return .{
            .left_ptr = xlib.XCreateFontCursor(display, xlib.XC_left_ptr),
            .xterm = xlib.XCreateFontCursor(display, xlib.XC_xterm),
            .hand2 = xlib.XCreateFontCursor(display, xlib.XC_hand2),
            .openhand = 0, // xlib.XCreateFontCursor(display, xlib.XC_openhand),
            .crosshair = xlib.XCreateFontCursor(display, xlib.XC_crosshair),
            .watch = xlib.XCreateFontCursor(display, xlib.XC_watch),
            .sb_v_double_arrow = xlib.XCreateFontCursor(display, xlib.XC_sb_v_double_arrow),
            .sb_h_double_arrow = xlib.XCreateFontCursor(display, xlib.XC_sb_h_double_arrow),
            .bottom_left_corner = xlib.XCreateFontCursor(display, xlib.XC_bottom_left_corner),
            .top_left_corner = xlib.XCreateFontCursor(display, xlib.XC_top_left_corner),
            .no = 0, // xlib.XCreateFontCursor(display, xlib.XC_no),
            .fleur = xlib.XCreateFontCursor(display, xlib.XC_fleur),
        };
    }

    pub fn deinit(self: @This(), display: *xlib.Display) void {
        inline for (std.meta.fields(@This())) |field| {
            const cursor: xlib.Cursor = @field(self, field.name);
            if (cursor != 0) _ = xlib.XFreeCursor(display, cursor);
        }
    }

    pub fn get(self: @This(), cursor: PlatformWindow.Cursor) xlib.Cursor {
        // XDefineCursor
        return switch (cursor) {
            .arrow => self.left_ptr,
            .text => self.xterm,
            .hand => self.hand2,
            .grab => self.left_ptr, // self.openhand,
            .crosshair => self.crosshair,
            .wait => self.watch,
            .resize_ns => self.sb_v_double_arrow,
            .resize_ew => self.sb_h_double_arrow,
            .resize_nesw => self.bottom_left_corner,
            .resize_nwse => self.top_left_corner,
            .forbidden => self.left_ptr, // self.no,
            .move => self.fleur,
            _ => @intFromEnum(cursor),
        };
    }
};

pub const Window = struct {
    interface: PlatformWindow = .{},
    handle: xlib.Window = 0,
    wm_delete_window: xlib.Atom = 0,
    colormap: xlib.Colormap = 0,
    glx_context: ?*anyopaque = null,
    move_event: ?PlatformWindow.Position = null,
};

pub fn init() !@This() {
    const display: *xlib.Display = xlib.XOpenDisplay(null) orelse return error.OpenDisplay;

    var extensions_info = std.mem.zeroes(ExtensionsInfo);
    {
        var opcode: c_int = 0;
        var event: c_int = 0;
        var err: c_int = 0;
        if (xlib.XQueryExtension(display, "XInputExtension", &opcode, &event, &err) == xlib.True) {
            extensions_info.xi_supported = true;
            extensions_info.xi_opcode = @intCast(opcode);
        }
    }

    return .{ .display = display, .atom_table = .load(display), .cursor_table = .load(display), .extensions_info = extensions_info };
}

pub fn deinit(self: @This()) void {
    self.cursor_table.deinit(self.display);
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
            .windowNative = windowNative,
            .windowFramebuffer = windowFramebuffer,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = opengl.glXGetProcAddress,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *PlatformWindow, options: PlatformWindow.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const screen = xlib.DefaultScreen(self.display);
    const screen_window = xlib.RootWindow(self.display, screen);

    switch (builtin.mode) {
        .Debug, .ReleaseSafe => if (options.surface_type == .opengl) {
            const glx_arb_create_context_supported = supported: {
                const ext_str: [*:0]const u8 = xlib.glXQueryExtensionsString(self.display, screen);
                break :supported std.mem.containsAtLeast(u8, std.mem.span(ext_str), 1, "GLX_ARB_create_context");
            };
            std.debug.assert(glx_arb_create_context_supported);
        },
        else => {},
    }

    var fbconfig: ?xlib.GLXFBConfig = null;

    const visual: *xlib.XVisualInfo = visual: switch (options.surface_type) {
        .opengl => {
            const fbattribs: [*]const c_int = &.{
                xlib.GLX_X_RENDERABLE,  xlib.True,
                xlib.GLX_DRAWABLE_TYPE, xlib.GLX_WINDOW_BIT,
                xlib.GLX_RENDER_TYPE,   xlib.GLX_RGBA_BIT,
                xlib.GLX_DOUBLEBUFFER,  xlib.True,
                xlib.GLX_RED_SIZE,      8,
                xlib.GLX_GREEN_SIZE,    8,
                xlib.GLX_BLUE_SIZE,     8,
                xlib.GLX_DEPTH_SIZE,    24,
                xlib.None,
            };

            var fbcount: c_int = undefined;
            const fbconfigs = xlib.glXChooseFBConfig(self.display, screen, fbattribs, &fbcount);
            fbconfig = fbconfigs[0];

            break :visual xlib.glXGetVisualFromFBConfig(self.display, fbconfig.?);
        },
        else => {
            var visual: xlib.XVisualInfo = .{
                .visual = xlib.XDefaultVisual(self.display, screen),
                .depth = xlib.DefaultDepth(self.display, screen),
            };
            break :visual &visual;
        },
    };

    const colormap = xlib.XCreateColormap(self.display, screen_window, visual.visual, xlib.AllocNone);
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
        screen_window,
        if (options.position) |position| @intCast(position.x) else 0,
        if (options.position) |position| @intCast(position.y) else 0,
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
    try windowSetProperty(context, platform_window, .{ .resize_policy = options.resize_policy });

    window.wm_delete_window = xlib.XInternAtom(self.display, "WM_DELETE_WINDOW", @intFromBool(false));
    if (xlib.XSetWMProtocols(self.display, window.handle, &window.wm_delete_window, 1) == xlib.False) return error.SetWMProtocols;
    if (xlib.XMapWindow(self.display, window.handle) == xlib.False) return error.MapWindow;
    try windowSetProperty(context, platform_window, .{ .always_on_top = options.always_on_top });
    if (options.fullscreen) try windowSetProperty(context, platform_window, .{ .fullscreen = options.fullscreen });
    if (options.maximized) try windowSetProperty(context, platform_window, .{ .maximized = options.maximized });
    if (options.minimized) try windowSetProperty(context, platform_window, .{ .minimized = options.minimized });
    if (!options.decorated) try windowSetProperty(context, platform_window, .{ .decorated = options.decorated });
    if (options.floating) |floating| try windowSetProperty(context, platform_window, .{ .floating = floating });
    if (xlib.XFlush(self.display) == xlib.False) return error.Flush;

    // Create OpenGL context
    switch (options.surface_type) {
        .opengl => |gl| {
            const ctx_attribs: [*]const c_int = &.{
                xlib.GLX_CONTEXT_MAJOR_VERSION_ARB, @intCast(gl.major),
                xlib.GLX_CONTEXT_MINOR_VERSION_ARB, @intCast(gl.minor),
                xlib.GLX_CONTEXT_PROFILE_MASK_ARB,  xlib.GLX_CONTEXT_CORE_PROFILE_BIT_ARB,
                xlib.None,
            };
            const glXCreateContextAttribsARB = @as(?*const fn (
                display: *xlib.Display,
                fbconfig: xlib.GLXFBConfig,
                share_context: xlib.GLXContext,
                direct: c_int, // bool
                attribs: [*]const c_int,
            ) callconv(.c) xlib.GLXContext, @ptrCast(xlib.glXGetProcAddressARB("glXCreateContextAttribsARB"))) orelse return error.LoadGlXCreateContextAttribsARB;

            window.glx_context = glXCreateContextAttribsARB(self.display, fbconfig.?, null, 1, ctx_attribs);
        },
        else => {},
    }

    if (!self.extensions_info.xi_supported) return;

    var mask: [xlib.XIMaskLen(xlib.XI_LASTEVENT)]u8 = @splat(0);

    const events = [_]u32{
        xlib.XI_Motion,
        xlib.XI_TouchBegin,
        xlib.XI_TouchUpdate,
        xlib.XI_TouchEnd,
    };

    for (events) |event| {
        const index: usize = @intCast(event / 8);
        mask[index] |= @as(u8, 1) << (@as(u3, @intCast(event % 8)));
    }

    var evmask: xlib.XIEventMask = .{
        .deviceid = xlib.XIAllDevices,
        .mask_len = @intCast(mask.len),
        .mask = &mask,
    };

    if (xlib.XISelectEvents(self.display, window.handle, &evmask, 1) != 0) return error.XISelectEvents;
    _ = xlib.XFlush(self.display);
}
fn windowClose(context: *anyopaque, platform_window: *PlatformWindow) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.glx_context) |glx_context| xlib.glXDestroyContext(self.display, @ptrCast(glx_context));
    _ = xlib.XDestroyWindow(self.display, window.handle);
    window.* = undefined;
}
fn windowPoll(context: *anyopaque, platform_window: *PlatformWindow) anyerror!?PlatformWindow.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.move_event) |move_event| {
        window.move_event = null;
        return .{ .move = move_event };
    }

    var event: xlib.XEvent = undefined;
    if (xlib.XPending(self.display) == 0) return null;
    if (xlib.XNextEvent(self.display, &event) != xlib.XCSUCCESS) return null;

    switch (event.type) {
        xlib.ClientMessage => if (@as(xlib.Atom, @intCast(event.xclient.data.l[0])) == window.wm_delete_window) return .close,
        xlib.FocusIn => return .{ .focus = true },
        xlib.FocusOut => return .{ .focus = false },
        xlib.ConfigureNotify => {
            var attrs: xlib.XWindowAttributes = undefined;
            _ = xlib.XGetWindowAttributes(self.display, window.handle, &attrs);

            var root_x: c_int = 0;
            var root_y: c_int = 0;
            var child: xlib.Window = 0;
            _ = xlib.XTranslateCoordinates(self.display, window.handle, xlib.XDefaultRootWindow(self.display), 0, 0, &root_x, &root_y, &child);

            const size: PlatformWindow.Size = .{ .width = @intCast(attrs.width), .height = @intCast(attrs.height) };
            const position: PlatformWindow.Position = .{ .x = @intCast(root_x), .y = @intCast(root_y) };

            if (window.interface.size.eql(size)) return .{ .move = position };
            if (window.interface.position.x != position.x or window.interface.position.y != position.y) {
                window.move_event = position;
                window.interface.position = position;
            }
            return if (window.interface.surface_type != .opengl and window.interface.surface_type != .vulkan) .{ .resize = size } else null;
        },
        xlib.Expose => if (window.interface.surface_type == .vulkan or window.interface.surface_type == .opengl)
            return .{ .resize = .{ .width = @intCast(event.xexpose.width), .height = @intCast(event.xexpose.height) } },
        xlib.ButtonPress, xlib.ButtonRelease => return switch (event.xbutton.button) {
            4...7 => |scroll| if (event.type == xlib.ButtonPress) .{ .mouse_scroll = switch (scroll) {
                6 => .{ .horizontal = 1.0 },
                7 => .{ .horizontal = -1.0 },
                4 => .{ .vertical = 1.0 },
                5 => .{ .vertical = -1.0 },
                else => unreachable,
            } } else null,
            else => .{ .mouse_button = .{
                .state = switch (event.type) {
                    xlib.ButtonPress => .pressed,
                    xlib.ButtonRelease => .released,
                    else => unreachable,
                },
                .button = PlatformWindow.Event.MouseButton.Button.fromX(event.xbutton.button) orelse return null,
            } },
        },
        xlib.MotionNotify => if (!self.extensions_info.xi_supported) {
            const mouse_motion: PlatformWindow.Event.MouseMotion = .{
                .x = @floatFromInt(event.xmotion.x),
                .y = @floatFromInt(event.xmotion.y),
            };
            if (mouse_motion.x != window.interface.mouse_position.x or mouse_motion.y != window.interface.mouse_position.y)
                return .{ .mouse_motion = mouse_motion };
        },
        xlib.KeyPress, xlib.KeyRelease => return .{ .key = .{
            .state = switch (event.type) {
                xlib.KeyPress => .pressed,
                xlib.KeyRelease => .released,
                else => unreachable,
            },
            .code = @intCast(event.xkey.keycode),
            .sym = PlatformWindow.Event.Key.Sym.fromXkb(xlib.XLookupKeysym(&event.xkey, @intCast(event.xkey.state & xlib.ShiftMask))) orelse return null,
        } },
        xlib.GenericEvent => {
            const gevent: *xlib.XGenericEventCookie = @ptrCast(&event);
            _ = xlib.XGetEventData(self.display, gevent);
            defer xlib.XFreeEventData(self.display, gevent);

            const xiev: *xlib.XIDeviceEvent = @ptrCast(@alignCast(gevent.data));

            // Xinput
            if (self.extensions_info.xi_supported and gevent.extension == @as(c_int, @intCast(self.extensions_info.xi_opcode))) switch (gevent.evtype) {
                xlib.XI_Motion => {
                    const mouse_motion: PlatformWindow.Event.MouseMotion = .{
                        .x = xiev.event_x,
                        .y = xiev.event_y,
                    };
                    if (mouse_motion.x != window.interface.mouse_position.x or mouse_motion.y != window.interface.mouse_position.y)
                        return .{ .mouse_motion = mouse_motion };
                },
                xlib.XI_TouchBegin => {
                    const touch_down: PlatformWindow.Event.Touch = .{
                        .id = @intCast(xiev.detail),
                        .x = xiev.event_x,
                        .y = xiev.event_y,
                    };
                    return .{ .touch_down = touch_down };
                },
                xlib.XI_TouchEnd => {
                    const touch_up: PlatformWindow.Event.Touch = .{
                        .id = @intCast(xiev.detail),
                        .x = xiev.event_x,
                        .y = xiev.event_y,
                    };
                    return .{ .touch_up = touch_up };
                },
                xlib.XI_TouchUpdate => {
                    const touch_motion: PlatformWindow.Event.Touch = .{
                        .id = @intCast(xiev.detail),
                        .x = xiev.event_x,
                        .y = xiev.event_y,
                    };
                    return .{ .touch_motion = touch_motion };
                },
                else => {},
            };
        },
        else => {},
    }
    return windowPoll(context, platform_window);
}
fn windowSetProperty(context: *anyopaque, platform_window: *PlatformWindow, property: PlatformWindow.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const screen = xlib.XDefaultRootWindow(self.display);

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
                self.atom_table.net_wm.name,
                self.atom_table.utf8_string,
                8,
                xlib.PropModeReplace,
                @ptrCast(title.ptr),
                @intCast(title.len),
            );
        },
        .size => |size| _ = xlib.XResizeWindow(self.display, window.handle, size.width, size.height),
        .position => |position| _ = xlib.XMoveWindow(self.display, window.handle, @intCast(position.x), @intCast(position.y)),
        .resize_policy => |resize_policy| {
            var hints: xlib.XSizeHints = .{};

            switch (resize_policy) {
                .resizable => |resizable| {
                    hints.flags = xlib.PMinSize | xlib.PMaxSize;

                    const width: c_int = @intCast(window.interface.size.width);
                    const height: c_int = @intCast(window.interface.size.height);
                    hints.min_width = if (!resizable) width else 0;
                    hints.min_height = if (!resizable) height else 0;
                    hints.max_width = if (!resizable) width else std.math.maxInt(c_int);
                    hints.max_height = if (!resizable) height else std.math.maxInt(c_int);
                },
                .specified => |specified| {
                    if (specified.min_size) |size| {
                        hints.flags |= xlib.PMinSize;
                        hints.min_width = @intCast(size.width);
                        hints.min_height = @intCast(size.height);
                    }
                    if (specified.max_size) |size| {
                        hints.flags |= xlib.PMaxSize;
                        hints.max_width = @intCast(size.width);
                        hints.max_height = @intCast(size.height);
                    }
                },
            }
            xlib.XSetWMNormalHints(self.display, window.handle, &hints);
        },
        .fullscreen => |fullscreen| {
            var event: xlib.XEvent = .{ .xclient = .{
                .type = xlib.ClientMessage,
                .message_type = self.atom_table.net_wm.state,
                .display = self.display,
                .window = window.handle,
                .format = 32,
                .data = .{ .l = .{ @intFromBool(fullscreen), @intCast(self.atom_table.net_wm.state_fullscreen), 0, 1, 0 } },
            } };
            _ = xlib.XSendEvent(self.display, xlib.DefaultRootWindow(self.display), xlib.False, xlib.SubstructureRedirectMask | xlib.SubstructureNotifyMask, &event);
        },
        .maximized => |maximized| {
            var event: xlib.XEvent = .{
                .xclient = .{
                    .type = xlib.ClientMessage,
                    .serial = 0,
                    .send_event = xlib.True,
                    .message_type = self.atom_table.net_wm.state,
                    .window = window.handle,
                    .format = 32,
                    .data = .{
                        .l = .{
                            @intFromBool(maximized),
                            @intCast(self.atom_table.net_wm.state_maximized_horz),
                            @intCast(self.atom_table.net_wm.state_maximized_vert),
                            1, // normal client source
                            0,
                        },
                    },
                },
            };

            _ = xlib.XSendEvent(self.display, screen, xlib.False, xlib.SubstructureRedirectMask | xlib.SubstructureNotifyMask, &event);
        },
        .minimized => |minimized| _ = if (minimized)
            xlib.XIconifyWindow(self.display, window.handle, @intCast(screen))
        else
            xlib.XMapWindow(self.display, window.handle),
        .always_on_top => |always_on_top| {
            var event: xlib.XEvent = .{
                .xclient = .{
                    .type = xlib.ClientMessage,
                    .serial = 0,
                    .send_event = xlib.True,
                    .message_type = self.atom_table.net_wm.state,
                    .window = window.handle,
                    .format = 32,
                    .data = .{
                        .l = .{
                            @intFromBool(always_on_top),
                            @intCast(self.atom_table.net_wm.state_above),
                            0,
                            1, // normal client source
                            0,
                        },
                    },
                },
            };

            _ = xlib.XSendEvent(self.display, screen, xlib.False, xlib.SubstructureRedirectMask | xlib.SubstructureNotifyMask, &event);
        },
        .floating => |floating| {
            _ = xlib.XChangeProperty(
                self.display,
                window.handle,
                self.atom_table.net_wm.window_type,
                xlib.XA_ATOM,
                32,
                xlib.PropModeReplace,
                std.mem.asBytes(&(if (floating) self.atom_table.net_wm.window_type_dialog else self.atom_table.net_wm.window_type_normal)),
                1,
            );
        },
        .decorated => |decorated| {
            const MotifWmHints = extern struct {
                flags: c_ulong,
                functions: c_ulong,
                decorated: c_ulong,
                input_mode: c_ulong,
                status: c_ulong,
            };

            var motif_hints: MotifWmHints = .{
                .flags = 1 << 1,
                .functions = 0,
                .decorated = @intFromBool(decorated),
                .input_mode = 0,
                .status = 0,
            };

            _ = xlib.XChangeProperty(self.display, window.handle, self.atom_table.motif_wm.hints, self.atom_table.motif_wm.hints, 32, xlib.PropModeReplace, @ptrCast(&motif_hints), 5);
        },
        .focused => |focus| {
            // Fallback (sometimes works)
            _ = xlib.XSetInputFocus(self.display, window.handle, xlib.RevertToParent, xlib.CurrentTime);

            var event: xlib.XEvent = undefined;
            event.xclient = .{
                .type = xlib.ClientMessage,
                .serial = 0,
                .send_event = xlib.True,
                .display = self.display,
                .window = window.handle,
                .message_type = self.atom_table.net.active_window,
                .format = 32,
                .data = .{
                    .l = .{
                        if (focus) 1 else 0,
                        xlib.CurrentTime,
                        0,
                        0,
                        0,
                    },
                },
            };

            _ = xlib.XSendEvent(self.display, screen, xlib.False, xlib.SubstructureRedirectMask | xlib.SubstructureNotifyMask, &event);
        },
        .cursor => |cursor| {
            _ = xlib.XDefineCursor(self.display, window.handle, self.cursor_table.get(cursor));
        },
    }

    _ = xlib.XFlush(self.display);
}
fn windowNative(context: *anyopaque, platform_window: *PlatformWindow) PlatformWindow.Native {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const screen = xlib.DefaultScreen(self.display);

    return .{
        .x11 = .{
            .display = self.display,
            .window = @intCast(window.handle),
            .screen = @intCast(screen),
        },
    };
}
fn windowFramebuffer(context: *anyopaque, platform_window: *PlatformWindow) anyerror!PlatformWindow.Framebuffer {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;

    std.log.info("no software rendering is currently not supported", .{});

    return undefined;
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    if (xlib.glXMakeCurrent(self.display, window.handle, @ptrCast(window.glx_context)) == xlib.False) return error.GlxMakeCurrent;
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    xlib.glXSwapBuffers(@ptrCast(self.display), window.handle);
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *PlatformWindow, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    const glXSwapIntervalEXT: *const fn (display: *xlib.Display, drawable: xlib.Drawable, interval: i32) callconv(.c) void = @ptrCast(xlib.glXGetProcAddress("glXSwapIntervalEXT") orelse return error.SwapIntervalLoad);
    glXSwapIntervalEXT(self.display, window.handle, interval);
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *PlatformWindow, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const vkCreateXlibSurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateXlibSurfaceKHR") orelse return error.LoadVkCreateXlibSurfaceKHR);

    const create_info: vulkan.Surface.CreateInfo = .{ .xlib = .{
        .display = self.display,
        .window = window.handle,
    } };

    var surface: ?*vulkan.Surface = null;
    if (vkCreateXlibSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateXlibSurfaceKHR;
    return surface orelse error.InvalidSurface;
}
