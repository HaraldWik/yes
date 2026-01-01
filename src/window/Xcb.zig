const std = @import("std");
const Window = @import("Window.zig");
const xcb = @import("xcb");
const egl = @import("egl");

connection: *xcb.connection_t,
window: xcb.window_t,
atom_wm_delete_window: xcb.atom_t,
api: GraphicsApi,

pub const GraphicsApi = union(Window.GraphicsApi.Tag) {
    opengl: struct {
        display: @typeInfo(egl.EGLDisplay).optional.child,
        config: @typeInfo(egl.EGLConfig).optional.child,
        context: @typeInfo(egl.EGLContext).optional.child,
        surface: @typeInfo(egl.EGLSurface).optional.child,
    },
    vulkan,
    none,
};

pub fn open(config: Window.Config) !@This() {
    var scr: c_int = undefined;
    const connection = xcb.connect(null, &scr) orelse return error.Connection;
    if (xcb.connection_has_error(connection) != 0) return error.Connection;

    const setup = xcb.get_setup(connection);
    var iter = xcb.setup_roots_iterator(setup);
    while (scr > 0) : (scr -= 1) xcb.screen_next(&iter);

    const screen = iter.data;

    const window = xcb.generate_id(connection);
    const value_mask = xcb.CW.BACK_PIXEL | xcb.CW.EVENT_MASK;
    const value_list = [_]u32{
        screen.black_pixel,
        xcb.EVENT_MASK.KEY_RELEASE |
            xcb.EVENT_MASK.KEY_PRESS |
            xcb.EVENT_MASK.EXPOSURE |
            xcb.EVENT_MASK.STRUCTURE_NOTIFY |
            xcb.EVENT_MASK.POINTER_MOTION |
            xcb.EVENT_MASK.BUTTON_PRESS |
            xcb.EVENT_MASK.BUTTON_RELEASE,
    };

    _ = xcb.create_window(
        connection,
        xcb.COPY_FROM_PARENT,
        window,
        screen.root,
        0,
        0,
        @intCast(config.size.width),
        @intCast(config.size.height),
        0,
        @intFromEnum(xcb.window_class_t.INPUT_OUTPUT),
        screen.root_visual,
        value_mask,
        &value_list,
    );

    const api: GraphicsApi = api: switch (config.api) {
        .opengl => |opengl| {
            const exts = egl.eglQueryString(egl.EGL_NO_DISPLAY, egl.EGL_EXTENSIONS);
            if (!std.mem.containsAtLeast(u8, std.mem.span(exts), 1, "EGL_EXT_platform_xcb")) {
                return error.NoEglPlatformXcb;
            }
            std.debug.print("{s}\n", .{exts});

            const EGL_PLATFORM_XCB_EXT = 0x3138;
            const eglGetPlatformDisplayEXT: *const fn (platform: egl.EGLenum, native_display: *anyopaque, attrib_list: ?*egl.EGLint) callconv(.c) egl.EGLDisplay =
                @ptrCast(egl.eglGetProcAddress("eglGetPlatformDisplayEXT") orelse return error.NoEglPlatformXcb);

            const display = eglGetPlatformDisplayEXT(EGL_PLATFORM_XCB_EXT, @ptrCast(connection), null) orelse return error.EglNoDisplay;

            var major: egl.EGLint = undefined;
            var minor: egl.EGLint = undefined;
            if (egl.eglInitialize(display, &major, &minor) != egl.EGL_TRUE) return error.EglInitializeEgl;
            if (egl.eglBindAPI(egl.EGL_OPENGL_API) != egl.EGL_TRUE) return error.BindAPI; // EGL_OPENGL_ES_API

            const config_attribs: []const egl.EGLint = &.{
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
            if (egl.eglChooseConfig(display, config_attribs.ptr, &egl_config, 1, &n) != egl.EGL_TRUE) return error.EglChooseConfig;

            const context_attribs: []const egl.EGLint = &.{
                egl.EGL_CONTEXT_MAJOR_VERSION,       @intCast(opengl.version.major),
                egl.EGL_CONTEXT_MINOR_VERSION,       @intCast(opengl.version.minor),
                egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                egl.EGL_NONE,
            };

            const context = egl.eglCreateContext(display, egl_config, egl.EGL_NO_CONTEXT, context_attribs.ptr) orelse return error.EglCreateContext;
            const surface = egl.eglCreateWindowSurface(display, egl_config, @intCast(window), null) orelse return error.EglCreateSurface;

            break :api .{ .opengl = .{
                .display = display,
                .config = egl_config.?,
                .context = context,
                .surface = surface,
            } };
        },
        .vulkan => .vulkan,
        .none => .none,
    };

    // Send notification when window is destroyed.
    const atom_wm_protocols = try get_atom(connection, "WM_PROTOCOLS");
    const atom_wm_delete_window = try get_atom(connection, "WM_DELETE_WINDOW");
    _ = xcb.change_property(connection, .REPLACE, window, atom_wm_protocols, .ATOM, 32, 1, &atom_wm_delete_window);

    _ = xcb.change_property(connection, .REPLACE, window, .WM_NAME, .STRING, 8, @intCast(config.title.len), config.title.ptr);

    var wm_class_buf: [100]u8 = undefined;
    const wm_class = std.fmt.bufPrint(&wm_class_buf, "windowName\x00{s}\x00", .{config.title}) catch unreachable;
    _ = xcb.change_property(connection, .REPLACE, window, .WM_CLASS, .STRING, 8, @intCast(wm_class.len), wm_class.ptr);
    _ = xcb.map_window(connection, window);

    return .{
        .connection = connection,
        .window = window,
        .atom_wm_delete_window = atom_wm_delete_window,
        .api = api,
    };
}

pub fn close(self: @This()) void {
    _ = self;
}

pub fn poll(self: *@This(), keyboard: *Window.io.Keyboard) !?Window.io.Event {
    _ = keyboard;
    const event = xcb.poll_for_event(self.connection) orelse return null;
    defer std.c.free(event);
    switch (event.response_type.op) {
        .CLIENT_MESSAGE => blk: {
            const client_message: *xcb.client_message_event_t = @ptrCast(event);
            if (client_message.window != self.window) break :blk;

            if (client_message.type == self.atom_wm_delete_window) {
                const msg_atom: xcb.atom_t = @enumFromInt(client_message.data.data32[0]);
                if (msg_atom == self.atom_wm_delete_window) return .close;
            }
        },
        .CONFIGURE_NOTIFY => {
            const configure: *xcb.configure_notify_event_t = @ptrCast(event);
            return .{ .resize = .{ .width = @intCast(configure.width), .height = @intCast(configure.height) } };
        },
        .EXPOSE => {},
        .KEY_PRESS => {
            const key_press: *xcb.key_press_event_t = @ptrCast(event);
            if (key_press.detail == 9) return .close;
            std.debug.print("key state: {d} : detail {d}\n", .{ key_press.state, key_press.detail });
            return .{ .key = .{
                .state = .pressed,
                .code = key_press.detail,
                .sym = Window.io.Event.Key.Sym.fromXkb(key_press.detail) orelse return null,
            } };
        },
        .KEY_RELEASE => {
            // key up
        },
        .MOTION_NOTIFY => {
            // mouse movement
        },
        .BUTTON_PRESS => {
            // mouse down
        },
        .BUTTON_RELEASE => {
            // mouse up
        },
        else => |t| {
            std.log.debug("unhandled xcb message: {s}", .{@tagName(t)});
        },
    }
    return null;
}

pub fn getSize(self: @This()) Window.Size {
    _ = self;
    return .{};
}

pub fn setTitle(self: @This(), title: [:0]const u8) void {
    _ = self;
    _ = title;
}

pub fn fullscreen(self: @This(), state: bool) void {
    _ = self;
    _ = state;
}

pub fn maximize(self: @This(), state: bool) void {
    _ = self;
    _ = state;
}

pub fn minimize(self: @This()) void {
    _ = self;
}

pub fn setPosition(self: @This(), position: Window.Position(i32)) void {
    _ = self;
    _ = position;
}

fn get_atom(conn: *xcb.connection_t, name: [:0]const u8) error{OutOfMemory}!xcb.atom_t {
    const cookie = xcb.intern_atom(conn, 0, @intCast(name.len), name.ptr);
    if (xcb.intern_atom_reply(conn, cookie, null)) |r| {
        defer std.c.free(r);
        return r.atom;
    }
    return error.OutOfMemory;
}
