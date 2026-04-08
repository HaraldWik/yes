const std = @import("std");
const opengl = @import("../opengl.zig");
const vulkan = @import("../root.zig").vulkan;
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");
const xcb = @import("xcb");

gpa: std.mem.Allocator,
connection: *xcb.xcb_connection_t,
screen: *xcb.xcb_screen_t,
atom_table: AtomTable,
windows: std.ArrayList(?*Window) = .empty,

pub const AtomTable = struct {
    utf8_string: xcb.xcb_atom_t,
    wm: struct {
        protocols: xcb.xcb_atom_t,
        name: xcb.xcb_atom_t,
    },
    net_wm: struct {
        name: xcb.xcb_atom_t,
    },

    pub fn load(connection: *xcb.xcb_connection_t) @This() {
        const utf8_string_cookie = cookie(connection, "UTF8_STRING");
        const wm_protocols_cookie = cookie(connection, "WM_PROTOCOLS");
        const wm_name_cookie = cookie(connection, "WM_NAME");

        const net_wm_name_cookie = cookie(connection, "_NET_WM_NAME");

        return .{
            .utf8_string = atom(connection, utf8_string_cookie),
            .wm = .{
                .protocols = atom(connection, wm_protocols_cookie),
                .name = atom(connection, wm_name_cookie),
            },
            .net_wm = .{
                .name = atom(connection, net_wm_name_cookie),
            },
        };
    }

    fn cookie(connection: *xcb.xcb_connection_t, name: []const u8) xcb.xcb_intern_atom_cookie_t {
        return xcb.xcb_intern_atom(connection, 0, @intCast(name.len), name.ptr);
    }

    fn atom(connection: *xcb.xcb_connection_t, c: xcb.xcb_intern_atom_cookie_t) xcb.xcb_atom_t {
        return xcb.xcb_intern_atom_reply(connection, c, null).?.*.atom;
    }
};

pub const Window = struct {
    interface: PlatformWindow = .{},
    id: xcb.xcb_window_t = 0,
    event_queue: std.Deque(PlatformWindow.Event) = .empty,
    wm_delete_atom: xcb.xcb_atom_t = 0,
};

pub fn init(gpa: std.mem.Allocator, minimal: std.process.Init.Minimal) !@This() {
    var screen_index: c_int = 0;
    const display_name = minimal.environ.getPosix("DISPLAY");
    const connection = xcb.xcb_connect(@ptrCast(display_name), &screen_index) orelse return error.Connect;

    const setup = xcb.xcb_get_setup(connection);
    var screen_it = xcb.xcb_setup_roots_iterator(setup);
    for (0..@intCast(screen_index)) |_| xcb.xcb_screen_next(&screen_it);
    const screen: *xcb.xcb_screen_t = screen_it.data orelse return error.XcbUnsupported;

    return .{
        .gpa = gpa,
        .connection = connection,
        .screen = screen,
        .atom_table = .load(connection),
    };
}

pub fn deinit(self: *@This()) void {
    self.windows.deinit(self.gpa);
    xcb.xcb_disconnect(self.connection);
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
            .openglGetProcAddress = opengl.glXGetProcAddress,
        },
    };
}

pub fn windowFromId(self: *@This(), id: xcb.xcb_window_t) ?struct { *Window, usize } {
    for (self.windows.items, 0..) |window, index| {
        if (window == null) continue;
        if (window.?.id == id) return .{ window.?, index };
    } else return null;
}

fn windowOpen(context: *anyopaque, platform_window: *PlatformWindow, options: PlatformWindow.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    for (self.windows.items, 0..) |other_window, index| {
        if (other_window != null) continue;
        self.windows.items[index] = window;
    } else try self.windows.append(self.gpa, window);

    window.id = xcb.xcb_generate_id(self.connection);

    const mask: u32 = xcb.XCB_CW_BACK_PIXEL | xcb.XCB_CW_EVENT_MASK;
    const values = [_]u32{
        self.screen.white_pixel,
        xcb.XCB_EVENT_MASK_EXPOSURE | xcb.XCB_EVENT_MASK_KEY_PRESS,
    };

    _ = xcb.xcb_create_window(
        self.connection,
        xcb.XCB_COPY_FROM_PARENT,
        window.id,
        self.screen.root,
        if (options.position) |position| @intCast(position.x) else 0,
        if (options.position) |position| @intCast(position.y) else 0,
        @intCast(options.size.width),
        @intCast(options.size.height),
        10,
        xcb.XCB_WINDOW_CLASS_INPUT_OUTPUT,
        self.screen.root_visual,
        mask,
        &values,
    );

    _ = xcb.xcb_map_window(self.connection, window.id);

    window.wm_delete_atom = xcb.xcb_intern_atom_reply(
        self.connection,
        xcb.xcb_intern_atom(self.connection, 0, "WM_DELETE_WINDOW".len, "WM_DELETE_WINDOW"),
        null,
    ).?.*.atom;

    // Tell X server that we want to receive WM_DELETE_WINDOW events
    _ = xcb.xcb_change_property(
        self.connection,
        xcb.XCB_PROP_MODE_REPLACE,
        window.id,
        self.atom_table.wm.protocols,
        4, // XA_ATOM = 4
        32,
        1,
        &window.wm_delete_atom,
    );

    try windowSetProperty(context, platform_window, .{ .title = options.title });

    _ = xcb.xcb_flush(self.connection);
}
fn windowClose(context: *anyopaque, platform_window: *PlatformWindow) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _, const window_index = self.windowFromId(window.id).?;
    self.windows.items[window_index] = null;

    window.event_queue.deinit(self.gpa);
    _ = xcb.xcb_destroy_window(self.connection, window.id);
}
fn windowPoll(context: *anyopaque, platform_window: *PlatformWindow) anyerror!?PlatformWindow.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    var out_event: ?PlatformWindow.Event = null;
    var event_target_id: xcb.xcb_window_t = 0;

    const generic_event: *xcb.xcb_generic_event_t = xcb.xcb_poll_for_event(self.connection) orelse return null;
    defer std.heap.c_allocator.destroy(generic_event);
    const event_type = generic_event.*.response_type & 0x7f;
    switch (event_type) {
        xcb.XCB_CLIENT_MESSAGE => {
            const event: *xcb.xcb_client_message_event_t = @ptrCast(generic_event);
            event_target_id = event.window;

            const target, _ = self.windowFromId(event.window).?;
            if (event.data.data32[0] == target.wm_delete_atom) {
                out_event = .close;
            }
        },
        xcb.XCB_EXPOSE => {
            const event: *xcb.xcb_expose_event_t = @ptrCast(generic_event);
            event_target_id = event.window;

            const size: PlatformWindow.Size = .{ .width = @intCast(event.width), .height = @intCast(event.height) };
            out_event = .{ .resize = size };
        },
        xcb.XCB_KEY_PRESS => {
            const event: *xcb.xcb_key_press_event_t = @ptrCast(generic_event);
            event_target_id = event.event;

            std.debug.print("key: {d}\n", .{event.detail});
            out_event = .close;
        },
        else => {},
    }

    if (out_event) |event| {
        if (window.id == event_target_id) return event else {
            const target, _ = self.windowFromId(event_target_id).?;
            try target.event_queue.pushBack(self.gpa, event);
        }
    }
    return windowPoll(context, platform_window);
}
fn windowSetProperty(context: *anyopaque, platform_window: *PlatformWindow, property: PlatformWindow.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    switch (property) {
        .title => |title| {
            _ = xcb.xcb_change_property(self.connection, xcb.XCB_PROP_MODE_REPLACE, window.id, self.atom_table.wm.name, xcb.XCB_ATOM_STRING, 8, @intCast(title.len), title.ptr);
            _ = xcb.xcb_change_property(self.connection, xcb.XCB_PROP_MODE_REPLACE, window.id, self.atom_table.net_wm.name, self.atom_table.utf8_string, 8, @intCast(title.len), title.ptr);
        },
        .size => {},
        .position => {},
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
        .cursor => {},
    }
    _ = xcb.xcb_flush(self.connection);
}
fn windowNative(context: *anyopaque, platform_window: *PlatformWindow) PlatformWindow.Native {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    return .{ .x11 = .{
        .display = self.connection,
        .window = @intCast(window.id),
        .screen = @intCast(self.screen.root),
    } };
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
    _ = window;

    // xcb.xcb_glx_make_current();
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
    // xcb.xcb_glx_swap_buffers(c: ?*struct_xcb_connection_t, context_tag: u32, drawable: u32)
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *PlatformWindow, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
    _ = interval;
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *PlatformWindow, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const vkCreateXcbSurfaceKHR: vulkan.Surface.CreateProc = @ptrCast(getProcAddress(instance, "vkCreateXcbSurfaceKHR") orelse return error.LoadVkCreateXlibSurfaceKHR);

    const create_info: vulkan.Surface.CreateInfo = .{ .xcb = .{
        .connection = self.connection,
        .window = window.id,
    } };

    var surface: ?*vulkan.Surface = null;
    if (vkCreateXcbSurfaceKHR(instance, &create_info, allocator, &surface) != .success) return error.VkCreateXlibSurfaceKHR;
    return surface orelse error.InvalidSurface;
}
