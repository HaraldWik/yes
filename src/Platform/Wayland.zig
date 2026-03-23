const std = @import("std");
const build_options = @import("build_options");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const zxdg = wayland.client.zxdg;
const wp = wayland.client.wp;
const egl = @cImport({ // TODO: replace
    @cInclude("EGL/egl.h");
    @cInclude("wayland-egl.h");
    @cInclude("wayland-egl-core.h");
});
const xkb = @import("xkbcommon");
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");

const Wayland = @This();

allocator: std.mem.Allocator,
display: *wl.Display,
registry: *wl.Registry,

compositor: *wl.Compositor,
xdg_wm_base: *xdg.WmBase,
seat: *wl.Seat,
shm: *wl.Shm,
zxdg_decoration_manager: ?*zxdg.DecorationManagerV1 = null,
wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1,

io_manager: *IoManager,

const Globals = struct {
    compositor: ?*wl.Compositor = null,
    xdg_wm_base: ?*xdg.WmBase = null,
    seat: ?*wl.Seat = null,
    shm: ?*wl.Shm = null,
    zxdg_decoration_manager: ?*zxdg.DecorationManagerV1 = null,
    wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
};

const IoManager = struct {
    err: ?anyerror = null,
    current_window: std.atomic.Value(?*Window) = .init(null),
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,
    touch: ?*wl.Touch = null,
    xkb: struct {
        context: ?*xkb.xkb_context = null,
        state: ?*xkb.xkb_state = null,
        keymap: ?*xkb.xkb_keymap = null,
        keymap_data: []align(std.heap.page_size_min) u8 = undefined,
        modifiers: struct {
            depressed: u32 = 0,
            latched: u32 = 0,
            locked: u32 = 0,
            group: u32 = 0,
        } = .{},
    } = .{},
};

pub const Window = struct {
    interface: PlatformWindow = .{},
    allocator: std.mem.Allocator = undefined,
    err: ?anyerror = null,
    wl_surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    xdg_toplevel: *xdg.Toplevel = undefined,
    zxdg_toplevel_decoration: ?*zxdg.ToplevelDecorationV1 = null,
    zxdg_toplevel_decoration_mode: zxdg.ToplevelDecorationV1.Mode = .client_side,
    wp_cursor_shape_device: ?*wp.CursorShapeDeviceV1 = null,
    // event_queue: *wl.EventQueue = undefined,
    events: std.ArrayList(PlatformWindow.Event) = .empty,
    running: bool = true,
    surface: Surface = .empty,
    cursor: PlatformWindow.Cursor = .default,

    pub const Surface = union(enum) {
        empty,
        framebuffer: Software,
        opengl: OpenGL,
        vulkan,

        pub const OpenGL = struct {
            display: *anyopaque,
            config: *anyopaque,
            context: *anyopaque,
            window: *wl.EglWindow,
            surface: *anyopaque,
        };
        pub const Software = struct {
            buffer: *wl.Buffer,
            pixels: [*]align(std.heap.page_size_min) u8,
        };
    };
};

pub fn init(allocator: std.mem.Allocator) !@This() {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var globals: Globals = .{};
    registry.setListener(*Globals, registryListener, &globals);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const xdg_wm_base = globals.xdg_wm_base orelse return error.NoXdgWmBase;
    xdg_wm_base.setListener(?*anyopaque, xdgWmBaseListener, null);

    const compositor = globals.compositor orelse return error.NoCompositor;
    const seat = globals.seat orelse return error.NoWlSeat;
    const shm = globals.shm orelse return error.NoShm;

    const io_manager = try allocator.create(IoManager);
    io_manager.* = .{ .xkb = .{
        .context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS) orelse return error.CreateXkbContext,
    } };

    seat.setListener(*IoManager, seatListener, io_manager);
    if (display.flush() != .SUCCESS) return error.Flush;
    if (display.dispatch() != .SUCCESS) return error.Dispatch;

    if (io_manager.err) |err| return err;

    return .{
        .allocator = allocator,
        .display = display,
        .registry = registry,

        .compositor = compositor,
        .xdg_wm_base = xdg_wm_base,
        .seat = seat,
        .shm = shm,
        .zxdg_decoration_manager = globals.zxdg_decoration_manager,
        .wp_cursor_shape_manager = globals.wp_cursor_shape_manager,

        .io_manager = io_manager,
    };
}

pub fn deinit(self: @This()) void {
    if (self.io_manager.xkb.state) |state| xkb.xkb_state_unref(state);
    if (self.io_manager.xkb.keymap) |keymap| xkb.xkb_keymap_unref(keymap);
    if (self.io_manager.xkb.context) |context| xkb.xkb_context_unref(context);
    if (self.io_manager.keyboard) |keyboard| keyboard.release();
    if (self.io_manager.pointer) |pointer| pointer.release();
    if (self.io_manager.touch) |touch| touch.release();
    self.allocator.destroy(self.io_manager);
    self.shm.destroy();
    self.seat.destroy();
    self.xdg_wm_base.destroy();
    self.compositor.destroy();
    self.registry.destroy();
    self.display.disconnect();
}

pub fn platform(self: *@This()) Platform {
    return .{
        .ptr = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowFramebuffer = windowFramebuffer,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = opengl.eglGetProcAddress,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *PlatformWindow, options: PlatformWindow.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    window.allocator = self.allocator;

    window.wl_surface = try self.compositor.createSurface();
    window.xdg_surface = try self.xdg_wm_base.getXdgSurface(window.wl_surface);
    window.xdg_toplevel = try window.xdg_surface.getToplevel();

    // window.event_queue = try self.display.createQueue();
    // window.wl_surface.setQueue(window.event_queue);
    // window.xdg_surface.setQueue(window.event_queue);
    // window.xdg_toplevel.setQueue(window.event_queue);

    var configured: bool = false;
    window.xdg_surface.setListener(*bool, xdgSurfaceListener, &configured);
    window.xdg_toplevel.setListener(*Window, xdgToplevelListener, window);

    try windowSetProperty(context, platform_window, .{ .title = options.title });
    try windowSetProperty(context, platform_window, .{ .resize_policy = options.resize_policy });
    try windowSetProperty(context, platform_window, .{ .decorated = options.decorated });
    if (self.io_manager.pointer) |pointer| {
        if (self.wp_cursor_shape_manager) |wp_cursor_shape_manager|
            window.wp_cursor_shape_device = try wp_cursor_shape_manager.getPointer(pointer);
    }

    window.wl_surface.commit();
    while (!configured) if (self.display.dispatch() != .SUCCESS) return error.Dispatch;
    window.wl_surface.commit();

    switch (options.surface_type) {
        .framebuffer => try windowAllocShm(window, self.shm),
        .opengl => |gl| {
            const display = egl.eglGetDisplay(@ptrCast(self.display)) orelse return error.EglGetDisplay;

            var major: egl.EGLint = undefined;
            var minor: egl.EGLint = undefined;
            if (egl.eglInitialize(display, &major, &minor) != egl.EGL_TRUE) return error.EglInitialize;
            if (egl.eglBindAPI(egl.EGL_OPENGL_API) != egl.EGL_TRUE) return error.EglBindAPI; // EGL_OPENGL_ES_API

            const config_attribs: []const egl.EGLint = &.{
                egl.EGL_SURFACE_TYPE, egl.EGL_WINDOW_BIT,
                egl.EGL_RED_SIZE,     8,
                egl.EGL_GREEN_SIZE,   8,
                egl.EGL_BLUE_SIZE,    8,
                egl.EGL_ALPHA_SIZE,   8,
                egl.EGL_RENDERABLE_TYPE, egl.EGL_OPENGL_BIT, // egl.EGL_OPENGL_ES2_BIT,
                egl.EGL_NONE,
            };

            var config: egl.EGLConfig = undefined;
            var n: egl.EGLint = undefined;
            if (egl.eglChooseConfig(display, config_attribs.ptr, &config, 1, &n) != egl.EGL_TRUE) return error.ChooseConfig;

            const attribs: []const egl.EGLint = &.{
                egl.EGL_CONTEXT_MAJOR_VERSION,       @intCast(gl.major),
                egl.EGL_CONTEXT_MINOR_VERSION,       @intCast(gl.minor),
                egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                egl.EGL_NONE,
            };

            const egl_context = egl.eglCreateContext(display, config, egl.EGL_NO_CONTEXT, attribs.ptr) orelse return error.CreateContext;

            const egl_window = try wl.EglWindow.create(window.wl_surface, @intCast(options.size.width), @intCast(options.size.height));
            const egl_surface = egl.eglCreateWindowSurface(display, config, @intFromPtr(egl_window), null) orelse return error.CreateWindowSurface;

            _ = egl.eglSwapBuffers(display, egl_surface);

            window.surface = .{ .opengl = .{
                .display = display,
                .config = config.?,
                .context = egl_context,
                .window = egl_window,
                .surface = egl_surface,
            } };
        },
        else => {},
    }

    window.wl_surface.commit();
    if (self.display.roundtrip() != .SUCCESS) return error.Roundtrip;

    if (options.surface_type != .empty) try window.events.append(self.allocator, .{ .focus = .focused });
    try window.events.append(self.allocator, .{ .resize = options.size });
}
fn windowClose(context: *anyopaque, platform_window: *PlatformWindow) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    switch (window.surface) {
        .framebuffer => |software| {
            software.buffer.destroy();
        },
        .opengl => |gl| {
            _ = egl.eglDestroySurface(gl.display, gl.surface);
            gl.window.destroy();
            _ = egl.eglDestroyContext(gl.display, gl.context);
            _ = egl.eglTerminate(gl.display);
        },
        else => {},
    }

    if (window.zxdg_toplevel_decoration) |zxdg_toplevel_decoration| zxdg_toplevel_decoration.destroy();
    if (window.wp_cursor_shape_device) |wp_cursor_shape_device| wp_cursor_shape_device.destroy();
    window.xdg_toplevel.destroy();
    window.xdg_surface.destroy();
    window.wl_surface.destroy();
    // window.event_queue.destroy();
    window.events.deinit(window.allocator);
}
fn windowPoll(context: *anyopaque, platform_window: *PlatformWindow) anyerror!?PlatformWindow.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (!window.running) return .close;

    if (self.display.dispatchPending() != .SUCCESS) return error.DispatchPending;
    if (!self.display.prepareRead()) return null;
    self.io_manager.current_window.store(window, .seq_cst);

    if (self.display.flush() != .SUCCESS) return error.Flush;

    if (window.err) |err| return err;
    if (self.io_manager.err) |err| return err;

    var pfd: std.posix.pollfd = .{
        .fd = @intCast(self.display.getFd()),
        .events = std.posix.POLL.IN,
        .revents = 0,
    };

    if (std.posix.poll(@ptrCast(&pfd), 1) catch 0 > 0)
        _ = self.display.readEvents()
    else
        self.display.cancelRead();

    if (self.display.dispatchPending() != .SUCCESS) return error.DispatchPending;
    self.io_manager.current_window.store(null, .seq_cst);

    const event = window.events.pop() orelse return null;
    switch (event) {
        .resize => |size| switch (window.surface) {
            .framebuffer => if (!size.eql(.{})) {
                window.interface.size = size;
                try windowAllocShm(window, self.shm);
            },
            .opengl => |gl| {
                window.wl_surface.commit();
                gl.window.resize(@intCast(size.width), @intCast(size.height), 0, 0);
                window.wl_surface.commit();
            },
            .vulkan => window.wl_surface.commit(),
            else => {},
        },
        else => {},
    }
    return event;
}
fn windowSetProperty(context: *anyopaque, platform_window: *PlatformWindow, property: PlatformWindow.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (property) {
        .title => |title| {
            const title_z = try self.allocator.dupeZ(u8, title);
            defer self.allocator.free(title_z);
            window.xdg_toplevel.setTitle(title_z.ptr);
        },
        .size => {},
        .position => {},
        .resize_policy => |resize_policy| switch (resize_policy) {
            .resizable => |resizable| {
                const size: PlatformWindow.Size = if (resizable) .{} else window.interface.size;
                window.xdg_toplevel.setMaxSize(@intCast(size.width), @intCast(size.height));
                window.xdg_toplevel.setMinSize(@intCast(size.width), @intCast(size.height));
            },
            .specified => |specified| {
                const max_size: PlatformWindow.Size = if (specified.max_size) |size| size else .{};
                const min_size: PlatformWindow.Size = if (specified.min_size) |size| size else .{};
                window.xdg_toplevel.setMaxSize(@intCast(max_size.width), @intCast(max_size.height));
                window.xdg_toplevel.setMinSize(@intCast(min_size.width), @intCast(min_size.height));
            },
        },
        .fullscreen => |fullscreen| {
            if (fullscreen)
                window.xdg_toplevel.setFullscreen(null)
            else
                window.xdg_toplevel.unsetFullscreen();
        },
        .maximized => |maximized| {
            if (maximized)
                window.xdg_toplevel.setMaximized()
            else
                window.xdg_toplevel.unsetMaximized();
        },
        .minimized => |minimized| {
            if (minimized)
                window.xdg_toplevel.setMinimized();
            // TODO: request focus
        },
        .always_on_top => {},
        .floating => {},
        .decorated => |decorated| if (window.zxdg_toplevel_decoration) |zxdg_toplevel_decoration| if (decorated) {
            window.zxdg_toplevel_decoration = try self.zxdg_decoration_manager.?.getToplevelDecoration(window.xdg_toplevel);
            window.zxdg_toplevel_decoration.?.setListener(*Window, zxdgToplevelDecorationListener, window);
        } else {
            window.zxdg_toplevel_decoration_mode = .client_side;
            zxdg_toplevel_decoration.destroy();
        },
        .focus => {}, // TODO: add focus request
        .cursor => |cursor| if (window.wp_cursor_shape_device) |wp_cursor_shape_device| {
            window.cursor = cursor;
            const shape: wp.CursorShapeDeviceV1.Shape = @enumFromInt(@intFromEnum(cursor));
            wp_cursor_shape_device.setShape(0, shape);
        },
    }
}
fn windowFramebuffer(_: *anyopaque, platform_window: *PlatformWindow) anyerror!PlatformWindow.Framebuffer {
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    return .{ .pixels = window.surface.framebuffer.pixels };
}
fn windowOpenglMakeCurrent(_: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    std.debug.assert(window.surface == .opengl);
    const gl = window.surface.opengl;
    if (egl.eglMakeCurrent(gl.display, gl.surface, gl.surface, gl.context) != egl.EGL_TRUE) return error.EglMakeCurrent;
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    std.debug.assert(window.surface == .opengl);
    const gl = window.surface.opengl;
    if (egl.eglSwapBuffers(gl.display, gl.surface) != egl.EGL_TRUE) return error.EglSwapBuffers;
    if (self.display.dispatchPending() != .SUCCESS) return error.DispatchPending;
}
fn windowOpenglSwapInterval(_: *anyopaque, platform_window: *PlatformWindow, interval: i32) anyerror!void {
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    std.debug.assert(window.surface == .opengl);
    const gl = window.surface.opengl;
    if (egl.eglSwapInterval(gl.display, interval) != egl.EGL_TRUE) return error.EglSwapInterval;
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *PlatformWindow, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const vkCreateWaylandSurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateWaylandSurfaceKHR") orelse return error.LoadVkCreateWaylandSurfaceKHR);

    const create_info: vulkan.Surface.CreateInfo = .{
        .wayland = .{
            .display = self.display,
            .surface = window.wl_surface,
        },
    };

    var surface: ?*vulkan.Surface = undefined;
    if (vkCreateWaylandSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateWaylandSurfaceKHR;
    return surface orelse error.InvalidSurface;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            inline for (std.meta.fields(Globals)) |field| {
                const GlobalType = std.meta.Child(std.meta.Child(field.type));
                if (std.mem.orderZ(u8, global.interface, GlobalType.interface.name) == .eq) {
                    @field(globals, field.name) = registry.bind(global.name, GlobalType, 1) catch return;
                    return;
                }
            }
        },
        .global_remove => {},
    }
}

fn xdgWmBaseListener(wm_base: *xdg.WmBase, event: xdg.WmBase.Event, _: ?*anyopaque) void {
    switch (event) {
        .ping => |ping| wm_base.pong(ping.serial),
    }
}

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, io_manager: *IoManager) void {
    switch (event) {
        .capabilities => |capabilities| {
            if (capabilities.capabilities.keyboard) {
                io_manager.keyboard = seat.getKeyboard() catch |err| {
                    io_manager.err = err;
                    return;
                };
                io_manager.keyboard.?.setListener(*IoManager, keyboardListener, io_manager);
            } else if (io_manager.keyboard) |keyboard| {
                keyboard.release();
                io_manager.keyboard = null;
            }
            if (capabilities.capabilities.pointer) {
                io_manager.pointer = seat.getPointer() catch |err| {
                    io_manager.err = err;
                    return;
                };
                io_manager.pointer.?.setListener(*IoManager, pointerListener, io_manager);
            } else if (io_manager.pointer) |pointer| {
                pointer.release();
                io_manager.pointer = null;
            }
            if (capabilities.capabilities.touch) {
                io_manager.touch = seat.getTouch() catch |err| {
                    io_manager.err = err;
                    return;
                };
                io_manager.touch.?.setListener(*IoManager, touchListener, io_manager);
            } else if (io_manager.touch) |touch| {
                touch.release();
                io_manager.touch = null;
            }
        },
        .name => |name| {
            std.log.debug("seat name: {s}", .{name.name});
        },
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, io_manager: *IoManager) void {
    const current_window = io_manager.current_window.load(.seq_cst);
    switch (event) {
        .keymap => |keymap| {
            if (keymap.format != .xkb_v1) return;
            defer _ = std.posix.system.close(keymap.fd);

            if (io_manager.xkb.state != null) xkb.xkb_state_unref(io_manager.xkb.state);
            if (io_manager.xkb.keymap != null) {
                xkb.xkb_keymap_unref(io_manager.xkb.keymap);
                if (io_manager.xkb.keymap_data.len != 0) std.posix.munmap(io_manager.xkb.keymap_data);
            }

            io_manager.xkb.keymap_data = std.posix.mmap(null, keymap.size, .{ .READ = true }, .{ .TYPE = .PRIVATE }, keymap.fd, 0) catch return;
            io_manager.xkb.keymap = xkb.xkb_keymap_new_from_buffer(io_manager.xkb.context.?, io_manager.xkb.keymap_data.ptr, io_manager.xkb.keymap_data.len, xkb.XKB_KEYMAP_FORMAT_TEXT_V1, xkb.XKB_KEYMAP_COMPILE_NO_FLAGS) orelse return;
            io_manager.xkb.state = xkb.xkb_state_new(io_manager.xkb.keymap.?) orelse return;
            _ = xkb.xkb_state_update_mask(
                io_manager.xkb.state.?,
                io_manager.xkb.modifiers.depressed,
                io_manager.xkb.modifiers.latched,
                io_manager.xkb.modifiers.locked,
                io_manager.xkb.modifiers.group,
                0,
                0,
            );
        },
        .modifiers => |modifiers| {
            io_manager.xkb.modifiers = .{
                .depressed = modifiers.mods_depressed,
                .latched = modifiers.mods_latched,
                .locked = modifiers.mods_locked,
                .group = modifiers.group,
            };
            if (io_manager.xkb.state == null or io_manager.xkb.keymap == null) return;

            _ = xkb.xkb_state_update_mask(io_manager.xkb.state.?, modifiers.mods_depressed, modifiers.mods_latched, modifiers.mods_locked, modifiers.group, 0, 0);
        },
        .enter => if (current_window) |window| if (window.interface.focus == .unfocused) {
            window.events.append(window.allocator, .{ .focus = .focused }) catch |err| {
                window.err = err;
            };
        },
        .leave => if (current_window) |window| if (window.interface.focus == .focused) {
            window.events.append(window.allocator, .{ .focus = .unfocused }) catch |err| {
                window.err = err;
            };
        },
        .key => |key| if (current_window) |window| {
            if (io_manager.xkb.state == null or io_manager.xkb.keymap == null) return;
            const sym = xkb.xkb_state_key_get_one_sym(io_manager.xkb.state.?, key.key + 8);
            const window_event: PlatformWindow.Event.Key = .{
                .state = @enumFromInt(@intFromEnum(key.state)),
                .code = key.key + 8,
                .sym = PlatformWindow.Event.Key.Sym.fromXkb(sym) orelse return,
            };
            window.events.append(window.allocator, .{ .key = window_event }) catch |err| {
                window.err = err;
            };
        },
        .repeat_info => {},
    }
}

fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, io_manager: *IoManager) void {
    const window = io_manager.current_window.load(.seq_cst) orelse return;
    switch (event) {
        .enter => if (window.wp_cursor_shape_device) |wp_cursor_shape_device| {
            const shape: wp.CursorShapeDeviceV1.Shape = @enumFromInt(@intFromEnum(window.cursor));
            wp_cursor_shape_device.setShape(0, shape);
        },
        .leave => {},
        .motion => |motion| {
            const mouse_motion: PlatformWindow.Event.MouseMotion = .{ .x = motion.surface_x.toDouble(), .y = motion.surface_y.toDouble() };
            window.events.append(window.allocator, .{ .mouse_motion = mouse_motion }) catch |err| {
                window.err = err;
            };
        },
        .button => |button| {
            const mouse_button: PlatformWindow.Event.MouseButton = .{
                .state = @enumFromInt(@intFromEnum(button.state)),
                .button = PlatformWindow.Event.MouseButton.Button.fromWayland(button.button).?,
            };
            window.events.append(window.allocator, .{ .mouse_button = mouse_button }) catch |err| {
                window.err = err;
            };
        },
        .axis => |axis| {
            const mouse_scroll: PlatformWindow.Event.MouseScroll = switch (axis.axis) {
                .vertical_scroll => .{ .vertical = -axis.value.toDouble() / 10.0 },
                .horizontal_scroll => .{ .horizontal = axis.value.toDouble() / 10.0 },
                _ => unreachable,
            };
            window.events.append(window.allocator, .{ .mouse_scroll = mouse_scroll }) catch |err| {
                window.err = err;
            };
        },
    }
}

fn touchListener(_: *wl.Touch, event: wl.Touch.Event, io_manager: *IoManager) void {
    _ = io_manager;
    switch (event) {
        else => {}, //std.log.info("touch event: {t}", .{event}),
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, configured: *bool) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            configured.* = true;
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, window: *Window) void {
    const allocator = window.allocator;
    switch (event) {
        .configure => |configure| for (configure.states.slice(xdg.Toplevel.State)) |state| switch (state) {
            .resizing, .fullscreen, .maximized => {
                const size: PlatformWindow.Size = .{ .width = @intCast(configure.width), .height = @intCast(configure.height) };
                window.events.append(allocator, .{ .resize = size }) catch |err| {
                    window.err = err;
                };
            },
            .activated => {
                if (window.interface.focus == .focused) return;
                window.events.append(allocator, .{ .focus = .focused }) catch |err| {
                    window.err = err;
                };
            },
            else => {},
        },
        .close => {
            window.events.append(window.allocator, .close) catch |err| {
                window.err = err;
            };
            window.running = false;
        },
    }
}

fn zxdgToplevelDecorationListener(_: *zxdg.ToplevelDecorationV1, event: zxdg.ToplevelDecorationV1.Event, window: *Window) void {
    switch (event) {
        .configure => |configure| window.zxdg_toplevel_decoration_mode = configure.mode,
    }
}

fn windowAllocShm(window: *Window, shm: *wl.Shm) !void {
    const size = window.interface.size;

    const channels = 4;
    const length = size.width * size.height * channels;

    var fd_name_buf: [64]u8 = undefined;
    const fd_name = try std.fmt.bufPrintSentinel(&fd_name_buf, "/yes_window_shm_{d}_{d}", .{ size.width, size.height }, 0);
    const fd: std.posix.fd_t = std.posix.system.shm_open(
        fd_name[0..].ptr,
        @bitCast(std.posix.O{
            .ACCMODE = .RDWR,
            .CREAT = true,
            .EXCL = true,
        }),
        std.posix.S.IWUSR | std.posix.S.IRUSR | std.posix.S.IWOTH | std.posix.S.IROTH,
    );
    defer _ = std.posix.system.close(@intCast(fd));
    _ = std.posix.system.shm_unlink(fd_name[0..].ptr);
    _ = std.posix.system.ftruncate(@intCast(fd), length);

    var pixels = try std.posix.mmap(
        null,
        length,
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED },
        fd,
        0,
    );

    const pool: *wl.ShmPool = try shm.createPool(@intCast(fd), @intCast(length));
    defer pool.destroy();
    const buffer: *wl.Buffer = try pool.createBuffer(0, @intCast(size.width), @intCast(size.height), @intCast(size.width * channels), .argb8888);
    window.wl_surface.attach(buffer, 0, 0);
    window.wl_surface.damage(0, 0, @intCast(size.width), @intCast(size.height));
    window.wl_surface.commit();

    window.surface = .{ .framebuffer = .{ .buffer = buffer, .pixels = pixels.ptr } };
}
