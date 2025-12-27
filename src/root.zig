const std = @import("std");
const builtin = @import("builtin");

pub const Size = struct {
    width: T = 0,
    height: T = 0,

    pub const T = u32;

    pub fn toArray(self: @This()) [2]T {
        return .{ self.width, self.height };
    }
    pub fn toVec(self: @This()) @Vector(2, T) {
        return .{ self.width, self.height };
    }
    pub fn aspect(self: @This()) f32 {
        return @as(f32, @floatFromInt(self.width)) / @as(f32, @floatFromInt(self.height));
    }
};

pub fn Position(T: type) type {
    return struct {
        x: T = 0,
        y: T = 0,
        pub fn toArray(self: @This()) [2]T {
            return .{ self.x, self.y };
        }
        pub fn toVec(self: @This()) @Vector(2, T) {
            return .{ self.x, self.y };
        }
    };
}

pub const Monitor = @import("monitor/Monitor.zig");
pub const Window = @import("window/Window.zig");

pub const opengl = @import("opengl.zig");
pub const vulkan = @import("vulkan.zig");
/// only windows support currently (sort of)
pub const clipboard = @import("clipboard.zig");
/// only windows support currently
pub const file_dialog = @import("file_dialog.zig");
/// work in progress
pub const message_box = @import("message_box.zig");

pub const native = struct {
    pub const os = builtin.os.tag;

    pub const win32 = @import("win32");
    pub const posix = struct {
        pub const xkb = @import("xkb");
        pub const x11 = @import("x11");
        pub const wayland = struct {
            pub const client = @import("wayland");
            pub const xkg = @import("xdg");
            pub const decor = @import("decor");
        };
    };
};
