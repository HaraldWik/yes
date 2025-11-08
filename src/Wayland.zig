const std = @import("std");
const root = @import("root.zig");
const wl = @cImport({ // TODO: Remove C import
    @cInclude("wayland-client.h");
    @cInclude("wayland-egl.h");
});
const egl = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("GLES2/gl2.h");
});

display: *wl.wl_display,
compositor: *wl.wl_compositor,
surface: *wl.wl_surface,
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

    fn init(self: *@This(), registry: *wl.wl_registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void {
        _ = version;

        if (std.mem.eql(u8, std.mem.span(interface), std.mem.span(wl.wl_compositor_interface.name)))
            self.compositor = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_compositor_interface, 4));

        // std.debug.print("{d}\n", .{name});
    }
    fn deinit(self: *@This(), registry: *wl.wl_registry, name: u32) callconv(.c) void {
        _ = self;
        _ = registry;
        _ = name;
    }
};

pub fn open(config: root.Window.Config) !@This() {
    const display: *wl.wl_display = wl.wl_display_connect(null) orelse return error.ConnectDisplay;

    const compositor: *wl.wl_compositor = try registry: {
        var data: Registry = undefined;
        const registry: *wl.wl_registry = wl.wl_display_get_registry(display) orelse return error.GetDisplayRegistry;
        _ = wl.wl_registry_add_listener(registry, &wl.wl_registry_listener{ .global = @ptrCast(&Registry.init), .global_remove = @ptrCast(&Registry.deinit) }, @ptrCast(&data));
        _ = wl.wl_display_roundtrip(display);
        if (data.compositor == null) return error.RegisterCompositor;
        break :registry data.compositor orelse error.RegisterCompositor;
    };

    const surface: *wl.wl_surface = wl.wl_compositor_create_surface(compositor) orelse return error.CreateSurface;

    return .{
        .display = display,
        .surface = surface,
        .compositor = compositor,
        .api = api: switch (config.api) {
            .opengl => {
                const egl_window: *wl.wl_egl_window = wl.wl_egl_window_create(surface, @intCast(config.width), @intCast(config.height)) orelse return error.EglWindowCreate;
                const egl_display = egl.eglGetDisplay(@ptrCast(display)) orelse return error.EglGetDisplay;

                var major: egl.EGLint = 0;
                var minor: egl.EGLint = 0;
                if (egl.eglInitialize(egl_display, &major, &minor) == egl.EGL_FALSE)
                    return error.EglInitialize;

                if (egl.eglBindAPI(egl.EGL_OPENGL_API) == egl.EGL_FALSE) return error.BindAPI;

                const attribs = [_]egl.EGLint{
                    egl.EGL_RED_SIZE, 8,
                    egl.EGL_NONE,
                };
                var egl_config: egl.EGLConfig = null;
                var num_configs: egl.EGLint = 0;
                if (egl.eglChooseConfig(egl_display, &attribs[0], &egl_config, 1, &num_configs) == egl.EGL_FALSE) return error.EglChooseConfig;

                const egl_context = egl.eglCreateContext(egl_display, egl_config, egl.EGL_NO_CONTEXT, null) orelse return error.EglCreateContext;
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
