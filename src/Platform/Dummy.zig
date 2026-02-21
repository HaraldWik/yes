const Platform = @import("../Platform.zig");

window_count: usize = 0,

const scope = @import("std").log.scoped(.dummy);

pub const Window = struct {
    interface: Platform.Window = .{},
    index: usize = 0,
    title: []const u8 = "",
    poll_count: usize = 0,
};

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

    self.window_count += 1;

    window.index = self.window_count;
    window.title = options.title;

    scope.info("window open: ({d}) {s}", .{ window.index, options.title });
}

fn windowClose(context: *anyopaque, platform_window: *Platform.Window) void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    self.window_count -= 1;

    scope.info("window close: ({d}) {s}", .{ window.index, window.title });
}

fn windowPoll(context: *anyopaque, platform_window: *Platform.Window) anyerror!?Platform.Window.Event {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    window.poll_count += 1;

    scope.info("window poll: ({d}) {s}", .{ window.index, window.title });

    if (window.poll_count > 10) return .close;

    return null;
}

fn windowSetTitle(context: *anyopaque, platform_window: *Platform.Window, title: []const u8) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;

    const old_title = window.title;
    window.title = title;

    scope.info("window set title \"{s}\" -> \"{s}\"", .{ old_title, window.title });
}
