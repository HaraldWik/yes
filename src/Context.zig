const std = @import("std");
const builtin = @import("builtin");
const posix = @import("posix.zig");

posix_platform: posix.Platform = .x11,

pub fn get(init: std.process.Init.Minimal) @This() {
    return .{
        .posix_platform = switch (builtin.os.tag) {
            .windows, .wasi => .x11,
            else => .get(init),
        },
    };
}
