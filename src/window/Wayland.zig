const std = @import("std");
const root = @import("../root.zig");
pub const wl = @import("wayland");
pub const xdg = @import("xdg");
pub const egl = @import("egl");
// https://nilsbrause.github.io/waylandpp_docs/egl_8cpp-example.html

display: *wl.wl_display,
compositor: *wl.wl_compositor,
xdg_wm_base: *xdg.xdg_wm_base,
seat: *wl.wl_seat,
surface: *wl.wl_surface,
xdg_surface: *xdg.xdg_surface,
xdg_toplevel: *xdg.xdg_toplevel,
api: GraphicsApi,

pub const GraphicsApi = union(root.GraphicsApi) {
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

pub fn open(config: root.Window.Config) !@This() {
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

    //  wl.wl_seat_get_keyboard(arg_wl_seat_1: ?*struct_wl_seat)

    const xdg_wm_base_listener = xdg.xdg_wm_base_listener{
        .ping = xdgWmBasePing,
    };
    _ = xdg.xdg_wm_base_add_listener(xdg_wm_base, &xdg_wm_base_listener, null);

    const surface: *wl.wl_surface = wl.wl_compositor_create_surface(compositor) orelse return error.CreateSurface;
    const xdg_surface: *xdg.xdg_surface = xdg.xdg_wm_base_get_xdg_surface(xdg_wm_base, @ptrCast(surface)) orelse return error.XdgWmBaseGetXdgSurface;

    var configure: Configure = .{};
    _ = xdg.xdg_surface_add_listener(xdg_surface, &xdg.xdg_surface_listener{ .configure = @ptrCast(&Configure.callback) }, &configure);

    const xdg_toplevel: *xdg.xdg_toplevel = xdg.xdg_surface_get_toplevel(xdg_surface) orelse return error.XdgSurfaceGetToplevel;
    const nothing: *anyopaque = undefined;
    if (xdg.xdg_toplevel_add_listener(xdg_toplevel, Toplevel.listener, nothing) != 0) return error.XdgToplevelAddListener;
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
        .opengl => |api| {
            _ = egl.eglMakeCurrent(api.display, egl.EGL_NO_SURFACE, egl.EGL_NO_SURFACE, egl.EGL_NO_CONTEXT);
            _ = egl.eglDestroySurface(api.display, api.surface);
            wl.wl_egl_window_destroy(api.window);
            _ = egl.eglDestroyContext(api.display, api.context);
            _ = egl.eglTerminate(api.display);
        },
        .vulkan => {},
        .none => {},
    }

    xdg.xdg_toplevel_destroy(self.xdg_toplevel);
    xdg.xdg_surface_destroy(self.xdg_surface);
    wl.wl_surface_destroy(self.surface);
    wl.wl_display_disconnect(self.display);
}

pub fn poll(self: @This()) ?root.Event {
    // Dispatch any already-queued events first
    while (wl.wl_display_prepare_read(self.display) != 0) {
        _ = wl.wl_display_dispatch_pending(self.display);
    }

    _ = wl.wl_display_flush(self.display);

    // Use poll() with timeout=0 for non-blocking check
    const pfd: std.posix.pollfd = .{
        .fd = wl.wl_display_get_fd(self.display),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };

    var fds = [_]std.posix.pollfd{pfd};
    const ret = std.posix.poll(&fds, 0) catch 0;

    if (ret > 0) {
        _ = wl.wl_display_read_events(self.display);
        _ = wl.wl_display_dispatch_pending(self.display);
    } else {
        wl.wl_display_cancel_read(self.display);
    }

    if (!running) return .close;
    return null;
}

pub fn getSize(self: @This()) root.Window.Size {
    _ = self;
    return .{ .width = 0, .height = 0 };
}

pub const Toplevel = struct {
    pub const listener: *const xdg.xdg_toplevel_listener = &.{
        .configure = configure,
        .close = close_,
        .configure_bounds = configureBounds,
        .wm_capabilities = capabilities,
    };

    pub fn configure(data: ?*anyopaque, toplevel: ?*xdg.xdg_toplevel, width: i32, height: i32, states: [*c]xdg.wl_array) callconv(.c) void {
        _ = data;
        _ = toplevel;
        std.debug.print("{d}x{d}\n", .{ width, height });
        _ = states;
    }

    pub fn close_(data: ?*anyopaque, toplevel: ?*xdg.xdg_toplevel) callconv(.c) void {
        _ = data;
        _ = toplevel;
        running = false;
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

var running: bool = true; // TODO: remove

fn xdgWmBasePing(data: ?*anyopaque, xdg_wm_base: ?*xdg.xdg_wm_base, serial: u32) callconv(.c) void {
    _ = data;
    xdg.xdg_wm_base_pong(xdg_wm_base, serial);
}
