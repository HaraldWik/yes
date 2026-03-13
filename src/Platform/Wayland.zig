const std = @import("std");
const build_options = @import("build_options");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const egl = @cImport({ // TODO: replace
    @cInclude("EGL/egl.h");
    @cInclude("wayland-egl.h");
    @cInclude("wayland-egl-core.h");
});
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Platform = @import("../Platform.zig");

const Wayland = @This();

allocator: std.mem.Allocator,
display: *wl.Display,
registry: *wl.Registry,

compositor: *wl.Compositor,
wm_base: *xdg.WmBase,
seat: *wl.Seat,
shm: *wl.Shm,

io_manager: *IoManager,

const Globals = struct {
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,
    seat: ?*wl.Seat = null,
    shm: ?*wl.Shm = null,
};

const IoManager = struct {
    err: ?anyerror = null,
    windows: std.Deque(*Window) = .empty,
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,
    touch: ?*wl.Touch = null,
};

pub const Window = struct {
    interface: Platform.Window = .{},
    platform: *Wayland = undefined,
    err: ?anyerror = null,
    wl_surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    xdg_toplevel: *xdg.Toplevel = undefined,
    event_queue: *wl.EventQueue = undefined,
    events: std.ArrayList(Platform.Window.Event) = .empty,
    configured: bool = false,
    running: bool = true,
    surface: Surface = .empty,

    pub const Surface = union(enum) {
        empty,
        software: Software,
        opengl: OpenGL,
        vulkan,

        pub const OpenGL = struct {
            display: *anyopaque,
            config: *anyopaque,
            context: *anyopaque,
            window: *egl.wl_egl_window,
            surface: *anyopaque,
        };
        pub const Software = struct {
            buffer: *wl.Buffer,
            pixels: []u8,
        };
    };
};

pub fn init(allocator: std.mem.Allocator) !@This() {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var globals: Globals = undefined;
    registry.setListener(*Globals, registryListener, &globals);
    if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    const seat = globals.seat orelse return error.NoWlSeat;

    const io_manager = try allocator.create(IoManager);
    io_manager.* = .{};
    io_manager.windows = try .initCapacity(allocator, 1);

    seat.setListener(*IoManager, seatListener, io_manager);
    if (display.dispatch() != .SUCCESS) return error.Dispatch;

    if (io_manager.err) |err| return err;

    return .{
        .allocator = allocator,
        .display = display,
        .registry = registry,

        .compositor = globals.compositor orelse return error.NoWlCompositor,
        .wm_base = globals.wm_base orelse return error.NoXdgWmBase,
        .seat = seat,
        .shm = globals.shm orelse return error.NoWlShm,

        .io_manager = io_manager,
    };
}

pub fn deinit(self: @This()) void {
    if (self.io_manager.keyboard) |keyboard| keyboard.release();
    if (self.io_manager.pointer) |pointer| pointer.release();
    if (self.io_manager.touch) |touch| touch.release();
    self.io_manager.windows.deinit(self.allocator);
    self.allocator.destroy(self.io_manager);
    self.shm.destroy();
    self.seat.destroy();
    self.wm_base.destroy();
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
            .windowSoftwareGetPixels = windowSoftwareGetPixels,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = opengl.eglGetProcAddress,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    window.platform = self;
    try self.io_manager.windows.pushBack(self.allocator, window);

    window.wl_surface = try self.compositor.createSurface();
    window.xdg_surface = try self.wm_base.getXdgSurface(window.wl_surface);
    window.xdg_toplevel = try window.xdg_surface.getToplevel();

    window.event_queue = try self.display.createQueue();
    window.wl_surface.setQueue(window.event_queue);
    window.xdg_toplevel.setQueue(window.event_queue);

    window.xdg_surface.setListener(*Window, xdgSurfaceListener, window);
    window.xdg_toplevel.setListener(*Window, xdgToplevelListener, window);

    switch (options.surface_type) {
        .software => {
            const software_surface = try allocWindowShm(self.shm, options.size);
            window.wl_surface.attach(software_surface.buffer, 0, 0);
            window.wl_surface.damage(0, 0, @intCast(options.size.width), @intCast(options.size.height));
        },
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

            const egl_window: *egl.wl_egl_window = egl.wl_egl_window_create(@ptrCast(window.wl_surface), @intCast(options.size.width), @intCast(options.size.height)) orelse return error.CreateWindow;
            const egl_surface = egl.eglCreateWindowSurface(display, config, @intFromPtr(egl_window), null) orelse return error.CreateWindowSurface;

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
    if (!window.configured) return error.NoConfigureReceived;

    try windowSetProperty(context, platform_window, .{ .title = options.title });
    try windowSetProperty(context, platform_window, .{ .resize_policy = options.resize_policy });
    try windowSetProperty(context, platform_window, .{ .decorated = options.decorated });

    try window.events.append(self.allocator, .{ .resize = options.size });
}
fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    switch (window.surface) {
        .software => |software| {
            software.buffer.destroy();
        },
        .opengl => |gl| {
            _ = egl.eglDestroySurface(gl.display, gl.surface);
            egl.wl_egl_window_destroy(gl.window);
            _ = egl.eglDestroyContext(gl.display, gl.context);
            _ = egl.eglTerminate(gl.display);
        },
        else => {},
    }

    window.xdg_toplevel.destroy();
    window.xdg_surface.destroy();
    window.wl_surface.destroy();
    window.event_queue.destroy();
}
fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.err) |err| return err;
    if (!window.running) return null;

    if (self.display.prepareRead()) return null;
    if (self.display.readEvents() != .SUCCESS) return error.ReadEvents;
    if (self.display.dispatchQueue(window.event_queue) != .SUCCESS) return error.DispatchQueuePending;

    const event = window.events.pop() orelse return null;
    switch (event) {
        .resize => |size| switch (window.surface) {
            .software => if (!size.eql(.{})) {
                const software_surface = try allocWindowShm(self.shm, size);
                window.wl_surface.attach(software_surface.buffer, 0, 0);
                window.wl_surface.damage(0, 0, @intCast(size.width), @intCast(size.height));
                window.wl_surface.commit();
                window.surface.software = software_surface;
            },
            .opengl => |gl| {
                egl.wl_egl_window_resize(gl.window, @intCast(size.width), @intCast(size.height), 0, 0);
            },
            else => {},
        },
        else => {},
    }
    return event;
}
fn windowSetProperty(context: *anyopaque, platform_window: *Platform.Window, property: Platform.Window.Property) anyerror!void {
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
                const size: Platform.Window.Size = if (resizable) .{} else window.interface.size;
                window.xdg_toplevel.setMaxSize(@intCast(size.width), @intCast(size.height));
                window.xdg_toplevel.setMinSize(@intCast(size.width), @intCast(size.height));
            },
            .specified => |specified| {
                const max_size: Platform.Window.Size = if (specified.max_size) |size| size else .{};
                const min_size: Platform.Window.Size = if (specified.min_size) |size| size else .{};
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
        .decorated => {},
    }
}
fn windowSoftwareGetPixels(_: *anyopaque, platform_window: *Platform.Window) anyerror![]u8 {
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    return window.surface.software.pixels;
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *Platform.Window, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
    _ = interval;
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *Platform.Window, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
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
            if (std.mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                globals.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                globals.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                globals.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            } else if (std.mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                globals.seat = registry.bind(global.name, wl.Seat, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, window: *Window) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            window.wl_surface.commit();
            window.configured = true;
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, window: *Window) void {
    const allocator = window.platform.allocator;
    switch (event) {
        .configure => |configure| {
            const size: Platform.Window.Size = .{ .width = @intCast(configure.width), .height = @intCast(configure.height) };
            window.events.append(allocator, .{ .resize = size }) catch |err| {
                window.err = err;
            };
        },
        .close => {
            window.events.append(allocator, .close) catch |err| {
                window.err = err;
            };
            window.running = false;
        },
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
            std.log.info("seat name: {s}", .{name.name});
        },
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, io_manager: *IoManager) void {
    _ = io_manager;
    switch (event) {
        else => std.log.info("keyboard event: {t}", .{event}),
    }
}

fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, io_manager: *IoManager) void {
    _ = io_manager;
    switch (event) {
        else => std.log.info("pointer event: {t}", .{event}),
    }
}

fn touchListener(_: *wl.Touch, event: wl.Touch.Event, io_manager: *IoManager) void {
    _ = io_manager;
    switch (event) {
        else => std.log.info("touch event: {t}", .{event}),
    }
}

fn allocWindowShm(shm: *wl.Shm, size: Platform.Window.Size) !Window.Surface.Software {
    const channels = 4;
    const length = size.width * size.height * channels;

    var fd_name: [10:0]u8 = undefined;
    @memcpy(fd_name[4..], "wl_shm");
    std.debug.print("alloc shm name: {s}", .{fd_name});
    std.mem.writeInt(u32, fd_name[0..4], size.width % size.height * length, if (size.width % 2 == 0) .little else .big);
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
    const buffer: *wl.Buffer = try pool.createBuffer(0, @intCast(size.width), @intCast(size.height), @intCast(size.width * channels), .rgba8888);
    return .{ .buffer = buffer, .pixels = pixels[0..length] };
}
