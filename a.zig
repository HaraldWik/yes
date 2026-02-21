const std = @import("std");

pub const Interface = struct {
    count: f64 = 0,
    vtable: *const VTable,

    pub const VTable = struct {
        add: *const fn (*Interface, amount: f64) void,
        sub: *const fn (*Interface, amount: f64) void,
    };

    pub fn add(self: *@This(), amount: f64) void {
        self.vtable.add(self, amount);
    }

    pub fn sub(self: *@This(), amount: f64) void {
        self.vtable.sub(self, amount);
    }
};

pub const Implementation = struct {
    interface: Interface,
    function_call_count: usize = 0,

    pub const default: @This() = .{
        .interface = .{
            .vtable = &.{
                .add = add,
                .sub = sub,
            },
        },
    };

    pub fn add(interface: *Interface, amount: f64) void {
        const implementation: *@This() = @fieldParentPtr("interface", interface);
        implementation.function_call_count += 1;

        interface.count += amount;
    }
    pub fn sub(interface: *Interface, amount: f64) void {
        const implementation: *@This() = @fieldParentPtr("interface", interface);
        implementation.function_call_count += 1;

        interface.count -= amount;
    }
};

pub fn main() !void {
    var implementation: Implementation = .default;
    const interface = &implementation.interface;

    interface.add(3);
    interface.sub(2);
    interface.add(1);

    std.debug.print("count: {d}, func: {d}\n", .{ interface.count, implementation.function_call_count });
}
