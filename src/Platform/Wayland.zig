const std = @import("std");
const build_options = @import("build_options");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const vulkan = @import("../root.zig").vulkan;
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
    surface: *wl.Surface = undefined,
    xdg_surface: *xdg.Surface = undefined,
    xdg_toplevel: *xdg.Toplevel = undefined,
    event_queue: *wl.EventQueue = undefined,
    events: std.ArrayList(Platform.Window.Event) = .empty,
    configured: bool = false,
    running: bool = true,
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
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    window.platform = self;
    try self.io_manager.windows.pushBack(self.allocator, window);

    window.surface = try self.compositor.createSurface();
    window.xdg_surface = try self.wm_base.getXdgSurface(window.surface);
    window.xdg_toplevel = try window.xdg_surface.getToplevel();

    window.event_queue = try self.display.createQueue();
    window.surface.setQueue(window.event_queue);
    window.xdg_toplevel.setQueue(window.event_queue);

    window.xdg_surface.setListener(*Window, xdgSurfaceListener, window);
    window.xdg_toplevel.setListener(*Window, xdgToplevelListener, window);

    window.surface.commit();

    if (self.display.roundtrip() != .SUCCESS) return error.Roundtrip;
    if (!window.configured) return error.NoConfigureReceived;

    try window.events.append(self.allocator, .{ .resize = options.size });

    try windowSetProperty(context, platform_window, .{ .title = options.title });
    try windowSetProperty(context, platform_window, .{ .resize_policy = options.resize_policy });
    try windowSetProperty(context, platform_window, .{ .decorated = options.decorated });
}
fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    window.event_queue.destroy();
    window.xdg_toplevel.destroy();
    window.xdg_surface.destroy();
    window.surface.destroy();
}
fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    if (window.err) |err| return err;
    if (!window.running) return null;

    if (self.display.dispatchQueuePending(window.event_queue) != .SUCCESS) return error.DispatchQueuePending;

    return window.events.pop() orelse null;
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
            .surface = window.surface,
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
            window.surface.commit();
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
                io_manager.keyboard = null;
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
