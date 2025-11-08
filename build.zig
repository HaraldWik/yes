const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opengl = b.option(bool, "opengl", "OpenGL") orelse true;
    const vulkan = b.option(bool, "vulkan", "Vulkan") orelse true;

    const options = b.addOptions();
    options.addOption(@TypeOf(opengl), "opengl", opengl);
    options.addOption(@TypeOf(vulkan), "vulkan", vulkan);

    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

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
    mod.addOptions("build_options", options);

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
