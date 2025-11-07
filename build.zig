const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");
    // const wayland_dep = b.dependency("wayland", .{});
    // const wayland = b.addTranslateC(.{
    //     .root_source_file = wayland_dep.path("src/wayland-client.h"),
    //     .target = target,
    //     .optimize = optimize,
    // }).createModule();
    // wayland.addIncludePath(wayland_dep.path("src"));
    // wayland.addCSourceFiles(.{
    //     .files = &.{
    //         // "wayland-client.h",
    //         "wayland-egl.h",
    //     },
    // });

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = zigwin32 },
            // .{ .name = "wayland", .module = wayland },
        },
        .link_libc = true,
    });

    switch (target.result.os.tag) {
        .windows => {
            mod.linkSystemLibrary("user32", .{});
            mod.linkSystemLibrary("kernel32", .{});
        },
        else => {
            mod.linkSystemLibrary("glx", .{});
            mod.linkSystemLibrary("X11", .{});

            mod.linkSystemLibrary("wayland-client", .{});
        },
    }
}
