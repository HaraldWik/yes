const std = @import("std");
const root = @import("../root.zig");
const Window = @import("Window.zig");
const Event = @import("../event.zig").Union;
pub const wl = @import("wayland");
pub const xdg = @import("xdg");
pub const xkb = @import("xkb");
pub const egl = @import("egl");

display: *wl.wl_display,
compositor: *wl.wl_compositor,
xdg_wm_base: *xdg.xdg_wm_base,
seat: *wl.wl_seat,
surface: *wl.wl_surface,
xdg_surface: *xdg.xdg_surface,
xdg_toplevel: *xdg.xdg_toplevel,
api: GraphicsApi,

var event_buffer: [128]Event = undefined;
var events: std.Deque(Event) = .empty;

pub const GraphicsApi = union(Window.GraphicsApi.Tag) {
    opengl: OpenGL,
    vulkan: Vulkan,
    none: void,

    pub const OpenGL = struct {
        display: @typeInfo(egl.EGLDisplay).optional.child,
        config: @typeInfo(egl.EGLConfig).optional.child,
        context: @typeInfo(egl.EGLContext).optional.child,
        window: *wl.wl_egl_window,
        surface: @typeInfo(egl.EGLSurface).optional.child,
    };
    pub const Vulkan = struct {};
};

pub fn open(config: Window.Config) !@This() {
    events = .initBuffer(&event_buffer);

    const display: *wl.wl_display = wl.wl_display_connect(null) orelse return error.ConnectDisplay;
    const compositor: *wl.wl_compositor, const xdg_wm_base: *xdg.xdg_wm_base, const seat: *wl.wl_seat = registry: {
        var data: Registry = undefined;
        const registry: *wl.wl_registry = wl.wl_display_get_registry(display) orelse return error.GetDisplayRegistry;
        if (wl.wl_registry_add_listener(registry, &wl.wl_registry_listener{ .global = @ptrCast(&Registry.callback) }, @ptrCast(&data)) != 0) return error.RegistryAddListener;
        if (wl.wl_display_roundtrip(display) < 0) return error.DisplayRoundtrip;
        break :registry .{
            data.compositor orelse return error.Compositor,
            data.xdg_wm_base orelse return error.XdgWmBase,
            data.seat orelse return error.Seat,
        };
    };

    var keyboard: Keyboard = undefined;
    try keyboard.addListener(seat);

    const xdg_wm_base_listener = xdg.xdg_wm_base_listener{
        .ping = xdgWmBasePing,
    };
    if (xdg.xdg_wm_base_add_listener(xdg_wm_base, &xdg_wm_base_listener, null) != 0) return error.AddXdgBaseListener;

    const surface: *wl.wl_surface = wl.wl_compositor_create_surface(compositor) orelse return error.CreateSurface;
    const xdg_surface: *xdg.xdg_surface = xdg.xdg_wm_base_get_xdg_surface(xdg_wm_base, @ptrCast(surface)) orelse return error.XdgBaseGetXdgSurface;

    var configure: Configure = .{};
    _ = xdg.xdg_surface_add_listener(xdg_surface, &xdg.xdg_surface_listener{ .configure = @ptrCast(&Configure.callback) }, &configure);

    const xdg_toplevel: *xdg.xdg_toplevel = xdg.xdg_surface_get_toplevel(xdg_surface) orelse return error.XdgSurfaceGetToplevel;
    if (xdg.xdg_toplevel_add_listener(xdg_toplevel, Toplevel.listener, null) != 0) return error.XdgToplevelAddListener;
    xdg.xdg_toplevel_set_title(xdg_toplevel, config.title.ptr);

    wl.wl_surface_commit(surface);
    while (!configure.done) _ = wl.wl_display_dispatch(display);
    wl.wl_surface_commit(surface);

    const api: GraphicsApi = api: switch (config.api) {
        .opengl => {
            const egl_display = egl.eglGetDisplay(display) orelse return error.EglGetDisplay;

            var major: egl.EGLint = undefined;
            var minor: egl.EGLint = undefined;
            if (egl.eglInitialize(egl_display, &major, &minor) != egl.EGL_TRUE) return error.InitializeEgl;
            if (egl.eglBindAPI(egl.EGL_OPENGL_API) != egl.EGL_TRUE) return error.BindAPI; // EGL_OPENGL_ES_API

            const egl_config_attribs: []const egl.EGLint = &.{
                egl.EGL_SURFACE_TYPE, egl.EGL_WINDOW_BIT,
                egl.EGL_RED_SIZE,     8,
                egl.EGL_GREEN_SIZE,   8,
                egl.EGL_BLUE_SIZE,    8,
                egl.EGL_ALPHA_SIZE,   8,
                egl.EGL_RENDERABLE_TYPE, egl.EGL_OPENGL_BIT, // egl.EGL_OPENGL_ES2_BIT,
                egl.EGL_NONE,
            };

            var egl_config: egl.EGLConfig = undefined;
            var n: egl.EGLint = undefined;
            if (egl.eglChooseConfig(egl_display, egl_config_attribs.ptr, &egl_config, 1, &n) != egl.EGL_TRUE) return error.EglChooseConfig;

            const egl_context_attribs: []const egl.EGLint = &.{
                egl.EGL_CONTEXT_MAJOR_VERSION, 4,
                egl.EGL_CONTEXT_MINOR_VERSION,       5, // Need 4.5+ for DSA
                egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                egl.EGL_NONE,
            };

            const egl_context = egl.eglCreateContext(egl_display, egl_config, egl.EGL_NO_CONTEXT, egl_context_attribs.ptr) orelse return error.CreateContext;

            const window: *wl.wl_egl_window = wl.wl_egl_window_create(surface, @intCast(config.size.width), @intCast(config.size.height)) orelse return error.CreateWindow;
            const egl_surface = egl.eglCreateWindowSurface(egl_display, egl_config, @intFromPtr(window), null) orelse return error.EglCreateWindowSurface;

            if (egl.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) != egl.EGL_TRUE) return error.EglMakeCurrent;

            break :api .{ .opengl = .{
                .display = egl_display,
                .config = egl_config.?,
                .context = egl_context,
                .window = window,
                .surface = egl_surface,
            } };
        },
        else => undefined,
    };

    wl.wl_surface_commit(surface);
    _ = wl.wl_display_roundtrip(display); // Ensure compositor processes commit

    return .{
        .display = display,
        .compositor = compositor,
        .xdg_wm_base = xdg_wm_base,
        .seat = seat,
        .surface = surface,
        .xdg_surface = xdg_surface,
        .xdg_toplevel = xdg_toplevel,
        .api = api,
    };
}

pub fn close(self: @This()) void {
    switch (self.api) {
        .opengl => |opengl| {
            _ = egl.eglMakeCurrent(opengl.display, egl.EGL_NO_SURFACE, egl.EGL_NO_SURFACE, egl.EGL_NO_CONTEXT);
            _ = egl.eglDestroySurface(opengl.display, opengl.surface);
            wl.wl_egl_window_destroy(opengl.window);
            _ = egl.eglDestroyContext(opengl.display, opengl.context);
            _ = egl.eglTerminate(opengl.display);
        },
        .vulkan => {},
        .none => {},
    }

    xdg.xdg_toplevel_destroy(self.xdg_toplevel);
    xdg.xdg_surface_destroy(self.xdg_surface);
    wl.wl_surface_destroy(self.surface);
    wl.wl_display_disconnect(self.display);
}

pub fn poll(self: @This()) ?Event {
    while (wl.wl_display_prepare_read(self.display) != 0) _ = wl.wl_display_dispatch_pending(self.display);
    _ = wl.wl_display_flush(self.display);

    var pfd: std.posix.pollfd = .{
        .fd = wl.wl_display_get_fd(self.display),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };

    if (std.posix.poll(@ptrCast(&pfd), 0) catch 0 > 0) {
        _ = wl.wl_display_read_events(self.display);
        _ = wl.wl_display_dispatch_pending(self.display);
    } else wl.wl_display_cancel_read(self.display);

    const event = events.popFront() orelse return null;
    switch (event) {
        .resize => |size| switch (self.api) {
            .opengl => |gl| wl.wl_egl_window_resize(gl.window, @intCast(size.width), @intCast(size.height), 0, 0),
            else => {},
        },
        else => {},
    }
    return event;
}

pub fn getSize(self: @This()) Window.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}

const Registry = struct {
    compositor: ?*wl.wl_compositor,
    xdg_wm_base: ?*xdg.xdg_wm_base,
    seat: ?*wl.wl_seat,

    fn callback(self: *@This(), registry: *wl.wl_registry, name: u32, interfacez: [*:0]const u8, version: u32) callconv(.c) void {
        const interface = std.mem.span(interfacez);

        if (std.mem.eql(u8, interface, std.mem.span(wl.wl_compositor_interface.name))) {
            self.compositor = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_compositor_interface, version));
        } else if (std.mem.eql(u8, interface, std.mem.span(xdg.xdg_wm_base_interface.name))) {
            self.xdg_wm_base = @ptrCast(wl.wl_registry_bind(registry, name, @ptrCast(&xdg.xdg_wm_base_interface), version));
        } else if (std.mem.eql(u8, interface, std.mem.span(wl.wl_seat_interface.name))) {
            self.seat = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_seat_interface, version));
        }
    }
};

const Configure = struct {
    done: bool = false,
    serial: u32 = undefined,
    fn callback(self: *@This(), xdg_surface: *xdg.xdg_surface, serial: u32) callconv(.c) void {
        xdg.xdg_surface_ack_configure(xdg_surface, serial);
        self.done = true;
    }
};

pub const Toplevel = struct {
    pub const listener: *const xdg.xdg_toplevel_listener = &.{
        .configure = configure,
        .close = close_,
        .configure_bounds = configureBounds,
        .wm_capabilities = capabilities,
    };

    pub fn configure(_: ?*anyopaque, _: ?*xdg.xdg_toplevel, width: i32, height: i32, _: [*c]xdg.wl_array) callconv(.c) void {
        events.pushBackAssumeCapacity(.{ .resize = .{ .width = @intCast(width), .height = @intCast(height) } });
    }

    pub fn close_(_: ?*anyopaque, _: ?*xdg.xdg_toplevel) callconv(.c) void {
        events.pushFrontAssumeCapacity(.close);
    }

    pub fn configureBounds(data: ?*anyopaque, toplevel: ?*xdg.xdg_toplevel, width: i32, height: i32) callconv(.c) void {
        _ = data;
        _ = toplevel;
        _ = width;
        _ = height;
    }

    pub fn capabilities(data: ?*anyopaque, toplevel: ?*xdg.xdg_toplevel, states: [*c]xdg.struct_wl_array) callconv(.c) void {
        _ = data;
        _ = toplevel;
        _ = states;
    }
};

fn xdgWmBasePing(data: ?*anyopaque, xdg_wm_base: ?*xdg.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    xdg.xdg_wm_base_pong(xdg_wm_base, serial);
}
pub const Keyboard = struct {
    handle: *wl.wl_keyboard = undefined,
    xkb_ctx: *xkb.xkb_context = undefined,
    xkb_keymap: ?*xkb.xkb_keymap = null,
    xkb_state: ?*xkb.xkb_state = null,

    pub const listener: *const wl.wl_keyboard_listener = &.{
        .keymap = @ptrCast(&keymap),
        .enter = @ptrCast(&enter),
        .leave = @ptrCast(&leave),
        .key = @ptrCast(&key),
        .modifiers = @ptrCast(&modifiers),
        .repeat_info = @ptrCast(&repeatInfo),
    };

    pub fn addListener(self: *@This(), seat: *wl.wl_seat) !void {
        self.xkb_ctx = xkb.xkb_context_new(0) orelse return error.CreateXkbContext;
        self.handle = wl.wl_seat_get_keyboard(seat) orelse return error.GetKeyboard;
        if (wl.wl_keyboard_add_listener(self.handle, listener, self) != 0) return error.AddKeyboardListener;
    }

    fn keymap(self: *@This(), _: ?*wl.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {

        // xkbcommon expects the FD to be mmap-able or read fully, do not null-terminate
        const buffer = std.heap.page_allocator.alloc(u8, @intCast(size)) catch return;
        const bytes_read = std.posix.read(fd, buffer) catch return;
        _ = std.posix.close(fd);
        if (bytes_read != @as(usize, @intCast(size))) {
            std.heap.page_allocator.free(buffer);
            return;
        }

        // Create keymap from buffer
        self.xkb_keymap = xkb.xkb_keymap_new_from_buffer(
            self.xkb_ctx,
            buffer.ptr,
            @intCast(size),
            format,
            0, // flags
        );
        std.heap.page_allocator.free(buffer);

        if (self.xkb_keymap == null) return;

        self.xkb_state = xkb.xkb_state_new(self.xkb_keymap.?);
    }

    fn enter(_: *@This(), _: ?*wl.wl_keyboard, _: u32, _: ?*wl.wl_surface, _: [*c]wl.wl_array) callconv(.c) void {
        std.debug.print("Keyboard focus enter\n", .{});
    }

    fn leave(_: *@This(), _: ?*wl.wl_keyboard, _: u32, _: ?*wl.wl_surface) callconv(.c) void {
        std.debug.print("Keyboard focus leave\n", .{});
    }

    fn key(self: *@This(), _: ?*wl.wl_keyboard, _: u32, _: u32, keycode: u32, state: u32) callconv(.c) void {
        if (self.xkb_state == null) return;

        const keysym: xkb.xkb_keysym_t = xkb.xkb_state_key_get_one_sym(self.xkb_state.?, keycode + 8);

        if (state == wl.WL_KEYBOARD_KEY_STATE_PRESSED) {
            std.debug.print("Key pressed: {d}\n", .{keysym});
        } else {
            std.debug.print("Key released: {d}\n", .{keysym});
        }
    }

    fn modifiers(_: *@This(), _: ?*wl.wl_keyboard, _: u32, _: u32, _: u32, _: u32, _: u32) callconv(.c) void {}

    fn repeatInfo(_: *@This(), _: ?*wl.wl_keyboard, _: i32, _: i32) callconv(.c) void {}
};
