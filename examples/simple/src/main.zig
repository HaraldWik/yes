const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");

// example args "zig build run -- --xdg=x11"
pub const UnixPlatform = union(enum) {
    xpz: yes.Platform.Xpz,
    wayland: yes.Platform.Wayland,

    pub fn init(io: std.Io, minimal: std.process.Init.Minimal) !@This() {
        const unix_session_type = yes.UnixSessionType.get(minimal) orelse .x11;
        std.log.info("unix session type: {t}", .{unix_session_type});

        var self: @This() = undefined;
        switch (unix_session_type) {
            .x11 => {
                self = .{ .xpz = undefined };
                try self.xpz.init(io, minimal);
            },
            .wayland => {
                self = .{ .wayland = .{} };
            },
            else => return error.UnsupportedUnixPlatform,
        }
        return self;
    }

    pub fn deinit(self: @This(), io: std.Io) void {
        switch (self) {
            .xpz => |xpz| xpz.deinit(io),
            .wayland => {},
        }
    }

    pub fn platform(self: *@This()) yes.Platform {
        return switch (self.*) {
            .xpz => self.xpz.platform(),
            .wayland => self.wayland.platform(),
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform = switch (builtin.os.tag) {
        .windows => try yes.Platform.Win32.get(allocator),
        else => try UnixPlatform.init(io, init.minimal),
    };
    defer switch (builtin.os.tag) {
        .windows => {},
        else => cross_platform.deinit(io),
    };

    const platform = cross_platform.platform();

    var cross_window: switch (builtin.os.tag) {
        .windows => yes.Platform.Win32.Window,
        else => yes.Platform.Xpz.Window,
    } = .{};
    const window = &cross_window.interface;
    try window.open(platform, .{
        .title = "Window 🇸🇪👺🌶️🫑",
        .size = .{ .width = 600, .height = 400 },
        .min_size = .{ .width = 200, .height = 300 },
    });
    defer window.close(platform);

    var fullscreen: bool = false;

    main: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main,
            .resize => |size| std.log.info("resize: {d} x {d}", .{ size.width, size.height }),
            .move => |position| std.log.info("move: {d} x {d}", .{ position.x, position.y }),
            .focus => |focus| {
                std.log.info("focus: {t}", .{focus});
            },
            .key => |key| {
                std.log.info("{t:<8} {t}", .{ key.state, key.sym });
                if (key.state == .released and key.sym == .enter)
                    try window.setTitle(platform, "Window! 👺🌶️🫑");
            },
            .mouse_move => {},
            .mouse_button => |button| {
                std.log.info("{t:<8} mouse button {t:<8} at {d} x {d}", .{ button.state, button.type, button.position.x, button.position.y });
                if (button.state == .pressed and button.type == .left)
                    try window.setTitle(platform, "Window! 👺🌶️🫑");
                if (button.state == .pressed and button.type == .right)
                    try window.setTitle(platform, "Window 🇸🇪");

                if (button.state == .released and button.type == .middle) {
                    fullscreen = !fullscreen;
                    try window.setFullscreen(platform, fullscreen);
                }
            },
            .mouse_scroll => |scroll| {
                std.log.info("mouse scroll: {t}: {d:2}", .{ scroll, switch (scroll) {
                    .x => scroll.x,
                    .y => scroll.y,
                } });
            },
        };
    }
}
