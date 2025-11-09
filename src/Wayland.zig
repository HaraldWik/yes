const std = @import("std");
const root = @import("root.zig");
pub const wl = @cImport({ // TODO: Remove C import
    @cInclude("wayland-client.h");
    @cInclude("wayland-egl.h");
});
pub const xdg = @import("xdg");
pub const egl = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
});
// https://nilsbrause.github.io/waylandpp_docs/egl_8cpp-example.html

display: *wl.wl_display,
compositor: *wl.wl_compositor,
shell: *wl.wl_shell,
seat: *wl.wl_seat,
base: *xdg.xdg_wm_base,
surface: *wl.wl_surface,
shell_surface_t: *wl.wl_shell_surface,
api: GraphicsApi,

pub const GraphicsApi = union(root.GraphicsApi) {
    opengl: OpenGL,
    vulkan: Vulkan,
    none: void,

    pub const OpenGL = struct {
        window: *wl.wl_egl_window,
        display: *anyopaque,
        context: *anyopaque,
        surface: *anyopaque,
    };
    pub const Vulkan = struct {};
};

const Registry = struct {
    compositor: ?*wl.wl_compositor,
    shell: ?*wl.wl_shell,
    seat: ?*wl.wl_seat,
    base: ?*xdg.xdg_wm_base,
    // shm: ?*wl.wl_shm,

    fn register(self: *@This(), registry: *wl.wl_registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void {
        const interfaces = [_]wl.wl_interface{
            wl.wl_compositor_interface,
            wl.wl_shell_interface,
            wl.wl_seat_interface,
            @bitCast(xdg.xdg_wm_base_interface),
        };

        inline for (@typeInfo(@This()).@"struct".fields, interfaces) |field, target| {
            if (std.mem.eql(u8, std.mem.span(interface), std.mem.span(target.name)))
                @field(self.*, field.name) = @ptrCast(wl.wl_registry_bind(registry, name, &target, version));
        }
    }
};

pub fn open(config: root.Window.Config) !@This() {
    const display: *wl.wl_display = wl.wl_display_connect(null) orelse return error.ConnectDisplay;
    const compositor: *wl.wl_compositor, const shell: *wl.wl_shell, const seat: *wl.wl_seat, const base: ?*xdg.xdg_wm_base = registry: {
        var data: Registry = undefined;
        const registry: *wl.wl_registry = wl.wl_display_get_registry(display) orelse return error.GetDisplayRegistry;
        if (wl.wl_registry_add_listener(registry, &wl.wl_registry_listener{ .global = @ptrCast(&Registry.register) }, @ptrCast(&data)) != 0) return error.RegistryAddListener;
        if (wl.wl_display_roundtrip(display) < 0) return error.DisplayRoundtrip;
        break :registry .{ data.compositor.?, data.shell.?, data.seat.?, data.base };
    };
    //  wl.wl_seat_get_keyboard(arg_wl_seat_1: ?*struct_wl_seat)

    const surface: *wl.wl_surface = wl.wl_compositor_create_surface(compositor) orelse return error.CreateSurface;

    var serial: u32 = undefined; // TODO: make this trash work
    const ping = struct {
        fn ping(dest_serial_ptr: ?*anyopaque, _: ?*anyopaque, src_serial: u32) callconv(.c) void {
            const dest_serial: *u32 = @ptrCast(@alignCast(dest_serial_ptr));
            std.debug.print("Src serial: {d}", .{src_serial});
            dest_serial.* = src_serial;
        }
    }.ping;

    if (base != null) {
        if (xdg.xdg_wm_base_add_listener(base, &xdg.xdg_wm_base_listener{ .ping = ping }, &serial) != 0) return error.XdgBaseAddListener;
        xdg.xdg_wm_base_pong(base, serial);
    } else {
        const shell_surface: *wl.wl_shell_surface = wl.wl_shell_get_shell_surface(shell, surface) orelse return error.ShellGetShellSurface;
        if (wl.wl_shell_surface_add_listener(shell_surface, &wl.wl_shell_surface_listener{ .ping = ping }, &serial) != 0) return error.ShellSurfaceAddListener;
        wl.wl_shell_surface_pong(shell_surface, serial);
        wl.wl_shell_surface_set_title(shell_surface, config.title.ptr);
        wl.wl_shell_surface_set_toplevel(shell_surface);
    }

    std.debug.print("Serial: {d}\n", .{serial});

    return .{
        .display = display,
        .surface = surface,
        .compositor = compositor,
        .shell = shell,
        .seat = seat,
        .base = base,
        .api = api: switch (config.api) {
            .opengl => {
                const egl_window: *wl.wl_egl_window = wl.wl_egl_window_create(surface, @intCast(config.width), @intCast(config.height)) orelse return error.EglWindowCreate;

                const egl_display = egl.eglGetDisplay(@ptrCast(display)) orelse return error.EglGetDisplay;

                var major: egl.EGLint = 0;
                var minor: egl.EGLint = 0;
                if (egl.eglInitialize(egl_display, &major, &minor) == egl.EGL_FALSE) return error.EglInitialize;

                // Bind desktop OpenGL (not GLES)
                if (egl.eglBindAPI(egl.EGL_OPENGL_API) == egl.EGL_FALSE) return error.BindAPI;

                // Choose an OpenGL-compatible EGL config
                const attribs = [_]egl.EGLint{
                    egl.EGL_SURFACE_TYPE,    egl.EGL_WINDOW_BIT,
                    egl.EGL_RED_SIZE,        8,
                    egl.EGL_GREEN_SIZE,      8,
                    egl.EGL_BLUE_SIZE,       8,
                    egl.EGL_ALPHA_SIZE,      8,
                    egl.EGL_RENDERABLE_TYPE, egl.EGL_OPENGL_BIT,
                    egl.EGL_NONE,
                };

                var egl_config: egl.EGLConfig = null;
                var egl_config_count: egl.EGLint = 0;
                if (egl.eglChooseConfig(egl_display, &attribs[0], &egl_config, 1, &egl_config_count) == egl.EGL_FALSE or egl_config_count == 0) return error.EglChooseConfig;

                // Request OpenGL 4.6 core context
                const context_attribs = [_]egl.EGLint{
                    egl.EGL_CONTEXT_MAJOR_VERSION,       4,
                    egl.EGL_CONTEXT_MINOR_VERSION,       6,
                    egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                    egl.EGL_NONE,
                };

                const egl_context = egl.eglCreateContext(egl_display, egl_config, egl.EGL_NO_CONTEXT, &context_attribs) orelse return error.EglCreateContext;
                const egl_surface = egl.eglCreateWindowSurface(egl_display, egl_config, @intFromPtr(egl_window), null) orelse return error.EglCreateWindowSurface;
                if (egl.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) == egl.EGL_FALSE) return error.MakeCurrent;

                break :api .{ .opengl = .{
                    .window = egl_window,
                    .display = egl_display,
                    .context = egl_context,
                    .surface = egl_surface,
                } };
            },
            .vulkan => .{ .vulkan = .{} },
            .none => .{ .none = undefined },
        },
    };
}

pub fn close(self: @This()) void {
    switch (self.api) {
        .opengl => |api| {
            _ = egl.eglDestroySurface(api.display, api.surface);
            _ = egl.eglDestroyContext(api.display, api.context);
            _ = egl.eglTerminate(api.display);
            wl.wl_egl_window_destroy(api.window);
        },
        .vulkan => {},
        .none => {},
    }
    wl.wl_surface_destroy(self.surface);
    xdg.xdg_wm_base_destroy(self.base);
    wl.wl_seat_destroy(self.seat);
    wl.wl_shell_destroy(self.shell);
    wl.wl_compositor_destroy(self.compositor);
    wl.wl_display_disconnect(self.display);
}

pub fn next(self: @This()) ?root.Event {
    _ = self;
    return .none;
}

pub fn getSize(self: @This()) [2]usize {
    _ = self;
    return .{ 0, 0 };
}

pub fn isKeyDown(self: @This(), key: root.Key) bool {
    _ = self;
    _ = key;
    return false;
}
