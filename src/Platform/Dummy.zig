const vulkan = @import("../root.zig").vulkan;
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

fn windowSetProperty(context: *anyopaque, platform_window: *Platform.Window, property: Platform.Window.Property) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;

    scope.info("window set property: {s} {any}", .{ window.title, property });

    switch (property) {
        .title => window.title = property.title,
        .size => {},
        .position => {},
        .fullscreen => {},
        .maximize => {},
        .minimize => {},
        .always_on_top => {},
        .floating => {},
    }
}

fn windowOpenglMakeCurrent(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;

    scope.info("window opengl make current: ({d}) {s}", .{ window.index, window.title });
}
fn windowOpenglSwapBuffers(context: *anyopaque, platform_window: *Platform.Window) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    scope.info("window opengl swap buffers: ({d}) {s}", .{ window.index, window.title });
}
fn windowOpenglSwapInterval(context: *anyopaque, platform_window: *Platform.Window, interval: i32) anyerror!void {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    scope.info("window opengl swap interval: ({d}) {s}, interval: {}", .{ window.index, window.title, interval });
}
fn windowVulkanCreateSurface(context: *anyopaque, platform_window: *Platform.Window, instance: *vulkan.Instance, allocator: ?*const vulkan.AllocationCallbacks, getProcAddress: vulkan.Instance.GetProcAddress) anyerror!*vulkan.Surface {
    const self: *@This() = @ptrCast(@alignCast(context));
    const window: *Window = @alignCast(@fieldParentPtr("interface", platform_window));

    _ = self;
    _ = instance;
    _ = allocator;
    _ = getProcAddress;
    scope.info("window vulkan create surface: ({d}) {s})", .{ window.index, window.title });
    return undefined;
}
