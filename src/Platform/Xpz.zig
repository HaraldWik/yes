const std = @import("std");
const xpz = @import("xpz");
const opengl = @import("../opengl.zig");
const vulkan = @import("../vulkan.zig");
const Platform = @import("../Platform.zig");
const PlatformWindow = @import("../Window.zig");

connection: xpz.Connection,
root_screen: xpz.Screen,
atom_table: AtomTable,

pub const AtomTable = struct {
    net_wm_name: xpz.Atom,
    utf8_string: xpz.Atom,

    pub fn load(connection: *xpz.Connection) !@This() {
        const net_wm_name_request = try xpz.Atom.internUnflushed(connection, false, xpz.Atom.net_wm.name);
        const utf8_string_request = try xpz.Atom.internUnflushed(connection, false, xpz.Atom.utf8_string);

        const net_wm_name = (try net_wm_name_request.receiveReply(xpz.protocol.core.atom.intern.Reply)).value.atom;
        const utf8_string = (try utf8_string_request.receiveReply(xpz.protocol.core.atom.intern.Reply)).value.atom;

        return .{
            .net_wm_name = net_wm_name,
            .utf8_string = utf8_string,
        };
    }
};

pub const Window = struct {
    interface: PlatformWindow = .{},
    handle: xpz.Window = @enumFromInt(0),
};

pub const setup_listener = struct {
    pub fn vendor(user_data: ?*anyopaque, name: []const u8) !void {
        _ = user_data;
        std.log.info("server vendor: {s}", .{name});
    }

    pub fn currentScreen(user_data: ?*anyopaque, screen: xpz.Screen) !void {
        _ = user_data;
        std.log.info("screen: {d}, size: {d}x{d}, physical size: {d}x{d}mm, visual_id: {d}", .{
            @intFromEnum(screen.window),
            screen.width,
            screen.height,
            screen.width_mm,
            screen.height_mm,
            @intFromEnum(screen.visual_id),
        });
    }
};

pub fn init(allocator: std.mem.Allocator, io: std.Io, minimal: std.process.Init.Minimal) !@This() {
    var connection: xpz.Connection = try .connectUnix(allocator, io, xpz.Connection.default_address, .{});
    const root_screen = try connection.setupOptions(minimal, .{
        .setup_listener = .{
            .vendor = setup_listener.vendor,
            .screen = setup_listener.currentScreen,
        },
    });

    return .{
        .connection = connection,
        .root_screen = root_screen,
        .atom_table = try .load(&connection),
    };
}

pub fn deinit(self: *@This()) void {
    self.connection.disconnect();
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
            .openglGetProcAddress = undefined,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *PlatformWindow, options: PlatformWindow.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const connection = &self.*.connection;

    window.handle = @enumFromInt(connection.resource_id.next());
    try window.handle.create(connection, .{
        .parent = self.root_screen.window,
        .width = @intCast(options.size.width),
        .height = @intCast(options.size.height),
        .border_width = 1,
        .visual_id = self.root_screen.visual_id,
        .attributes = .{
            .background_pixel = 0xffffffff, // ARGB color
            // .events = .all,
            .events = .{
                .key_press = true,
                .key_release = true,
                .button_press = true,
                .button_release = true,
                .enter_window = true,
                .leave_window = true,
                .pointer_motion = true,
                // .pointer_motion_hint = true,
                .keymap_state = true,
                .exposure = true,
                .structure_notify = true,
                .substructure_notify = true,
                .substructure_redirect = true,
                .focus_change = true,
                .property_change = true,
                .colormap_change = true,
                .owner_grab_button = true,
            },
        },
    });
    try window.handle.map(&self.connection);
    try self.connection.flush();

    try windowSetProperty(context, platform_window, .{ .title = options.title });
}

fn windowClose(context: *anyopaque, platform_window: *PlatformWindow) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const connection = &self.*.connection;

    window.handle.destroy(connection);
}

fn windowPoll(context: *anyopaque, platform_window: *PlatformWindow) anyerror!?PlatformWindow.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = window;

    const connection = &self.*.connection;

    const event = (xpz.Event.next(connection) catch |err| return switch (err) {
        error.EndOfStream => .close,
        else => err,
    }) orelse return null;

    return switch (event) {
        .close => .close,
        .expose => |expose| .{ .resize = .{ .width = @intCast(expose.width), .height = @intCast(expose.height) } },
        .configure_notify => |notify| .{ .move = .{ .x = @intCast(notify.x), .y = @intCast(notify.y) } },
        .focus_in => .{ .focus = .focused },
        .focus_out => .{ .focus = .unfocused },
        .button_press, .button_release => |button| switch (button.button()) {
            .scroll_up => .{ .mouse_scroll = .{ .vertical = 1 } },
            .scroll_down => .{ .mouse_scroll = .{ .vertical = -1 } },
            .scroll_right => .{ .mouse_scroll = .{ .horizontal = 1 } },
            .scroll_left => .{ .mouse_scroll = .{ .horizontal = -1 } },

            else => .{
                .mouse_button = .{
                    .state = switch (event) {
                        .button_press => .pressed,
                        .button_release => .released,
                        else => unreachable,
                    },
                    .button = switch (button.button()) {
                        .left => .left,
                        .right => .right,
                        .middle => .middle,
                        .backward => .forward,
                        .forward => .backward,
                        else => unreachable,
                    },
                },
            },
        },
        .keymap_notify => |keymap| {
            std.log.info("keymap: {s}", .{keymap.keys});
            return null;
        },
        else => null,
    };
}
fn windowSetProperty(context: *anyopaque, platform_window: *PlatformWindow, property: PlatformWindow.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const connection = &self.*.connection;

    switch (property) {
        .title => |title| {
            try window.handle.changeProperty(connection, .replace, .wm_name, .string, .@"8", title); // This is for setting on older systems, does not support unicode (emojis)
            try window.handle.changeProperty(connection, .replace, self.atom_table.net_wm_name, self.atom_table.utf8_string, .@"8", title); // Modern way, supports unicode
            try connection.flush();
        },
        .resize_policy => {},
        .size => {},
        .position => {},
        .fullscreen => {},
        .maximized => {},
        .minimized => {},
        .always_on_top => {},
        .floating => {},
        .decorated => {},
        .focus => {},
        .cursor => {},
    }
}
fn windowFramebuffer(context: *anyopaque, platform_window: *PlatformWindow) anyerror!PlatformWindow.Framebuffer {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;

    std.log.info("no software rendering is currently not supported", .{});

    return undefined;
}
fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *PlatformWindow) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = window;
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

    _ = self;
    _ = window;
    _ = instance;
    _ = allocator;
    _ = getProcAddress;

    @panic("vulkan create surface not implemented");

    // const xcb_connection_t = extern struct {
    //     has_error: c_int = 0,
    //     fd: c_int,
    //     setup: *const xpz.protocol.core.setup.Reply,
    //     iolock: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER,

    //     out: extern struct {
    //         request: u64,
    //         completed: u64,
    //         maximum_request_length: u32,
    //         socket_closure: c_int,
    //     },

    //     in: extern struct {
    //         lock: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER,

    //         events: ?*anyopaque = null,
    //         replies: ?*anyopaque = null,

    //         request_expected: u64,
    //     },

    //     extensions: [*c]xcb_extension_data_t = null,

    //     xid_base: u32,
    //     xid_mask: u32,
    //     xid_last: u32,

    //     auth_info: xcb_auth_info_t = .{},
    //     shutdown: c_int,

    //     const xcb_extension_t = extern struct {
    //         name: [*:0]u8,
    //         global_id: c_int,
    //     };

    //     const xcb_query_extension_reply_t = extern struct {
    //         present: c_int,
    //         major_opcode: u8,
    //         first_event: u8,
    //         first_error: u8,
    //     };

    //     const xcb_extension_data_t = extern struct {
    //         ext: *xcb_extension_t,
    //         reply: xcb_query_extension_reply_t,
    //     };

    //     pub const xcb_auth_info_t = extern struct {
    //         namelen: c_int = 0,
    //         name: ?[*]u8 = null,
    //         datalen: c_int = 0,
    //         data: ?[*]u8 = null,
    //     };
    // };

    // const connection = self.connection;
    // var xcb_connection: xcb_connection_t = .{
    //     .fd = connection.writer.stream.socket.handle,
    //     .setup = &connection.setup_info.?,
    //     .out = .{
    //         .request = connection.sequence,
    //         .completed = connection.sequence,
    //         .maximum_request_length = connection.setup_info.?.maximum_request_length,
    //         .socket_closure = 1,
    //     },
    //     .xid_base = connection.resource_id.base,
    //     .xid_mask = connection.resource_id.mask,
    //     .xid_last = connection.resource_id.index,
    //     .in = .{
    //         .request_expected = connection.sequence + 1,
    //     },
    //     .shutdown = 0,
    // };

    // const create_info: vulkan.Surface.CreateInfo = .{ .xcb = .{
    //     .connection = @ptrCast(@alignCast(&xcb_connection)),
    //     .window = @intCast(@intFromEnum(window.handle)),
    // } };

    // var surface: ?*vulkan.Surface = undefined;
    // if (getProcAddress(instance, &create_info, allocator, &surface) != .success) return error.CreateSurfaceResult;
    // return surface orelse error.CreateSurface;
}
