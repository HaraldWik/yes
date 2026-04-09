const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const glfw = @import("glfw");
const vulkan = @import("../root.zig").vulkan;
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");

comptime {
    if (!build_options.glfw) @compileError("glfw unavailable, build option not true");
}

allocator: std.mem.Allocator,

pub const Window = struct {
    interface: PlatformWindow = .{},
    handle: *glfw.GLFWwindow = undefined,
    allocator: std.mem.Allocator = undefined,
    events: std.ArrayList(PlatformWindow.Event) = .empty,
    err: ?anyerror = null,
};

pub fn init(allocator: std.mem.Allocator) !@This() {
    _ = glfw.glfwInit();
    return .{ .allocator = allocator };
}

pub fn deinit(_: @This()) void {
    glfw.glfwTerminate();
}

pub fn platform(self: *@This()) Platform {
    return .{
        .ptr = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetProperty = windowSetProperty,
            .windowNative = windowNative,
            .windowFramebuffer = windowFramebuffer,
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
            .windowVulkanCreateSurface = windowVulkanCreateSurface,
            .openglGetProcAddress = @ptrCast(&glfw.glfwGetProcAddress),
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *PlatformWindow, options: PlatformWindow.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (options.surface_type) {
        .opengl => {
            glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
            glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
            glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE);
        },
        else => {
            glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, glfw.GLFW_NO_API);
        },
    }

    const title = try self.allocator.dupeSentinel(u8, options.title, 0);
    defer self.allocator.free(title);
    window.allocator = self.allocator;
    window.handle = glfw.glfwCreateWindow(@intCast(options.size.width), @intCast(options.size.height), title, null, null) orelse return error.CreateWindow;
    glfw.glfwSetWindowUserPointer(window.handle, window);

    _ = glfw.glfwSetFramebufferSizeCallback(window.handle, @ptrCast(&sizeCallback));
    _ = glfw.glfwSetWindowPosCallback(window.handle, @ptrCast(&positionCallback));
    _ = glfw.glfwSetWindowFocusCallback(window.handle, @ptrCast(&focusCallback));
    _ = glfw.glfwSetKeyCallback(window.handle, @ptrCast(&keyCallback));
    _ = glfw.glfwSetCursorPosCallback(window.handle, @ptrCast(&mouseMotionCallback));
    _ = glfw.glfwSetScrollCallback(window.handle, @ptrCast(&mouseScrollCallback));
    _ = glfw.glfwSetMouseButtonCallback(window.handle, @ptrCast(&mouseButtonCallback));

    try window.events.append(self.allocator, .{ .resize = options.size });
}
fn windowClose(context: *anyopaque, platform_window: *PlatformWindow) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    glfw.glfwDestroyWindow(window.handle);
    window.events.deinit(self.allocator);
}
fn windowPoll(context: *anyopaque, platform_window: *PlatformWindow) anyerror!?PlatformWindow.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;

    if (window.err) |err| return err;

    if (glfw.glfwWindowShouldClose(window.handle) == glfw.GLFW_TRUE) return .close;

    if (glfw.glfwGetKey(window.handle, glfw.GLFW_KEY_ESCAPE) == glfw.GLFW_PRESS) {
        glfw.glfwSetWindowShouldClose(window.handle, glfw.GLFW_TRUE);
    }

    glfw.glfwPollEvents();

    return window.events.pop();
}
fn windowSetProperty(context: *anyopaque, platform_window: *PlatformWindow, property: PlatformWindow.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (property) {
        .title => |title| {
            const title_dupe = try self.allocator.dupeSentinel(u8, title, 0);
            defer self.allocator.free(title_dupe);
            glfw.glfwSetWindowTitle(window.handle, title_dupe);
        },
        .size => |size| glfw.glfwSetWindowSize(window.handle, @intCast(size.width), @intCast(size.height)),
        .position => |position| glfw.glfwSetWindowPos(window.handle, @intCast(position.x), @intCast(position.y)),
        .resize_policy => |resize_policy| switch (resize_policy) {
            .resizable => |resizable| {
                _ = resizable;
            },
            .specified => |specified| {
                _ = specified;
            },
        },
        .fullscreen => {},
        .maximized => {},
        .minimized => {},
        .always_on_top => {},
        .floating => {},
        .decorated => {},
        .focused => {},
        .cursor => |cursor| {
            const cursor_mode: c_int = switch (cursor) {
                .arrow => glfw.GLFW_ARROW_CURSOR,
                .text => glfw.GLFW_IBEAM_CURSOR,
                .crosshair => glfw.GLFW_CROSSHAIR_CURSOR,
                .hand => glfw.GLFW_HAND_CURSOR,
                .resize_ns => glfw.GLFW_HRESIZE_CURSOR,
                .resize_ew => glfw.GLFW_VRESIZE_CURSOR,
                _ => |prong| @intCast(@intFromEnum(prong)),
                else => return,
            };
            glfw.glfwSetInputMode(window.handle, glfw.GLFW_CURSOR, cursor_mode);
        },
    }
}
fn windowNative(context: *anyopaque, platform_window: *PlatformWindow) PlatformWindow.Native {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    switch (builtin.os.tag) {
        .windows => {},
        .macos => {},
        else => {
            if (glfw.glfwGetWaylandDisplay()) |display| {
                return .{ .wayland = .{
                    .display = display,
                    .surface = glfw.glfwGetWaylandWindow(window.handle).?,
                    .compositor = 0,
                } };
            }

            if (glfw.glfwGetX11Display()) |display| {
                return .{ .x11 = .{
                    .display = display,
                    .window = glfw.glfwGetX11Window(window.handle),
                    .screen = 0,
                } };
            }
        },
    }
}
fn windowFramebuffer(context: *anyopaque, platform_window: *PlatformWindow) anyerror!PlatformWindow.Framebuffer {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;

    return .{ .pixels = undefined };
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    glfw.glfwMakeContextCurrent(window.handle);
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    glfw.glfwSwapBuffers(window.handle);
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *PlatformWindow, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
    glfw.glfwSwapInterval(@intCast(interval));
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *PlatformWindow, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = self;

    var surface: ?*vulkan.Surface = null;

    if (builtin.os.tag == .windows) {
        // TODO: add windows support
    }

    if (glfw.glfwGetWaylandDisplay()) |display| {
        const vkCreateWaylandSurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateWaylandSurfaceKHR") orelse return error.LoadVkCreateWaylandSurfaceKHR);

        const create_info: vulkan.Surface.CreateInfo = .{ .wayland = .{
            .display = display,
            .surface = glfw.glfwGetWaylandWindow(window.handle).?,
        } };

        if (vkCreateWaylandSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateWaylandSurfaceKHR;
    }

    if (glfw.glfwGetX11Display()) |display| {
        const vkCreateXlibSurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateXlibSurfaceKHR") orelse return error.LoadVkCreateXlibSurfaceKHR);

        const create_info: vulkan.Surface.CreateInfo = .{ .xlib = .{
            .display = display,
            .window = glfw.glfwGetX11Window(window.handle),
        } };

        if (vkCreateXlibSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateXlibSurfaceKHR;
    }

    return surface orelse error.InvalidSurface;
}

fn sizeCallback(glfw_window: *glfw.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    window.events.append(window.allocator, .{
        .resize = .{ .width = @intCast(width), .height = @intCast(height) },
    }) catch |err| {
        window.err = err;
    };
}

fn positionCallback(glfw_window: *glfw.GLFWwindow, x: c_int, y: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    window.events.append(window.allocator, .{
        .move = .{ .x = @intCast(x), .y = @intCast(y) },
    }) catch |err| {
        window.err = err;
    };
}

fn focusCallback(glfw_window: *glfw.GLFWwindow, focused: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    window.events.append(window.allocator, .{
        .focus = focused == 1,
    }) catch |err| {
        window.err = err;
    };
}

fn keyCallback(glfw_window: *glfw.GLFWwindow, key: c_int, scancode: c_int, action: c_int, _: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    _ = key;
    window.events.append(window.allocator, .{ .key = .{
        .state = if (action == glfw.GLFW_PRESS) .pressed else .released,
        .code = @intCast(scancode),
        .sym = .@"0",
    } }) catch |err| {
        window.err = err;
    };
}

fn mouseMotionCallback(glfw_window: *glfw.GLFWwindow, x: f64, y: f64) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    window.events.append(window.allocator, .{
        .mouse_motion = .{ .x = x, .y = y },
    }) catch |err| {
        window.err = err;
    };
}

fn mouseScrollCallback(glfw_window: *glfw.GLFWwindow, x: f64, y: f64) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    window.events.append(window.allocator, .{
        .mouse_scroll = if (x > 0) .{ .horizontal = x - 1 } else .{ .vertical = y },
    }) catch |err| {
        window.err = err;
    };
}

fn mouseButtonCallback(glfw_window: *glfw.GLFWwindow, button: c_int, action: c_int, _: c_int) callconv(.c) void {
    const window: *Window = @ptrCast(@alignCast(glfw.glfwGetWindowUserPointer(glfw_window)));
    window.events.append(window.allocator, .{ .mouse_button = .{
        .state = if (action == glfw.GLFW_PRESS) .pressed else .released,
        .button = switch (button) {
            glfw.GLFW_MOUSE_BUTTON_LEFT => .left,
            glfw.GLFW_MOUSE_BUTTON_RIGHT => .right,
            glfw.GLFW_MOUSE_BUTTON_MIDDLE => .middle,
            glfw.GLFW_MOUSE_BUTTON_4 => .backward,
            glfw.GLFW_MOUSE_BUTTON_5 => .forward,
            else => return,
        },
    } }) catch |err| {
        window.err = err;
    };
}
