const std = @import("std");
const xpz = @import("xpz");
const Platform = @import("../Platform.zig");

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
    interface: Platform.Window = .{},
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
            .windowOpenglMakeCurrent = windowOpenglMakeCurrent,
            .windowOpenglSwapBuffers = windowOpenglSwapBuffers,
            .windowOpenglSwapInterval = windowOpenglSwapInterval,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
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
            .background_pixel = 0x00000000, // ARGB color
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

    try connection.reader.interface.fillMore();
    std.log.info("read: {any}", .{connection.reader.interface.buffer});

    try windowSetProperty(context, platform_window, .{ .title = options.title });
}

fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const connection = &self.*.connection;

    window.handle.destroy(connection);
}

fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
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
        .focus_in => .{ .focus = .enter },
        .focus_out => .{ .focus = .leave },
        .button_press, .button_release => |button| switch (button.button()) {
            .scroll_up => .{ .mouse_scroll = .{ .y = 1 } },
            .scroll_down => .{ .mouse_scroll = .{ .y = -1 } },
            .scroll_right => .{ .mouse_scroll = .{ .x = 1 } },
            .scroll_left => .{ .mouse_scroll = .{ .x = -1 } },

            else => .{
                .mouse_button = .{
                    .state = switch (event) {
                        .button_press => .pressed,
                        .button_release => .released,
                        else => unreachable,
                    },
                    .type = switch (button.button()) {
                        .left => .left,
                        .right => .right,
                        .middle => .middle,
                        .backward => .forward,
                        .forward => .backward,
                        else => unreachable,
                    },
                    .position = .{ .x = @intCast(button.x), .y = @intCast(button.y) },
                },
            },
        },
        else => null,
    };
}

fn windowSetProperty(context: *anyopaque, platform_window: *Platform.Window, property: Platform.Window.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const connection = &self.*.connection;

    switch (property) {
        .title => |title| {
            try window.handle.changeProperty(connection, .replace, .wm_name, .string, .@"8", title); // This is for setting on older systems, does not support unicode (emojis)
            try window.handle.changeProperty(connection, .replace, self.atom_table.net_wm_name, self.atom_table.utf8_string, .@"8", title); // Modern way, supports unicode
            try connection.flush();
        },
        .size => |size| _ = size,
        .position => |position| _ = position,
        .fullscreen => |fullscreen| _ = fullscreen,
        .maximize => |maximize| _ = maximize,
        .minimize => |minimize| _ = minimize,
        else => {},
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
