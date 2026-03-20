const std = @import("std");

const Key = @import("event.zig").Event.Key;

keys: [std.math.maxInt(std.meta.Tag(Key.Sym))]Key.State,

pub const empty: @This() = .{ .keys = @splat(Key.State.released) };

pub fn set(self: *@This(), key: Key.Sym, state: Key.State) void {
    self.keys[@intFromEnum(key)] = state;
}

pub fn get(self: @This(), key: Key.Sym) Key.State {
    return self.keys[@intFromEnum(key)];
}
