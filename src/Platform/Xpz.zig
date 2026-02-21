const std = @import("std");
const xpz = @import("xpz");
const Platform = @import("../Platform.zig");

reader_buffer: [512]u8 = undefined,
writer_buffer: [512]u8 = undefined,
reader: std.Io.net.Stream.Reader,
writer: std.Io.net.Stream.Writer,
client: xpz.Client,
atom_table: AtomTable,
resource_index: u32,

pub const AtomTable = struct {
    net_wm_name: xpz.Atom,
    utf8_string: xpz.Atom,

    pub fn load(client: xpz.Client) !@This() {
        return .{
            .net_wm_name = try .intern(client, false, xpz.Atom.net_wm.name),
            .utf8_string = try .intern(client, false, xpz.Atom.utf8_string),
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
        std.log.info("vendor: {s}", .{name});
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

pub fn init(self: *@This(), io: std.Io, minimal: std.process.Init.Minimal) !void {
    const address: std.Io.net.UnixAddress = try .init(xpz.Client.default_display_path);
    const stream = try address.connect(io);

    self.reader = stream.reader(io, &self.reader_buffer);
    self.writer = stream.writer(io, &self.writer_buffer);

    self.client = try .init(io, &self.reader.interface, &self.writer.interface, xpz.Client.Options{
        .auth = .{ .mit_magic_cookie_1 = .{ .xauthority = minimal.environ.getPosix(xpz.Client.Auth.@"MIT-MAGIC-COOKIE-1".XAUTHORITY).? } },
        .setup_listener = .{
            .vendor = setup_listener.vendor,
            .screen = setup_listener.currentScreen,
        },
    });

    self.atom_table = try .load(self.client);
}

pub fn deinit(self: @This(), io: std.Io) void {
    const stream = self.getStream();
    stream.close(io);
}

pub fn getStream(self: @This()) std.Io.net.Stream {
    const reader: *std.Io.net.Stream.Reader = @fieldParentPtr("interface", self.client.reader);
    return reader.stream;
}

pub fn platform(self: *@This()) Platform {
    return .{
        .ptr = @ptrCast(@alignCast(self)),
        .vtable = &.{
            .windowOpen = windowOpen,
            .windowClose = windowClose,
            .windowPoll = windowPoll,
            .windowSetTitle = windowSetTitle,
        },
    };
}

fn windowOpen(context: *anyopaque, platform_window: *Platform.Window, options: Platform.Window.OpenOptions) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const client = self.client;

    self.resource_index += 1;

    window.handle = client.generateId(xpz.Window, self.resource_index);
    try window.handle.create(client, .{
        .parent = client.root_screen.window,
        .width = @intCast(options.size.width),
        .height = @intCast(options.size.height),
        .border_width = 1,
        .visual_id = client.root_screen.visual_id,
        .attributes = .{
            .background_pixel = 0x00c2bb5b, // ARGB color
            // .events = .all,
            .events = .{
                .exposure = true,
                .key_press = true,
                .key_release = true,
                .keymap_state = true,
                .focus_change = true,
                .button_press = true,
                .button_release = true,
            },
        },
    });
    try window.handle.map(client);
    try client.writer.flush();
}

fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    window.handle.destroy(self.client);
}

fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));
    _ = window;

    const event = try xpz.Event.next(self.client) orelse return null;

    return switch (event) {
        .close => .close,
        .expose => |expose| .{ .resize = .{ .width = @intCast(expose.width), .height = @intCast(expose.height) } },
        .focus_in => .{ .focus = .enter },
        .focus_out => .{ .focus = .leave },
        else => null,
    };
}

fn windowSetTitle(context: *anyopaque, platform_window: *Platform.Window, title: []const u8) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    const client = self.client;

    try window.handle.changeProperty(client, .replace, .wm_name, .string, .@"8", title); // This is for setting on older systems, does not support unicode (emojis)
    try window.handle.changeProperty(client, .replace, self.atom_table.net_wm_name, self.atom_table.utf8_string, .@"8", title); // Modern way, supports unicode
}
