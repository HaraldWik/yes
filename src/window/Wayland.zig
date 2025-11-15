const std = @import("std");
const root = @import("../root.zig");
const wl = @import("wayland");
const egl = @cImport(@cInclude("EGL/egl.h"));

// https://nilsbrause.github.io/waylandpp_docs/egl_8cpp-example.html

display: *wl.wl_display,
registry: *wl.wl_registry,
compositor: *wl.wl_compositor,
surface: *wl.wl_surface,
window: *anyopaque,
api: GraphicsApi,

pub const GraphicsApi = union(root.GraphicsApi) {
    opengl: OpenGL,
    vulkan: Vulkan,
    none: void,

    pub const OpenGL = struct {
        display: egl.EGLDisplay,
        config: egl.EGLConfig,
        context: egl.EGLContext,
        surface: egl.EGLSurface,
    };
    pub const Vulkan = struct {};
};

pub fn open(config: root.Window.Config) !@This() {
    const display: *wl.wl_display = wl.wl_display_connect(null) orelse return error.ConnectDisplay;
    errdefer wl.wl_display_disconnect(display);

    const compositor: *wl.wl_compositor = undefined;
    errdefer wl.wl_compositor_destroy(compositor);
    const registry: *wl.wl_registry = wl.wl_display_get_registry(display) orelse return error.GetRegistry;
    _ = wl.wl_registry_add_listener(registry, &wl.wl_registry_listener{ .global = @ptrCast(&registryGlobal) }, @ptrCast(@alignCast(compositor)));
    _ = wl.wl_display_roundtrip(display);

    const surface: *wl.wl_surface = wl.wl_compositor_create_surface(compositor) orelse return error.CreateSurface;
    errdefer wl.wl_surface_destroy(surface);

    const window = switch (config.api) {
        .opengl => wl.wl_egl_window_create(surface, @intCast(config.width), @intCast(config.height)) orelse return error.CreateEglWindow,
        else => unreachable,
    };

    return .{
        .display = display,
        .registry = registry,
        .compositor = compositor,
        .surface = surface,
        .window = window,
    };

    // return .{
    //     .display = display,
    //     .compositor = compositor,
    //     .seat = seat,
    //     .surface = surface,
    //     .api = api: switch (config.api) {
    //         .opengl => {
    //             const egl_window: *wl.wl_egl_window = wl.wl_egl_window_create(surface, @intCast(config.width), @intCast(config.height)) orelse return error.EglWindowCreate;

    //             const egl_display = egl.eglGetDisplay(@ptrCast(display)) orelse return error.EglGetDisplay;

    //             var major: egl.EGLint = 0;
    //             var minor: egl.EGLint = 0;
    //             if (egl.eglInitialize(egl_display, &major, &minor) == egl.EGL_FALSE) return error.EglInitialize;

    //             // Bind desktop OpenGL (not GLES)
    //             if (egl.eglBindAPI(egl.EGL_OPENGL_API) == egl.EGL_FALSE) return error.BindAPI;

    //             // Choose an OpenGL-compatible EGL config
    //             const attribs = [_]egl.EGLint{
    //                 egl.EGL_SURFACE_TYPE,    egl.EGL_WINDOW_BIT,
    //                 egl.EGL_RED_SIZE,        8,
    //                 egl.EGL_GREEN_SIZE,      8,
    //                 egl.EGL_BLUE_SIZE,       8,
    //                 egl.EGL_ALPHA_SIZE,      8,
    //                 egl.EGL_RENDERABLE_TYPE, egl.EGL_OPENGL_BIT,
    //                 egl.EGL_NONE,
    //             };

    //             var egl_config: egl.EGLConfig = null;
    //             var egl_config_count: egl.EGLint = 0;
    //             if (egl.eglChooseConfig(egl_display, &attribs[0], &egl_config, 1, &egl_config_count) == egl.EGL_FALSE or egl_config_count == 0) return error.EglChooseConfig;

    //             // Request OpenGL 4.6 core context
    //             const context_attribs = [_]egl.EGLint{
    //                 egl.EGL_CONTEXT_MAJOR_VERSION,       4,
    //                 egl.EGL_CONTEXT_MINOR_VERSION,       6,
    //                 egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
    //                 egl.EGL_NONE,
    //             };

    //             const egl_context = egl.eglCreateContext(egl_display, egl_config, egl.EGL_NO_CONTEXT, &context_attribs) orelse return error.EglCreateContext;
    //             const egl_surface = egl.eglCreateWindowSurface(egl_display, egl_config, @intFromPtr(egl_window), null) orelse return error.EglCreateWindowSurface;
    //             if (egl.eglMakeCurrent(egl_display, egl_surface, egl_surface, egl_context) == egl.EGL_FALSE) return error.MakeCurrent;

    //             break :api .{ .opengl = .{
    //                 .window = egl_window,
    //                 .display = egl_display,
    //                 .context = egl_context,
    //                 .surface = egl_surface,
    //             } };
    //         },
    //         .vulkan => .{ .vulkan = .{} },
    //         .none => .{ .none = undefined },
    //     },
    // };
}

pub fn close(self: @This()) void {
    wl.wl_egl_window_destroy(self.egl_window);
    wl.wl_surface_destroy(self.surface);
    wl.wl_compositor_destroy(self.compositor);
    wl.wl_registry_destroy(self.registry);
    wl.wl_display_disconnect(self.display);
}

pub fn poll(self: @This()) ?root.Event {
    _ = self;
    return .{ .key_down = .a };
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

fn registryGlobal(compositor: *wl.wl_compositor, registry: *wl.wl_registry, name: u32, interface: [*:0]const u8, version: u32) callconv(.c) void {
    if (std.mem.eql(u8, interface, wl.wl_compositor_interface.name))
        compositor.* = wl.wl_registry_bind(registry, name, &wl.wl_compositor_interface, version);
}
