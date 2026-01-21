const std = @import("std");
const builtin = @import("builtin");
const posix = @import("posix.zig");

posix_platform: switch (builtin.os.tag) {
    .windows, .wasi => void,
    else => posix.Platform,
},

pub fn get(init: std.process.Init.Minimal) @This() {
    return .{
        .posix_platform = switch (builtin.os.tag) {
            .windows, .wasi => {},
            else => .get(init),
        },
    };
}
