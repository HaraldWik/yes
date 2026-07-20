const Wayland = @This();

const std = @import("std");
const build_options = @import("build_options");
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Desktop = @import("../Desktop.zig");
const DesktopWindow = @import("../Window.zig");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const xdg = wayland.client.xdg;
const zwp = wayland.client.zwp;
const zxdg = wayland.client.zxdg;
const egl = @import("egl");
const xkb = @import("xkbcommon");

gpa: std.mem.Allocator,
display: *wl.Display,
registry: *wl.Registry,

compositor: *wl.Compositor,
xdg_wm_base: *xdg.WmBase,
seat: *wl.Seat,
shm: *wl.Shm,
zxdg_decoration_manager: ?*zxdg.DecorationManagerV1 = null,
wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
zwp_pointer_constraints: ?*zwp.PointerConstraintsV1 = null,
zwp_relative_pointer_manager: ?*zwp.RelativePointerManagerV1 = null,

io_manager: *IoManager,

const Globals = struct {
    compositor: ?*wl.Compositor = null,
    xdg_wm_base: ?*xdg.WmBase = null,
    seat: ?*wl.Seat = null,
    shm: ?*wl.Shm = null,
    data_device_manager: ?*wl.DataDeviceManager = null,
    zxdg_decoration_manager: ?*zxdg.DecorationManagerV1 = null,
    wp_cursor_shape_manager: ?*wp.CursorShapeManagerV1 = null,
    zwp_pointer_constraints: ?*zwp.PointerConstraintsV1 = null,
    zwp_relative_pointer_manager: ?*zwp.RelativePointerManagerV1 = null,
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
    active_touches: std.AutoHashMapUnmanaged(i32, struct { x: f64, y: f64 }) = .empty,
    data_device_manager: *wl.DataDeviceManager,
    data_device: *wl.DataDevice,
    dnd: struct {
        offer: *wl.DataOffer = undefined,
        fd: std.posix.fd_t = 0,
    } = .{},
    clipboard: struct {
        offer: ?*wl.DataOffer = null,
        fd: std.posix.fd_t = 0,
    } = .{},
};

pub const Window = struct {
    interface: DesktopWindow = .{},
    gpa: std.mem.Allocator = undefined,
    err: ?anyerror = null,
    output: ?*wl.Output = null,
    wl_surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    xdg_toplevel: *xdg.Toplevel = undefined,
    zxdg_toplevel_decoration: ?*zxdg.ToplevelDecorationV1 = null,
    zxdg_toplevel_decoration_mode: ?zxdg.ToplevelDecorationV1.Mode = null,
    wp_cursor_shape_device: ?*wp.CursorShapeDeviceV1 = null,
    confined_pointer: ?*zwp.ConfinedPointerV1 = null,
    locked_pointer: ?*zwp.LockedPointerV1 = null,
    relative_pointer: ?*zwp.RelativePointerV1 = null,

    // event_queue: *wl.EventQueue = undefined,
    events: std.Deque(DesktopWindow.Event) = .empty,
    running: bool = true,
    surface: Surface = .empty,
    cursor: DesktopWindow.Cursor = .default,

    pub const Surface = union(enum) {
        empty,
        framebuffer: Framebuffer,
        egl: Egl,
        vulkan,

        pub const Egl = struct {
            display: *anyopaque,
            config: *anyopaque,
            context: ?*anyopaque,
            window: *wl.EglWindow,
            surface: *anyopaque,
        };
        pub const Framebuffer = struct {
            buffer: *wl.Buffer,
            pixels: [*]align(std.heap.page_size_min) u8,
        };
    };

    fn addEvent(self: *Window, event: DesktopWindow.Event) void {
        self.events.pushBack(self.gpa, event) catch {
            self.err = error.AddEvent;
        };
    }
};

pub fn connect(gpa: std.mem.Allocator) !Wayland {
    try Loader.load();

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
    const data_device_manager = globals.data_device_manager orelse return error.NoDataDeviceManager;

    const io_manager = try gpa.create(IoManager);
    io_manager.* = .{
        .xkb = .{
            .context = xkb.xkb_context_new(xkb.XKB_CONTEXT_NO_FLAGS) orelse return error.CreateXkbuserdata,
        },
        .data_device_manager = data_device_manager,
        .data_device = try data_device_manager.getDataDevice(seat),
    };

    seat.setListener(*IoManager, seatListener, io_manager);
    io_manager.data_device.setListener(*IoManager, dataDeviceListener, io_manager);

    // wl_data_source_offer(data_source, "text/plain;charset=utf-8");

    if (display.flush() != .SUCCESS) return error.Flush;
    if (display.dispatch() != .SUCCESS) return error.Dispatch;

    if (io_manager.err) |err| return err;

    return .{
        .gpa = gpa,
        .display = display,
        .registry = registry,

        .compositor = compositor,
        .xdg_wm_base = xdg_wm_base,
        .seat = seat,
        .shm = shm,
        .zxdg_decoration_manager = globals.zxdg_decoration_manager,
        .wp_cursor_shape_manager = globals.wp_cursor_shape_manager,
        .zwp_pointer_constraints = globals.zwp_pointer_constraints,
        .zwp_relative_pointer_manager = globals.zwp_relative_pointer_manager,

        .io_manager = io_manager,
    };
}

pub fn disconnect(self: Wayland) void {
    self.io_manager.data_device.destroy();
    if (self.io_manager.xkb.state) |state| xkb.xkb_state_unref(state);
    if (self.io_manager.xkb.keymap) |keymap| xkb.xkb_keymap_unref(keymap);
    if (self.io_manager.xkb.context) |context| xkb.xkb_context_unref(context);
    if (self.io_manager.keyboard) |keyboard| keyboard.release();
    if (self.io_manager.pointer) |pointer| pointer.release();
    if (self.io_manager.touch) |touch| touch.release();
    self.io_manager.active_touches.deinit(self.gpa);
    self.gpa.destroy(self.io_manager);
    self.shm.destroy();
    self.seat.destroy();
    self.xdg_wm_base.destroy();
    self.compositor.destroy();
    self.registry.destroy();
    self.display.disconnect();
    Loader.unload();
}

pub fn desktop(self: *Wayland) Desktop {
    return .{
        .userdata = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowNative = windowNative,
            .windowFramebuffer = windowFramebuffer,
            .windowFramebufferPresent = Desktop.noWindowFramebufferPresent,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = opengl.eglGetProcAddress,
        },
    };
}

fn windowOpen(userdata: ?*anyopaque, desktop_window: *DesktopWindow, options: DesktopWindow.OpenOptions) anyerror!void {
    const self: *Wayland = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    window.gpa = self.gpa;

    window.wl_surface = try self.compositor.createSurface();
    window.xdg_surface = try self.xdg_wm_base.getXdgSurface(window.wl_surface);
    window.xdg_toplevel = try window.xdg_surface.getToplevel();

    // window.event_queue = try self.display.createQueue();
    // window.wl_surface.setQueue(window.event_queue);
    // window.xdg_surface.setQueue(window.event_queue);
    // window.xdg_toplevel.setQueue(window.event_queue);

    var configured: bool = false;
    window.wl_surface.setListener(*Window, surfaceListener, window);
    window.xdg_surface.setListener(*bool, xdgSurfaceListener, &configured);
    window.xdg_toplevel.setListener(*Window, xdgToplevelListener, window);

    try windowSetProperty(userdata, desktop_window, .{ .title = options.title });

    if (options.position) |position| try windowSetProperty(userdata, desktop_window, .{ .position = position });
    try windowSetProperty(userdata, desktop_window, .{ .resize_policy = options.resize_policy });
    if (options.decorated) try windowSetProperty(userdata, desktop_window, .{ .decorated = options.decorated });

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
            window.surface = .{ .egl = undefined };
            const window_egl = &window.*.surface.egl;
            window_egl.display = egl.eglGetDisplay(@ptrCast(self.display)) orelse return error.EglGetDisplay;

            var major: egl.EGLint = undefined;
            var minor: egl.EGLint = undefined;
            if (egl.eglInitialize(window_egl.display, &major, &minor) != egl.EGL_TRUE) return error.EglInitialize;
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
            var configs_count: egl.EGLint = undefined;
            if (egl.eglChooseConfig(window_egl.display, config_attribs.ptr, &config, 1, &configs_count) != egl.EGL_TRUE) return error.EglChooseConfig;

            const attribs: []const egl.EGLint = &.{
                egl.EGL_CONTEXT_MAJOR_VERSION,       @intCast(gl.major),
                egl.EGL_CONTEXT_MINOR_VERSION,       @intCast(gl.minor),
                egl.EGL_CONTEXT_OPENGL_PROFILE_MASK, egl.EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                egl.EGL_NONE,
            };

            window_egl.context = egl.eglCreateContext(window_egl.display, config, egl.EGL_NO_CONTEXT, attribs.ptr) orelse return error.EglCreateContext;

            window_egl.window = try wl.EglWindow.create(window.wl_surface, @intCast(options.size.width), @intCast(options.size.height));
            window_egl.surface = egl.eglCreateWindowSurface(window_egl.display, config, @intFromPtr(window_egl.window), null) orelse return error.EglCreateWindowSurface;
        },
        else => {},
    }

    window.wl_surface.commit();
    if (self.display.roundtrip() != .SUCCESS) return error.Roundtrip;

    if (options.surface_type != .empty) window.addEvent(.{ .focus = true });
    window.addEvent(.{ .resize = options.size });

    if (window.err) |err| return err;
}
fn windowClose(userdata: ?*anyopaque, desktop_window: *DesktopWindow) void {
    const self: *Wayland = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));
    _ = self;

    switch (window.surface) {
        .framebuffer => |framebuffer| {
            framebuffer.buffer.destroy();
            windowFreeShm(window);
        },
        .egl => |gl| {
            _ = egl.eglDestroySurface(gl.display, gl.surface);
            gl.window.destroy();
            _ = egl.eglDestroyContext(gl.display, gl.context);
            _ = egl.eglTerminate(gl.display);
        },
        else => {},
    }

    if (window.confined_pointer) |confined_pointer| confined_pointer.destroy();
    if (window.locked_pointer) |locked_pointer| locked_pointer.destroy();
    if (window.relative_pointer) |relative_pointer| relative_pointer.destroy();
    if (window.zxdg_toplevel_decoration) |zxdg_toplevel_decoration| zxdg_toplevel_decoration.destroy();
    if (window.wp_cursor_shape_device) |wp_cursor_shape_device| wp_cursor_shape_device.destroy();
    window.xdg_toplevel.destroy();
    window.xdg_surface.destroy();
    window.wl_surface.destroy();
    // window.event_queue.destroy();
    window.events.deinit(window.gpa);
}
fn windowPoll(userdata: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!?DesktopWindow.Event {
    const self: *Wayland = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    if (!window.running) return .close;

    if (self.display.dispatchPending() != .SUCCESS) return error.DispatchPending;
    if (self.display.prepareRead()) {
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
    }

    const event = window.events.popFront() orelse return null;
    switch (event) {
        .resize => |size| switch (window.surface) {
            .framebuffer => if (!size.eql(.{})) {
                window.interface.size = size;
                try windowAllocShm(window, self.shm);
            },
            .egl => |gl| {
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
fn windowSetProperty(userdata: ?*anyopaque, desktop_window: *DesktopWindow, property: DesktopWindow.Property) anyerror!void {
    const self: *Wayland = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    switch (property) {
        .title => |title| {
            window.xdg_toplevel.setTitle(title.ptr);
            window.xdg_toplevel.setAppId(title.ptr);
        },
        .size => {},
        .position => {},
        .resize_policy => |resize_policy| switch (resize_policy) {
            .resizable => |resizable| {
                const size: DesktopWindow.Size = if (resizable) .{} else window.interface.size;
                window.xdg_toplevel.setMaxSize(@intCast(size.width), @intCast(size.height));
                window.xdg_toplevel.setMinSize(@intCast(size.width), @intCast(size.height));
            },
            .specified => |specified| {
                const max_size: DesktopWindow.Size = if (specified.max_size) |size| size else .{};
                const min_size: DesktopWindow.Size = if (specified.min_size) |size| size else .{};
                window.xdg_toplevel.setMaxSize(@intCast(max_size.width), @intCast(max_size.height));
                window.xdg_toplevel.setMinSize(@intCast(min_size.width), @intCast(min_size.height));
            },
        },
        .mode => |mode| {
            if (mode != .minimized) {
                if (window.interface.unminimized_mode == .fullscreen) window.xdg_toplevel.unsetFullscreen();
                if (window.interface.unminimized_mode == .maximized) window.xdg_toplevel.unsetMaximized();
            }
            switch (mode) {
                .windowed => {},
                .fullscreen => window.xdg_toplevel.setFullscreen(null),
                .maximized => window.xdg_toplevel.setMaximized(),
                .minimized => window.xdg_toplevel.setMinimized(),
            }
        },
        .always_on_top => {},
        .floating => {},
        .decorated => |decorated| if (window.zxdg_toplevel_decoration) |zxdg_toplevel_decoration| if (decorated) {
            window.zxdg_toplevel_decoration = try self.zxdg_decoration_manager.?.getToplevelDecoration(window.xdg_toplevel);
            window.zxdg_toplevel_decoration.?.setListener(*Window, zxdgToplevelDecorationListener, window);
        } else {
            window.zxdg_toplevel_decoration_mode = null;
            zxdg_toplevel_decoration.destroy();
        },
        .focused => {}, // TODO: add focus request
        .cursor => |cursor| if (window.wp_cursor_shape_device) |wp_cursor_shape_device| {
            window.cursor = cursor;
            const shape: wp.CursorShapeDeviceV1.Shape = @enumFromInt(@intFromEnum(cursor));
            wp_cursor_shape_device.setShape(0, shape);
        },
        .cursor_mode => |mode| if (self.io_manager.pointer) |pointer| if (self.zwp_pointer_constraints) |zwp_pointer_constraints| {
            if (mode != .captured and mode != .locked) if (window.relative_pointer) |relative_pointer| {
                relative_pointer.destroy();
                window.relative_pointer = null;
            };

            switch (mode) {
                .normal, .hidden => {
                    if (window.confined_pointer) |confined_pointer| {
                        confined_pointer.destroy();
                        window.confined_pointer = null;
                    }
                    if (window.locked_pointer) |locked_pointer| {
                        locked_pointer.destroy();
                        window.locked_pointer = null;
                    }
                },
                .confined => if (window.confined_pointer == null) {
                    if (window.locked_pointer) |locked_pointer| {
                        locked_pointer.destroy();
                        window.locked_pointer = null;
                    }

                    window.confined_pointer = try zwp_pointer_constraints.confinePointer(window.wl_surface, pointer, null, .persistent);
                },
                .captured => if (self.zwp_relative_pointer_manager) |zwp_relative_pointer_manager| {
                    if (window.confined_pointer) |confined_pointer| {
                        confined_pointer.destroy();
                        window.confined_pointer = null;
                    }

                    if (window.locked_pointer == null) {
                        window.locked_pointer = try zwp_pointer_constraints.lockPointer(window.wl_surface, pointer, null, .persistent);
                    }
                    if (window.relative_pointer == null) {
                        window.relative_pointer = try zwp_relative_pointer_manager.getRelativePointer(pointer);
                        window.relative_pointer.?.setListener(*Window, relativePointerListener, window);
                    }
                },
                .locked => {
                    if (window.confined_pointer) |confined_pointer| {
                        confined_pointer.destroy();
                        window.confined_pointer = null;
                    }

                    if (window.locked_pointer == null) {
                        window.locked_pointer = try zwp_pointer_constraints.lockPointer(window.wl_surface, pointer, null, .persistent);
                    }
                    if (window.relative_pointer == null) if (self.zwp_relative_pointer_manager) |zwp_relative_pointer_manager| {
                        window.relative_pointer = try zwp_relative_pointer_manager.getRelativePointer(pointer);
                        window.relative_pointer.?.setListener(*Window, relativePointerListener, window);
                    };
                },
            }
        },
    }
}
fn windowNative(userdata: ?*anyopaque, desktop_window: *DesktopWindow) DesktopWindow.Native {
    const self: *Wayland = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));
    return .{
        .wayland = .{
            .display = self.display,
            .surface = window.wl_surface,
            .compositor = self.compositor,
        },
    };
}
fn windowFramebuffer(_: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!DesktopWindow.Framebuffer {
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));
    return .{ .pixels = window.surface.framebuffer.pixels };
}
fn windowOpenglMakeCurrent(_: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!void {
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    std.debug.assert(window.surface == .egl);
    const gl = window.surface.egl;
    if (egl.eglMakeCurrent(gl.display, gl.surface, gl.surface, gl.context) != egl.EGL_TRUE) return error.EglMakeCurrent;
}
fn windowOpenglSwapBuffers(_: ?*anyopaque, desktop_window: *DesktopWindow) anyerror!void {
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    std.debug.assert(window.surface == .egl);
    const gl = window.surface.egl;
    if (egl.eglSwapBuffers(gl.display, gl.surface) != egl.EGL_TRUE) return error.EglSwapBuffers;
}
fn windowOpenglSwapInterval(_: ?*anyopaque, desktop_window: *DesktopWindow, interval: i32) anyerror!void {
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    std.debug.assert(window.surface == .egl);
    const gl = window.surface.egl;
    if (egl.eglSwapInterval(gl.display, interval) != egl.EGL_TRUE) return error.EglSwapInterval;
}
fn windowVulkanCreateSurface(userdata: ?*anyopaque, desktop_window: *DesktopWindow, instance: *anyopaque, allocator: ?*const anyopaque, loader: vulkan.PfnGetInstanceProcAddr) anyerror!*anyopaque {
    const self: *Wayland = @ptrCast(@alignCast(userdata.?));
    const window: *Window = @alignCast(@fieldParentPtr("interface", desktop_window));

    const vkCreateWaylandSurfaceKHR: vulkan.SurfaceCreateProc = @ptrCast(loader(instance, "vkCreateWaylandSurfaceKHR") orelse return error.LoadVkCreateWaylandSurfaceKHR);

    const create_info: vulkan.SurfaceCreateInfo = .{ .wayland = .{
        .display = self.display,
        .surface = window.wl_surface,
    } };

    var surface: ?*anyopaque = undefined;
    if (vkCreateWaylandSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateWaylandSurfaceKHR;
    return surface orelse error.InvalidSurface;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            if (std.mem.orderZ(u8, global.interface, wl.Output.interface.name) == .eq) {
                // std.debug.print("monitor!, {s}\n", .{global.interface});
                return;
            }
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
        .name => {},
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
        .enter => |enter| if (enter.surface) |surface| {
            const window: *Window = @ptrCast(@alignCast(surface.getUserData().?));
            if (!window.interface.focused) window.addEvent(.{ .focus = true });
            io_manager.current_window.store(window, .seq_cst);
        },
        .leave => |leave| if (leave.surface) |surface| {
            const window: *Window = @ptrCast(@alignCast(surface.getUserData().?));

            if (window.interface.focused) window.addEvent(.{ .focus = false });
            if (current_window.? == window) io_manager.current_window.store(null, .seq_cst);
        },
        .key => |key| if (current_window) |window| {
            // HARALD TMP
            const data_source = io_manager.data_device_manager.createDataSource() catch return;
            // data_source.offer("text/plain;charset=utf-8");
            data_source.offer("text/uri-list");
            io_manager.data_device.setSelection(data_source, key.serial);
            data_source.setListener(*IoManager, dataSourceListener, io_manager);
            // HARALD TMP

            if (io_manager.xkb.state == null or io_manager.xkb.keymap == null) return;
            const sym = xkb.xkb_state_key_get_one_sym(io_manager.xkb.state.?, key.key + 8);
            const window_event: DesktopWindow.Event.Key = .{
                .state = @enumFromInt(@intFromEnum(key.state)),
                .code = key.key + 8,
                .sym = DesktopWindow.Event.Key.Sym.fromXkb(sym) orelse return,
            };
            window.addEvent(.{ .key = window_event });
        },
        .repeat_info => {},
    }
}

fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, io_manager: *IoManager) void {
    const window = io_manager.current_window.load(.seq_cst) orelse return;
    switch (event) {
        .enter => |enter| switch (window.interface.cursor_mode) {
            .normal, .confined => if (window.wp_cursor_shape_device) |wp_cursor_shape_device| {
                const shape: wp.CursorShapeDeviceV1.Shape = @enumFromInt(@intFromEnum(window.cursor));
                wp_cursor_shape_device.setShape(0, shape);
            },
            .hidden, .captured, .locked => pointer.setCursor(enter.serial, null, 0, 0),
        },
        .leave => {},
        .motion => |motion| {
            const previous = window.interface.mouse_position;

            const mouse_motion: DesktopWindow.Event.MouseMotion = .{
                .x = motion.surface_x.toDouble(),
                .y = motion.surface_y.toDouble(),
                .dx = motion.surface_x.toDouble() - previous.x,
                .dy = motion.surface_y.toDouble() - previous.y,
            };
            window.addEvent(.{ .mouse_motion = mouse_motion });
        },
        .button => |button| {
            const mouse_button: DesktopWindow.Event.MouseButton = .{
                .state = @enumFromInt(@intFromEnum(button.state)),
                .button = DesktopWindow.Event.MouseButton.Button.fromWayland(button.button).?,
            };
            window.addEvent(.{ .mouse_button = mouse_button });
        },
        .axis => |axis| {
            const mouse_scroll: DesktopWindow.Event.MouseScroll = switch (axis.axis) {
                .vertical_scroll => .{ .vertical = -axis.value.toDouble() / 10.0 },
                .horizontal_scroll => .{ .horizontal = axis.value.toDouble() / 10.0 },
                _ => unreachable,
            };
            window.addEvent(.{ .mouse_scroll = mouse_scroll });
        },
    }
}

fn relativePointerListener(_: *zwp.RelativePointerV1, event: zwp.RelativePointerV1.Event, window: *Window) void {
    switch (event) {
        .relative_motion => |motion| {
            const width = @as(f64, @floatFromInt(window.interface.size.width));
            const height = @as(f64, @floatFromInt(window.interface.size.height));
            const dx = motion.dx.toDouble();
            const dy = motion.dy.toDouble();

            const mouse_motion: DesktopWindow.Event.MouseMotion = .{
                .x = std.math.clamp(width / 2 + dx, 0, width),
                .y = std.math.clamp(height / 2 + dy, 0, height),
                .dx = dx,
                .dy = dy,
            };

            window.addEvent(.{ .mouse_motion = mouse_motion });
        },
    }
}

fn touchListener(_: *wl.Touch, event: wl.Touch.Event, io_manager: *IoManager) void {
    const window = io_manager.current_window.load(.seq_cst) orelse return;
    switch (event) {
        .down => |down| {
            const touch_down: DesktopWindow.Event.Touch = .{
                .id = down.id,
                .x = down.x.toDouble(),
                .y = down.y.toDouble(),
            };
            window.addEvent(.{ .touch_down = touch_down });
            io_manager.active_touches.put(window.gpa, touch_down.id, .{
                .x = touch_down.x,
                .y = touch_down.y,
            }) catch |err| {
                io_manager.err = err;
            };
        },
        .up => |up| {
            const touch_position = io_manager.active_touches.fetchRemove(up.id).?.value;
            const touch_up: DesktopWindow.Event.Touch = .{
                .id = up.id,
                .x = touch_position.x,
                .y = touch_position.y,
            };
            window.addEvent(.{ .touch_up = touch_up });
        },
        .motion => |motion| {
            const touch_motion: DesktopWindow.Event.Touch = .{
                .id = motion.id,
                .x = motion.x.toDouble(),
                .y = motion.y.toDouble(),
            };
            window.addEvent(.{ .touch_motion = touch_motion });
            io_manager.active_touches.put(window.gpa, touch_motion.id, .{
                .x = touch_motion.x,
                .y = touch_motion.y,
            }) catch |err| {
                io_manager.err = err;
            };
        },
        .cancel => {
            io_manager.active_touches.clearAndFree(window.gpa);
        },
        .frame => {},
    }
}

fn dataDeviceListener(_: *wl.DataDevice, event: wl.DataDevice.Event, io_manager: *IoManager) void {
    switch (event) {
        .data_offer => |offer| {
            io_manager.clipboard.offer = offer.id;
            offer.id.setListener(*IoManager, dataOfferListener, io_manager);
        },
        .enter => |enter| {
            const window: *Window = @ptrCast(@alignCast(enter.surface.?.getUserData()));
            // std.log.scoped(.data_device).info("{t} ({t} window)", .{ event, window.surface });
            if (enter.id) |offer| {
                // std.debug.print("accept\n", .{});
                offer.accept(enter.serial, "text/uri-list");

                io_manager.dnd.offer = offer;
            }

            window.addEvent(.drag_enter);
            io_manager.current_window.store(window, .seq_cst);
        },
        .leave => {
            const window = io_manager.current_window.load(.seq_cst) orelse return;
            window.addEvent(.drag_leave);
        },
        .motion => |motion| {
            const window = io_manager.current_window.load(.seq_cst) orelse return;

            const previous = window.interface.mouse_position;

            const drag_motion: DesktopWindow.Event.MouseMotion = .{
                .x = motion.x.toDouble(),
                .y = motion.y.toDouble(),
                .dx = motion.x.toDouble() - previous.x,
                .dy = motion.y.toDouble() - previous.y,
            };

            window.addEvent(.{ .drag_motion = drag_motion });
        },
        .drop => {
            const offer = io_manager.dnd.offer;

            var fds: [2]std.posix.fd_t = undefined;
            _ = std.posix.system.pipe(&fds);

            const read_fd = fds[0];
            const write_fd = fds[1];

            offer.receive("text/uri-list", write_fd);
            offer.receive("text/plain", write_fd);
            _ = std.posix.system.close(write_fd);

            const window = io_manager.current_window.load(.seq_cst) orelse return;
            window.addEvent(.{ .drag_drop = .{ .action = .copy, .kind = .text, .fd = read_fd } });
        },
        .selection => |selection| {
            // std.log.scoped(.data_device).info("{t}", .{event});

            const offer = selection.id orelse {
                io_manager.clipboard.offer = null;
                return;
            };

            io_manager.clipboard.offer = offer;
        },
    }
}

fn dataSourceListener(source: *wl.DataSource, event: wl.DataSource.Event, io_manager: *IoManager) void {
    _ = io_manager;
    switch (event) {
        .send => |send| {

            // if (!std.mem.eql(u8, std.mem.span(send.mime_type), "text/plain") and
            //     !std.mem.eql(u8, std.mem.span(send.mime_type), "text/plain;charset=utf-8"))
            // {
            //     _ = std.posix.system.close(send.fd);
            //     return;
            // }

            if (!std.mem.eql(u8, std.mem.span(send.mime_type), "text/uri-list")) {
                _ = std.posix.system.close(send.fd);
                // std.log.info("send wrong mime: {s}", .{send.mime_type});

                return;
            }

            // std.log.info("send found: {s}", .{send.mime_type});

            const bytes =
                "file:///home/user/Pictures/Screenshots/Screenshot%20From%202026-04-17%2017-47-33.png\n" ++
                "file:///home/user/Pictures/Screenshots/Screenshot%20From%202026-04-17%2017-47-33.png\n";

            var written: usize = 0;
            while (written < bytes.len) {
                const n = std.posix.system.write(send.fd, bytes[0..].ptr, bytes.len);
                written += @intCast(n);
            }

            _ = std.posix.system.close(send.fd);
        },

        .cancelled => {
            source.destroy();
        },

        else => {},
    }
}

fn dataOfferListener(_: *wl.DataOffer, event: wl.DataOffer.Event, io_manager: *IoManager) void {
    _ = io_manager;
    _ = event;
    _ = io_manager;
    // switch (event) {
    //     .offer => |offer| {
    //         std.log.scoped(.data_offer).info("offer: {s}", .{offer.mime_type});
    //     },
    //     .source_actions => |action| {
    //         std.log.scoped(.data_offer).info("source_actions: {s}{s}{s}", .{
    //             if (action.source_actions.ask) "ask;" else "",
    //             if (action.source_actions.copy) "copy;" else "",
    //             if (action.source_actions.move) "move;" else "",
    //         });
    //     },
    //     .action => |action| {
    //         std.log.scoped(.data_offer).info("action: {s}{s}{s}", .{
    //             if (action.dnd_action.ask) "ask;" else "",
    //             if (action.dnd_action.copy) "copy;" else "",
    //             if (action.dnd_action.move) "move;" else "",
    //         });
    //     },
    // }
}

fn surfaceListener(_: *wl.Surface, event: wl.Surface.Event, window: *Window) void {
    switch (event) {
        .enter => |enter| {
            window.output = enter.output;
        },
        .leave => {},
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
    switch (event) {
        .configure => |configure| {
            const size: DesktopWindow.Size = .{ .width = @intCast(configure.width), .height = @intCast(configure.height) };
            if (!size.eql(.{})) window.addEvent(.{ .resize = size });

            for (configure.states.slice(xdg.Toplevel.State)) |state| if (state == .activated and window.interface.focused) {
                if (window.interface.focused == true) return;
                window.addEvent(.{ .focus = true });
            };
        },
        .close => {
            window.addEvent(.close);
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
    const fd_name = try std.fmt.bufPrintSentinel(&fd_name_buf, "{d}window_shm_{d}_{d}", .{ @intFromPtr(window.xdg_toplevel), size.width, size.height }, 0);
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

    const pixels = try std.posix.mmap(
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

fn windowFreeShm(window: *Window) void {
    const size = window.interface.size;
    const length = size.width * size.height * 4;
    std.posix.munmap(window.surface.framebuffer.pixels[0..length]);
}

var wl_loader: Loader = .{};
/// Loads the wayland-client at runtime
pub const Loader = struct {
    lib: std.DynLib = undefined,

    wl_display_cancel_read: ?*const fn (display: *wl.Display) callconv(.c) void = null,
    wl_display_connect_to_fd: ?*const fn (fd: c_int) callconv(.c) ?*wl.Display = null,
    wl_display_connect: ?*const fn (name: ?[*:0]const u8) callconv(.c) ?*wl.Display = null,
    wl_display_create_queue: ?*const fn (display: *wl.Display) callconv(.c) ?*wl.EventQueue = null,
    wl_display_disconnect: ?*const fn (display: *wl.Display) callconv(.c) void = null,
    wl_display_dispatch_pending: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_dispatch_queue_pending: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_dispatch_queue: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_dispatch: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_flush: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_get_error: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_get_fd: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_prepare_read_queue: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_prepare_read: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_read_events: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_display_roundtrip_queue: ?*const fn (display: *wl.Display, queue: *wl.EventQueue) callconv(.c) c_int = null,
    wl_display_roundtrip: ?*const fn (display: *wl.Display) callconv(.c) c_int = null,
    wl_event_queue_destroy: ?*const fn (queue: *wl.EventQueue) callconv(.c) void = null,
    wl_proxy_add_dispatcher: ?*const fn (proxy: *wl.Proxy, dispatcher: *const wl.Proxy.DispatcherFn, implementation: ?*const anyopaque, data: ?*anyopaque) callconv(.c) c_int = null,
    wl_proxy_create: ?*const fn (factory: *wl.Proxy, interface: *const wl.Interface) callconv(.c) ?*wl.Proxy = null,
    wl_proxy_destroy: ?*const fn (proxy: *wl.Proxy) callconv(.c) void = null,
    wl_proxy_get_id: ?*const fn (proxy: *wl.Proxy) callconv(.c) u32 = null,
    wl_proxy_get_user_data: ?*const fn (proxy: *wl.Proxy) callconv(.c) ?*anyopaque = null,
    wl_proxy_get_version: ?*const fn (proxy: *wl.Proxy) callconv(.c) u32 = null,
    wl_proxy_marshal_array_constructor_versioned: ?*const fn (proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface, version: u32) callconv(.c) ?*wl.Proxy = null,
    wl_proxy_marshal_array_constructor: ?*const fn (proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface) callconv(.c) ?*wl.Proxy = null,
    wl_proxy_marshal_array: ?*const fn (proxy: *wl.Proxy, opcode: u32, args: ?[*]wl.Argument) callconv(.c) void = null,
    wl_proxy_set_queue: ?*const fn (proxy: *wl.Proxy, queue: *wl.EventQueue) callconv(.c) void = null,

    comptime {
        _ = exports;
    }

    pub const exports = struct {
        // zig fmt: off
        pub export fn wl_display_cancel_read(display: *wl.Display) void { wl_loader.wl_display_cancel_read.?(display); }
        pub export fn wl_display_connect_to_fd(fd: c_int) ?*wl.Display { return wl_loader.wl_display_connect_to_fd.?(fd); }
        pub export fn wl_display_connect(name: ?[*:0]const u8) ?*wl.Display { return wl_loader.wl_display_connect.?(name); }
        pub export fn wl_display_create_queue(display: *wl.Display) ?*wl.EventQueue { return wl_loader.wl_display_create_queue.?(display); }
        pub export fn wl_display_disconnect(display: *wl.Display) void { wl_loader.wl_display_disconnect.?(display); }
        pub export fn wl_display_dispatch_pending(display: *wl.Display) c_int { return wl_loader.wl_display_dispatch_pending.?(display); }
        pub export fn wl_display_dispatch_queue_pending(display: *wl.Display, queue: *wl.EventQueue) c_int { return wl_loader.wl_display_dispatch_queue_pending.?(display, queue); }
        pub export fn wl_display_dispatch_queue(display: *wl.Display, queue: *wl.EventQueue) c_int { return wl_loader.wl_display_dispatch_queue.?(display, queue); }
        pub export fn wl_display_dispatch(display: *wl.Display) c_int { return wl_loader.wl_display_dispatch.?(display); }
        pub export fn wl_display_flush(display: *wl.Display) c_int { return wl_loader.wl_display_flush.?(display); }
        pub export fn wl_display_get_error(display: *wl.Display) c_int { return wl_loader.wl_display_get_error.?(display); }
        pub export fn wl_display_get_fd(display: *wl.Display) c_int { return wl_loader.wl_display_get_fd.?(display); }
        pub export fn wl_display_prepare_read_queue(display: *wl.Display, queue: *wl.EventQueue) c_int { return wl_loader.wl_display_prepare_read_queue.?(display, queue); }
        pub export fn wl_display_prepare_read(display: *wl.Display) c_int { return wl_loader.wl_display_prepare_read.?(display); }
        pub export fn wl_display_read_events(display: *wl.Display) c_int { return wl_loader.wl_display_read_events.?(display); }
        pub export fn wl_display_roundtrip_queue(display: *wl.Display, queue: *wl.EventQueue) c_int { return wl_loader.wl_display_roundtrip_queue.?(display, queue); }
        pub export fn wl_display_roundtrip(display: *wl.Display) c_int { return wl_loader.wl_display_roundtrip.?(display); }
        pub export fn wl_event_queue_destroy(queue: *wl.EventQueue) void { wl_loader.wl_event_queue_destroy.?(queue); }
        pub export fn wl_proxy_add_dispatcher(proxy: *wl.Proxy, dispatcher: *const wl.Proxy.DispatcherFn, implementation: ?*const anyopaque, data: ?*anyopaque) c_int { return wl_loader.wl_proxy_add_dispatcher.?(proxy, dispatcher, implementation, data); }
        pub export fn wl_proxy_create(factory: *wl.Proxy, interface: *const wl.Interface) ?*wl.Proxy { return wl_loader.wl_proxy_create.?(factory, interface); }
        pub export fn wl_proxy_destroy(proxy: *wl.Proxy) void { wl_loader.wl_proxy_destroy.?(proxy); }
        pub export fn wl_proxy_get_id(proxy: *wl.Proxy) u32 { return wl_loader.wl_proxy_get_id.?(proxy); }
        pub export fn wl_proxy_get_user_data(proxy: *wl.Proxy) ?*anyopaque { return wl_loader.wl_proxy_get_user_data.?(proxy); }
        pub export fn wl_proxy_get_version(proxy: *wl.Proxy) u32 { return wl_loader.wl_proxy_get_version.?(proxy); }
        pub export fn wl_proxy_marshal_array_constructor_versioned(proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface, version: u32) ?*wl.Proxy { return wl_loader.wl_proxy_marshal_array_constructor_versioned.?(proxy, opcode, args, interface, version); }
        pub export fn wl_proxy_marshal_array_constructor(proxy: *wl.Proxy, opcode: u32, args: [*]wl.Argument, interface: *const wl.Interface) ?*wl.Proxy { return wl_loader.wl_proxy_marshal_array_constructor.?(proxy, opcode, args, interface); }
        pub export fn wl_proxy_marshal_array(proxy: *wl.Proxy, opcode: u32, args: ?[*]wl.Argument) void { wl_loader.wl_proxy_marshal_array.?(proxy, opcode, args); }
        pub export fn wl_proxy_set_queue(proxy: *wl.Proxy, queue: *wl.EventQueue) void { wl_loader.wl_proxy_set_queue.?(proxy, queue); }
        // zig fmt: on
    };

    pub fn load() !void {
        wl_loader.lib = try .openZ("libwayland-client.so.0");
        inline for (std.meta.fields(@This())) |field| {
            if (field.type != std.DynLib) {
                @field(wl_loader, field.name) = wl_loader.lib.lookup(field.type, field.name) orelse @panic(field.name);
            }
        }
    }

    pub fn unload() void {
        wl_loader.lib.close();
    }
};
