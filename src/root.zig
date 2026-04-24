pub const Platform = @import("Platform.zig");
pub const Window = @import("Window.zig");
pub const opengl = @import("opengl.zig");
pub const vulkan = @import("vulkan.zig");

pub const Clipboard = union(enum) {
    utf8: []const u8,
    files: []const []const u8,
    image: []const u8,
    raw: []const u8,
};
