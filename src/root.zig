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
    pub const x = @cImport({ // TODO: Remove c import
        @cInclude("X11/Xlib.h");
        @cInclude("X11/Xutil.h");
        @cInclude("X11/Xatom.h");
        @cInclude("GL/glx.h");
    });
    pub const wayland = @compileError("nothing here");
};

pub const Event = @import("event.zig").Union;
pub const Window = @import("window/Window.zig");

pub const GraphicsApi = enum {
    opengl,
    vulkan,
    none,
};
