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
    net_wm: struct {
        name: xlib.Atom,
        state: xlib.Atom,
        state_fullscreen: xlib.Atom,
        state_maximized_horz: xlib.Atom,
        state_maximized_vert: xlib.Atom,
    },

    pub fn load(display: *xlib.Display) @This() {
        return .{
            .utf8_string = xlib.XInternAtom(display, "UTF8_STRING", xlib.False),
            .net_wm = .{
                .name = xlib.XInternAtom(display, "_NET_WM_NAME", xlib.False),
                .state = xlib.XInternAtom(display, "_NET_WM_STATE", xlib.False),
                .state_fullscreen = xlib.XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", xlib.False),
                .state_maximized_horz = xlib.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_HORZ", xlib.False),
                .state_maximized_vert = xlib.XInternAtom(display, "_NET_WM_STATE_MAXIMIZED_VERT", xlib.False),
            },
        };
    }
};

pub const Window = struct {
    interface: Platform.Window = .{},
    handle: xlib.Window = 0,
    wm_delete_window: xlib.Atom = 0,
    colormap: xlib.Colormap = 0,
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
    const screen_window = xlib.RootWindow(self.display, screen);

    const glx_arb_create_context_supported = if (options.surface_type == .opengl) supported: {
        const ext_str: [*:0]const u8 = xlib.glXQueryExtensionsString(self.display, screen);
        break :supported std.mem.containsAtLeast(u8, std.mem.span(ext_str), 1, "GLX_ARB_create_context");
    } else false;
    var fbconfig: ?xlib.GLXFBConfig = null;

    const visual: *xlib.XVisualInfo = visual: switch (options.surface_type) {
        .opengl => if (glx_arb_create_context_supported) {
            const possible_attributes: []const ?[*]const c_int = &.{
                &.{ // Full “preferred” modern attributes
                    xlib.GLX_X_RENDERABLE,  1,
                    xlib.GLX_DRAWABLE_TYPE, xlib.GLX_WINDOW_BIT,
                    xlib.GLX_RENDER_TYPE,   xlib.GLX_RGBA_BIT,
                    xlib.GLX_DOUBLEBUFFER,  1,
                    xlib.GLX_RED_SIZE,      8,
                    xlib.GLX_GREEN_SIZE,    8,
                    xlib.GLX_BLUE_SIZE,     8,
                    xlib.GLX_ALPHA_SIZE,    8,
                    xlib.GLX_DEPTH_SIZE,    24,
                    xlib.GLX_STENCIL_SIZE,  8,
                    xlib.GLX_SAMPLE_BUFFERS, 1, // enable multisampling if available
                    xlib.GLX_SAMPLES, 4, // 4x MSAA
                    xlib.GLX_NONE,
                },
                &.{ // Medium fallback (drop stencil or multisample)
                    xlib.GLX_X_RENDERABLE,  1,
                    xlib.GLX_DRAWABLE_TYPE, xlib.GLX_WINDOW_BIT,
                    xlib.GLX_RENDER_TYPE,   xlib.GLX_RGBA_BIT,
                    xlib.GLX_DOUBLEBUFFER,  1,
                    xlib.GLX_RED_SIZE,      8,
                    xlib.GLX_GREEN_SIZE,    8,
                    xlib.GLX_BLUE_SIZE,     8,
                    xlib.GLX_ALPHA_SIZE,    8,
                    xlib.GLX_DEPTH_SIZE,    24,
                    xlib.GLX_NONE,
                },
                &.{ // Minimal fallback (just a drawable)
                    xlib.GLX_X_RENDERABLE,  1,
                    xlib.GLX_DRAWABLE_TYPE, xlib.GLX_WINDOW_BIT,
                    xlib.GLX_RENDER_TYPE,   xlib.GLX_RGBA_BIT,
                    xlib.GLX_NONE,
                },
                null,
            };
            for (possible_attributes) |attributes| {
                var fb_config_count: c_int = 0;
                const fbconfigs = xlib.glXChooseFBConfig(self.display, xlib.XDefaultScreen(self.display), attributes, &fb_config_count);
                if (fbconfigs == null or fb_config_count == 0) continue;
                fbconfig = fbconfigs[0];
            }
            if (fbconfig == null) return error.NoFbFound;
            break :visual xlib.glXGetVisualFromFBConfig(self.display, fbconfig.?) orelse return error.GlXGetVisualFromFBConfig;
        } else {
            var attribute_list = [_]c_int{
                xlib.GLX_RGBA,
                xlib.GLX_DOUBLEBUFFER,
                xlib.GLX_DEPTH_SIZE,
                24,
                xlib.GLX_STENCIL_SIZE,
                8,
                xlib.GLX_NONE,
            };
            break :visual xlib.glXChooseVisual(self.display, screen, &attribute_list) orelse return error.GlXChooseVisual;
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

    var motif_hints: MotifWmHints = .{
        .flags = 1 << 1,
        .functions = 0,
        .decorations = @intFromBool(options.decoration),
        .input_mode = 0,
        .status = 0,
    };

    const motif = xlib.XInternAtom(self.display, "_MOTIF_WM_HINTS", xlib.False);

    _ = xlib.XChangeProperty(self.display, window.handle, motif, motif, 32, xlib.PropModeReplace, @ptrCast(&motif_hints), 5);

    if (xlib.XMapWindow(self.display, window.handle) == xlib.False) return error.MapWindow;
    if (xlib.XFlush(self.display) == xlib.False) return error.Flush;

    // Create OpenGL context
    switch (options.surface_type) {
        .opengl => if (glx_arb_create_context_supported) {
            const ctx_attribs: [*]const c_int = &.{
                xlib.GLX_CONTEXT_MAJOR_VERSION_ARB, 4,
                xlib.GLX_CONTEXT_MINOR_VERSION_ARB, 6,
                xlib.GLX_CONTEXT_PROFILE_MASK_ARB,  xlib.GLX_CONTEXT_CORE_PROFILE_BIT_ARB,
                0,
            };
            const glXCreateContextAttribsARB = @as(?*const fn (
                display: *xlib.Display,
                fbconfig: xlib.GLXFBConfig,
                share_context: ?*anyopaque,
                direct: c_int, // bool
                attribs: [*]const c_int,
            ) ?*anyerror, @ptrCast(xlib.glXGetProcAddressARB("glXCreateContextAttribsARB"))) orelse return error.LoadGlXCreateContextAttribsARB;

            window.glx_context = glXCreateContextAttribsARB(self.display, fbconfig.?, null, 1, ctx_attribs);
        } else {
            window.glx_context = xlib.glXCreateContext(self.display, visual, null, @intFromBool(true)) orelse return error.CreateGlxContext;
        },
        else => {},
    }
}

fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.glx_context) |glx_context| xlib.glXDestroyContext(self.display, @ptrCast(glx_context));
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
                window.interface.position = position;
            }
            return .{ .resize = size };
        },
        xlib.ButtonPress, xlib.ButtonRelease => switch (event.xbutton.button) {
            4...7 => |scroll| if (event.type == xlib.ButtonPress) .{ .mouse_scroll = switch (scroll) {
                6 => .{ .x = 1 },
                7 => .{ .x = -1 },
                4 => .{ .y = 1 },
                5 => .{ .y = -1 },
                else => unreachable,
            } } else null,
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
        .maximize => |maximize| {
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
                            @intFromBool(maximize),
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
        .minimize => |minimize| _ = if (minimize)
            xlib.XIconifyWindow(self.display, window.handle, @intCast(screen))
        else
            xlib.XMapWindow(self.display, window.handle),
        .always_on_top => {},
        .floating => {},
    }

    _ = xlib.XFlush(self.display);
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    if (window.glx_context == null) return error.NotOpenGlSurface;
    if (xlib.glXMakeCurrent(self.display, window.handle, @ptrCast(window.glx_context)) == xlib.False) return error.GlxMakeCurrent;
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    if (window.glx_context == null) return error.NotOpenGlSurface;
    xlib.glXSwapBuffers(@ptrCast(self.display), window.handle);
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *Platform.Window, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    if (window.glx_context == null) return error.NotOpenGlSurface;
    const glXSwapIntervalEXT: *const fn (display: *xlib.Display, drawable: xlib.Drawable, interval: i32) callconv(.c) void = @ptrCast(xlib.glXGetProcAddress("glXSwapIntervalEXT") orelse return error.SwapIntervalLoad);
    glXSwapIntervalEXT(self.display, window.handle, interval);
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
