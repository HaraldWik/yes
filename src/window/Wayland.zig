const std = @import("std");
const Window = @import("Window.zig");
const wl = @import("wayland");
const xdg = @import("xdg");
const xkb = @import("xkb");
const egl = @import("egl");
const decor = @import("decor");

display: *wl.wl_display,
compositor: *wl.wl_compositor,
xdg_wm_base: *xdg.xdg_wm_base,
seat: *wl.wl_seat,
keyboard: ?Keyboard = null,
mouse: ?Mouse = null,
surface: *wl.wl_surface,
xdg_surface: *xdg.xdg_surface,
xdg_toplevel: *xdg.xdg_toplevel,
decoration: ?Decoration,
api: GraphicsApi,

// Data
size: Window.Size = undefined,

// TODO: make this not be global state
var event_buffer: [128]Window.io.Event = undefined;
var events: std.Deque(Window.io.Event) = .empty;

pub const GraphicsApi = union(Window.GraphicsApi.Tag) {
    opengl: OpenGL,
    vulkan: Vulkan,
    none: None,

    pub const OpenGL = struct {
        display: @typeInfo(egl.EGLDisplay).optional.child,
        config: @typeInfo(egl.EGLConfig).optional.child,
        context: @typeInfo(egl.EGLContext).optional.child,
        window: *wl.wl_egl_window,
        surface: @typeInfo(egl.EGLSurface).optional.child,
    };
    pub const Vulkan = struct {};
    pub const None = struct {
        shm: *wl.wl_shm,
        buffer: *wl.wl_buffer,
        pixels: []u8,
    };
};

pub fn open(config: Window.Config) !@This() {
    events = .initBuffer(&event_buffer);

    const display: *wl.wl_display = wl.wl_display_connect(null) orelse return error.ConnectDisplay;
    errdefer wl.wl_display_disconnect(display);
    const compositor: *wl.wl_compositor, const xdg_wm_base: *xdg.xdg_wm_base, const seat: *wl.wl_seat, const shm: ?*wl.wl_shm, const decoration_manager: ?*decor.zxdg_decoration_manager_v1 = registry: {
        var data: Registry = undefined;
        const registry: *wl.wl_registry = wl.wl_display_get_registry(display) orelse return error.GetDisplayRegistry;
        if (wl.wl_registry_add_listener(registry, &wl.wl_registry_listener{ .global = @ptrCast(&Registry.callback) }, @ptrCast(&data)) != 0) return error.RegistryAddListener;
        if (wl.wl_display_roundtrip(display) < 0) return error.DisplayRoundtrip;
        break :registry .{
            data.compositor orelse return error.Compositor,
            data.xdg_wm_base orelse return error.XdgWmBase,
            data.seat orelse return error.Seat,
            data.shm,
            data.decoration_manager,
        };
    };

    if (xdg.xdg_wm_base_add_listener(xdg_wm_base, &xdg.xdg_wm_base_listener{ .ping = callback.xdgBasePing }, null) != 0) return error.AddXdgBaseListener;

    const surface: *wl.wl_surface = wl.wl_compositor_create_surface(compositor) orelse return error.CreateSurface;
    const xdg_surface: *xdg.xdg_surface = xdg.xdg_wm_base_get_xdg_surface(xdg_wm_base, @ptrCast(surface)) orelse return error.XdgBaseGetXdgSurface;

    var configuration_done: bool = false;
    _ = xdg.xdg_surface_add_listener(xdg_surface, &xdg.xdg_surface_listener{ .configure = @ptrCast(&callback.configure) }, &configuration_done);

    const xdg_toplevel: *xdg.xdg_toplevel = xdg.xdg_surface_get_toplevel(xdg_surface) orelse return error.XdgSurfaceGetToplevel;
    if (xdg.xdg_toplevel_add_listener(xdg_toplevel, Toplevel.listener, null) != 0) return error.XdgToplevelAddListener;
    if (config.min_size) |size| xdg.xdg_toplevel_set_min_size(xdg_toplevel, @intCast(size.width), @intCast(size.height));
    if (config.max_size) |size| xdg.xdg_toplevel_set_max_size(xdg_toplevel, @intCast(size.width), @intCast(size.height));

    var decoration: ?Decoration = null;
    if (config.decoration and decoration_manager != null) {
        decoration = .{ .manager = decoration_manager.? };
        try decoration.?.get(xdg_toplevel);
    }

    wl.wl_surface_commit(surface);
    while (!configuration_done) _ = wl.wl_display_dispatch(display);
    wl.wl_surface_commit(surface);

    const api: GraphicsApi = api: switch (config.api) {
        .opengl => |opengl| {
            const egl_display = egl.eglGetDisplay(display) orelse return error.GetDisplay;

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
            if (egl.eglChooseConfig(egl_display, egl_config_attribs.ptr, &egl_config, 1, &n) != egl.EGL_TRUE) return error.ChooseConfig;

            const egl_context_attribs: []const egl.EGLint = &.{
                egl.EGL_CONTEXT_MAJOR_VERSION,       @intCast(opengl.version.major),
                egl.EGL_CONTEXT_MINOR_VERSION,       @intCast(opengl.version.minor),
                egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                egl.EGL_NONE,
            };

            const egl_context = egl.eglCreateContext(egl_display, egl_config, egl.EGL_NO_CONTEXT, egl_context_attribs.ptr) orelse return error.CreateContext;

            const window: *wl.wl_egl_window = wl.wl_egl_window_create(surface, @intCast(config.size.width), @intCast(config.size.height)) orelse return error.CreateWindow;
            const egl_surface = egl.eglCreateWindowSurface(egl_display, egl_config, @intFromPtr(window), null) orelse return error.CreateWindowSurface;

            break :api .{ .opengl = .{
                .display = egl_display,
                .config = egl_config.?,
                .context = egl_context,
                .window = window,
                .surface = egl_surface,
            } };
        },
        .vulkan => @panic("vulkan"),
        .none => {
            const buffer, const pixels = try Shm.resize(shm orelse return error.NoShm, config.size.width, config.size.height);
            wl.wl_surface_attach(surface, buffer, 0, 0);
            wl.wl_surface_damage(surface, 0, 0, @intCast(config.size.width), @intCast(config.size.height));

            @memset(pixels, 255);
            break :api .{ .none = .{
                .shm = shm.?,
                .buffer = buffer,
                .pixels = pixels,
            } };
        },
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
        .decoration = decoration,
        .api = api,
    };
}

pub fn close(self: @This()) void {
    switch (self.api) {
        .opengl => |opengl| {
            _ = egl.eglDestroySurface(opengl.display, opengl.surface);
            wl.wl_egl_window_destroy(opengl.window);
            _ = egl.eglDestroyContext(opengl.display, opengl.context);
            _ = egl.eglTerminate(opengl.display);
        },
        .vulkan => {},
        .none => |none| wl.wl_buffer_destroy(none.buffer),
    }

    if (self.decoration) |decoration| decoration.deinit();
    xdg.xdg_toplevel_destroy(self.xdg_toplevel);
    xdg.xdg_surface_destroy(self.xdg_surface);
    wl.wl_surface_destroy(self.surface);
    if (self.mouse) |mouse| mouse.deinit();
    if (self.keyboard) |keyboard| keyboard.deinit();
    wl.wl_display_disconnect(self.display);
}

pub fn poll(self: *@This(), keyboard: *Window.io.Keyboard) !?Window.io.Event {
    if (self.keyboard == null) {
        self.keyboard = .{};
        try self.keyboard.?.get(self.seat);
    }
    if (self.mouse == null) {
        self.mouse = .{};
        try self.mouse.?.get(self.seat);
    }

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
        .resize => |size| {
            self.size = size;
            switch (self.api) {
                .opengl => |opengl| wl.wl_egl_window_resize(opengl.window, @intCast(size.width), @intCast(size.height), 0, 0),
                .vulkan => @panic("vulkan"),
                .none => if (size.width != 0 and size.height != 0) {
                    self.api.none.buffer, self.api.none.pixels = try Shm.resize(self.api.none.shm, size.width, size.height);
                    @memset(self.api.none.pixels, 255);
                    wl.wl_surface_attach(self.surface, self.api.none.buffer, 0, 0);
                    wl.wl_surface_damage(self.surface, 0, 0, @intCast(size.width), @intCast(size.height));
                    wl.wl_surface_commit(self.surface);
                } else return null,
            }
        },
        .key => |key| keyboard.keys[@intFromEnum(key.sym)] = key.state,
        else => {},
    }
    return event;
}

pub fn getSize(self: @This()) Window.Size {
    return self.size;
}

pub fn setTitle(self: @This(), title: [:0]const u8) void {
    xdg.xdg_toplevel_set_title(self.xdg_toplevel, title);
}

pub fn fullscreen(self: @This(), state: bool) void {
    if (state)
        xdg.xdg_toplevel_set_fullscreen(self.xdg_toplevel, null)
    else
        xdg.xdg_toplevel_unset_fullscreen(self.xdg_toplevel);
}

pub fn maximize(self: @This(), state: bool) void {
    if (state)
        xdg.xdg_toplevel_set_maximized(self.xdg_toplevel)
    else
        xdg.xdg_toplevel_unset_maximized(self.xdg_toplevel);
}

pub fn minimize(self: @This()) void {
    xdg.xdg_toplevel_set_minimized(self.xdg_toplevel);
}

const Registry = struct {
    compositor: ?*wl.wl_compositor = null,
    xdg_wm_base: ?*xdg.xdg_wm_base = null,
    seat: ?*wl.wl_seat = null,
    shm: ?*wl.wl_shm = null,
    decoration_manager: ?*decor.zxdg_decoration_manager_v1 = null,

    fn callback(self: *@This(), registry: *wl.wl_registry, name: u32, interfacez: [*:0]const u8, version: u32) callconv(.c) void {
        const interface = std.mem.span(interfacez);

        if (std.mem.eql(u8, interface, std.mem.span(wl.wl_compositor_interface.name))) {
            self.compositor = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_compositor_interface, version));
        } else if (std.mem.eql(u8, interface, std.mem.span(xdg.xdg_wm_base_interface.name))) {
            self.xdg_wm_base = @ptrCast(wl.wl_registry_bind(registry, name, @ptrCast(&xdg.xdg_wm_base_interface), version));
        } else if (std.mem.eql(u8, interface, std.mem.span(wl.wl_seat_interface.name))) {
            self.seat = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_seat_interface, version));
        } else if (std.mem.eql(u8, interface, std.mem.span(wl.wl_shm_interface.name))) {
            self.shm = @ptrCast(wl.wl_registry_bind(registry, name, &wl.wl_shm_interface, version));
        } else if (std.mem.eql(u8, interface, std.mem.span(decor.zxdg_decoration_manager_v1_interface.name))) {
            self.decoration_manager = @ptrCast(wl.wl_registry_bind(registry, name, @ptrCast(&decor.zxdg_decoration_manager_v1_interface), version));
        }
    }
};

pub const callback = struct {
    fn configure(done: *bool, xdg_surface: *xdg.xdg_surface, serial: u32) callconv(.c) void {
        xdg.xdg_surface_ack_configure(xdg_surface, serial);
        done.* = true;
    }

    fn xdgBasePing(_: ?*anyopaque, xdg_wm_base: ?*xdg.xdg_wm_base, serial: u32) callconv(.c) void {
        xdg.xdg_wm_base_pong(xdg_wm_base, serial);
    }
};

pub const Toplevel = struct {
    pub const listener: *const xdg.xdg_toplevel_listener = &.{
        .configure = configure,
        .close = close_,
        .configure_bounds = configureBounds,
        .wm_capabilities = capabilities,
    };

    // TODO: use this correctly
    pub fn configure(_: ?*anyopaque, _: ?*xdg.xdg_toplevel, width: i32, height: i32, _: [*c]xdg.wl_array) callconv(.c) void {
        events.pushBackAssumeCapacity(.{ .resize = .{ .width = @intCast(width), .height = @intCast(height) } });
    }

    pub fn close_(_: ?*anyopaque, _: ?*xdg.xdg_toplevel) callconv(.c) void {
        events.pushFrontAssumeCapacity(.close);
    }

    pub fn configureBounds(_: ?*anyopaque, _: ?*xdg.xdg_toplevel, _: i32, _: i32) callconv(.c) void {}

    pub fn capabilities(_: ?*anyopaque, _: ?*xdg.xdg_toplevel, _: [*c]xdg.struct_wl_array) callconv(.c) void {}
};

pub const Keyboard = struct {
    handle: ?*wl.wl_keyboard = null,
    xkb_ctx: ?*xkb.xkb_context = null,
    xkb_state: ?*xkb.xkb_state = null,
    xkb_keymap: ?*xkb.xkb_keymap = null,
    keymap_data: []align(std.heap.page_size_min) u8 = undefined,
    mods_depressed: u32 = 0,
    mods_latched: u32 = 0,
    mods_locked: u32 = 0,
    group: u32 = 0,
    focused: bool = true,

    pub const listener: *const wl.wl_keyboard_listener = &.{
        .keymap = @ptrCast(&keymap),
        .enter = @ptrCast(&enter),
        .leave = @ptrCast(&leave),
        .key = @ptrCast(&key),
        .modifiers = @ptrCast(&modifiers),
        .repeat_info = @ptrCast(&repeatInfo),
    };

    pub fn get(self: *@This(), seat: *wl.wl_seat) !void {
        self.xkb_ctx = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS) orelse return error.CreateXkbContext;
        self.handle = wl.wl_seat_get_keyboard(seat) orelse return error.GetKeyboard;
        if (wl.wl_keyboard_add_listener(self.handle, listener, self) != 0) return error.AddKeyboardListener;
    }

    pub fn deinit(self: @This()) void {
        if (self.xkb_state != null) xkb.xkb_state_unref(self.xkb_state);
        if (self.xkb_keymap != null) xkb.xkb_keymap_unref(self.xkb_keymap);
        if (self.xkb_ctx != null) xkb.xkb_context_unref(self.xkb_ctx);
        if (self.handle != null) wl.wl_keyboard_destroy(self.handle);
    }

    fn keymap(self: *@This(), _: *wl.wl_keyboard, format: u32, fd: std.posix.fd_t, size: u32) callconv(.c) void {
        if (format != wl.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) return;
        defer std.posix.close(fd);

        if (self.xkb_state != null) xkb.xkb_state_unref(self.xkb_state);
        if (self.xkb_keymap != null) {
            xkb.xkb_keymap_unref(self.xkb_keymap);
            std.posix.munmap(self.keymap_data);
        }

        self.keymap_data = std.posix.mmap(null, size, std.c.PROT.READ, .{ .TYPE = .PRIVATE }, fd, 0) catch return;
        self.xkb_keymap = xkb.xkb_keymap_new_from_buffer(self.xkb_ctx, self.keymap_data.ptr, self.keymap_data.len, xkb.XKB_KEYMAP_FORMAT_TEXT_V1, xkb.XKB_KEYMAP_COMPILE_NO_FLAGS) orelse return;
        self.xkb_state = xkb.xkb_state_new(self.xkb_keymap) orelse return;
        _ = xkb.xkb_state_update_mask(self.xkb_state, self.mods_depressed, self.mods_latched, self.mods_locked, self.group, 0, 0);
    }

    fn enter(self: *@This(), _: *wl.wl_keyboard, _: u32, _: ?*wl.wl_surface, _: [*c]wl.wl_array) callconv(.c) void {
        self.focused = true;
        events.pushBackAssumeCapacity(.{ .focus = .enter });
    }

    fn leave(self: *@This(), _: *wl.wl_keyboard, _: u32, _: ?*wl.wl_surface) callconv(.c) void {
        self.focused = false;
        events.pushBackAssumeCapacity(.{ .focus = .leave });
    }

    fn key(self: *@This(), _: *wl.wl_keyboard, _: u32, _: u32, keycode: u32, state: u32) callconv(.c) void {
        if (!self.focused) return;
        if (self.xkb_state == null or self.xkb_keymap == null) return;

        const sym = xkb.xkb_state_key_get_one_sym(self.xkb_state, keycode + 8);

        events.pushBackAssumeCapacity(.{ .key = .{
            .state = switch (state) {
                wl.WL_KEYBOARD_KEY_STATE_PRESSED => .pressed,
                wl.WL_KEYBOARD_KEY_STATE_RELEASED => .released,
                else => unreachable,
            },
            .code = @intCast(keycode),
            .sym = Window.io.Event.Key.Sym.fromXkb(sym) orelse return,
        } });
    }

    fn modifiers(self: *@This(), _: *wl.wl_keyboard, _: u32, mods_depressed: u32, mods_latched: u32, mods_locked: u32, group: u32) callconv(.c) void {
        self.mods_depressed = mods_depressed;
        self.mods_latched = mods_latched;
        self.mods_locked = mods_locked;
        self.group = group;
        if (self.xkb_state == null or self.xkb_keymap == null) return;

        _ = xkb.xkb_state_update_mask(self.xkb_state, mods_depressed, mods_latched, mods_locked, group, 0, 0);
    }

    fn repeatInfo(_: ?*anyopaque, _: *wl.wl_keyboard, _: i32, _: i32) callconv(.c) void {}
};

pub const Mouse = struct {
    handle: *wl.wl_pointer = undefined,
    last_position: Window.Position(u32) = .{},
    focused: bool = true,

    pub const listener: *const wl.wl_pointer_listener = &.{
        .enter = @ptrCast(&enter),
        .leave = @ptrCast(&leave),
        .motion = @ptrCast(&motion),
        .button = @ptrCast(&button),
        .axis = @ptrCast(&axis),
        .frame = @ptrCast(&frame),
        .axis_source = @ptrCast(&axisSource),
        .axis_stop = @ptrCast(&axisStop),
        .axis_discrete = @ptrCast(&axisDiscrete),
        .axis_value120 = @ptrCast(&axisValue120),
        .axis_relative_direction = @ptrCast(&axisRelativeDirection),
    };

    pub fn get(self: *@This(), seat: *wl.wl_seat) !void {
        self.handle = wl.wl_seat_get_pointer(seat) orelse return error.GetPointer;
        if (wl.wl_pointer_add_listener(self.handle, listener, self) != 0) return error.AddPointerListener;
    }

    pub fn deinit(self: @This()) void {
        wl.wl_pointer_destroy(self.handle);
    }

    fn enter(self: *@This(), _: *wl.wl_pointer, _: u32, _: *wl.wl_surface, _: wl.wl_fixed_t, _: wl.wl_fixed_t) callconv(.c) void {
        self.focused = true;
    }
    fn leave(self: *@This(), _: *wl.wl_pointer, _: u32, _: *wl.wl_surface) callconv(.c) void {
        self.focused = false;
    }
    fn motion(self: *@This(), _: *wl.wl_pointer, _: u32, x: wl.wl_fixed_t, y: wl.wl_fixed_t) callconv(.c) void {
        if (x < 0 or y < 0) return;
        if (!self.focused) return;
        @setRuntimeSafety(false);
        self.last_position = .{ .x = @intFromFloat(wl.wl_fixed_to_double(x)), .y = @intFromFloat(wl.wl_fixed_to_double(y)) };
        events.pushBackAssumeCapacity(.{ .mouse = .{ .move = .{ .x = @intFromFloat(wl.wl_fixed_to_double(x)), .y = @intFromFloat(wl.wl_fixed_to_double(y)) } } });
    }
    fn button(self: *@This(), _: *wl.wl_pointer, _: u32, _: u32, code: u32, state: u32) callconv(.c) void {
        if (!self.focused) return;
        events.pushBackAssumeCapacity(.{ .mouse = .{ .button = .{
            .state = switch (state) {
                wl.WL_POINTER_BUTTON_STATE_PRESSED => .pressed,
                wl.WL_POINTER_BUTTON_STATE_RELEASED => .released,
                else => unreachable,
            },
            .code = Window.io.Event.Mouse.Button.Code.fromWayland(code) orelse return,
            .position = self.last_position,
        } } });
    }
    fn axis(self: *@This(), _: *wl.wl_pointer, _: u32, axis_: u32, value: wl.wl_fixed_t) callconv(.c) void {
        if (!self.focused) return;
        const delta = wl.wl_fixed_to_double(value) / 10;
        events.pushBackAssumeCapacity(.{ .mouse = .{ .scroll = switch (axis_) {
            wl.WL_POINTER_AXIS_VERTICAL_SCROLL => .{ .y = @intFromFloat(delta) },
            wl.WL_POINTER_AXIS_HORIZONTAL_SCROLL => .{ .x = @intFromFloat(delta) },
            else => unreachable,
        } } });
    }
    fn frame(_: *@This(), _: *wl.wl_pointer) callconv(.c) void {}
    fn axisSource(_: *@This(), _: *wl.wl_pointer, _: u32) callconv(.c) void {}
    fn axisStop(_: *@This(), _: *wl.wl_pointer, _: u32, _: u32) callconv(.c) void {}
    fn axisDiscrete(_: *@This(), _: *wl.wl_pointer, _: u32, _: i32) callconv(.c) void {}
    fn axisValue120(_: *@This(), _: *wl.wl_pointer, _: u32, _: i32) callconv(.c) void {}
    fn axisRelativeDirection(_: *@This(), _: *wl.wl_pointer, _: u32, _: u32) callconv(.c) void {}
};

pub const Shm = struct {
    pub fn alloc(size: usize) !std.posix.fd_t {
        var name: *const [8:0]u8 = "wl_shm__";
        const fd: std.posix.fd_t = @intCast(std.c.shm_open(
            name[0..].ptr,
            @bitCast(std.posix.O{
                .ACCMODE = .RDWR,
                .CREAT = true,
                .EXCL = true,
            }),
            std.posix.S.IWUSR | std.posix.S.IRUSR | std.posix.S.IWOTH | std.posix.S.IROTH,
        ));

        _ = std.c.shm_unlink(name[0..].ptr);

        try std.posix.ftruncate(fd, @intCast(size));

        return fd;
    }

    pub fn resize(shm: *wl.wl_shm, width: usize, height: usize) !struct { *wl.wl_buffer, []u8 } {
        const stride = 4;
        const size = width * height * stride;
        const fd: std.posix.fd_t = try alloc(size);
        defer std.posix.close(fd);
        const pixels = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );
        const pool: *wl.wl_shm_pool = wl.wl_shm_create_pool(shm, fd, @intCast(size)) orelse return error.CreateShmPool;
        const buffer = wl.wl_shm_pool_create_buffer(pool, 0, @intCast(width), @intCast(height), @intCast(width * stride), wl.WL_SHM_FORMAT_ARGB8888) orelse return error.CreateShmPoolBuffer;
        wl.wl_shm_pool_destroy(pool);
        return .{ buffer, pixels[0..size] };
    }
};

pub const Decoration = struct {
    manager: *decor.zxdg_decoration_manager_v1 = undefined,
    toplevel: *decor.zxdg_toplevel_decoration_v1 = undefined,
    mode: Mode = undefined,

    pub const listener: *const decor.zxdg_toplevel_decoration_v1_listener = &.{
        .configure = @ptrCast(&configure),
    };

    pub const Mode = enum(u32) {
        client = decor.ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE,
        server = decor.ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE,
    };

    pub fn get(self: *@This(), xdg_toplevel: *xdg.xdg_toplevel) !void {
        self.toplevel = decor.zxdg_decoration_manager_v1_get_toplevel_decoration(self.manager, @ptrCast(xdg_toplevel)) orelse return error.GetToplevelDecoration;
        decor.zxdg_toplevel_decoration_v1_set_mode(self.toplevel, @intFromEnum(Mode.server));
        if (decor.zxdg_toplevel_decoration_v1_add_listener(self.toplevel, listener, self) != 0) return error.AddToplevelDecorationListener;
    }

    pub fn deinit(self: @This()) void {
        decor.zxdg_toplevel_decoration_v1_destroy(self.toplevel);
    }

    pub fn configure(self: *@This(), _: *decor.zxdg_toplevel_decoration_v1, mode: u32) callconv(.c) void {
        self.mode = @enumFromInt(mode);
        switch (self.mode) {
            .client => {
                std.log.warn("No server side decorations available", .{});
            },
            .server => {},
        }
    }
};
