const std = @import("std");
const builtin = @import("builtin");

pub const opengl = @import("opengl.zig");
/// only windows support currently (sort of)
pub const clipboard = @import("clipboard.zig");
/// only windows support currently
pub const file_dialog = @import("file_dialog.zig");

pub const native = struct {
    pub const os = builtin.os.tag;

    pub const win32 = @import("win32");
    pub const x11 = @import("x11");
    pub const wayland = @compileError("nothing here");
};

pub const Event = @import("event.zig").Union;
pub const Window = @import("window/Window.zig");

pub const GraphicsApi = enum {
    opengl,
    vulkan,
    none,
};
