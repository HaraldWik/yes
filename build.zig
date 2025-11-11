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

    // const xdg = b.addTranslateC(.{
    //     .root_source_file = if (target.result.os.tag != .windows) b.path("include/xdg-shell-client-protocol.h") else b.addWriteFiles().add("c.h", ""),
    //     .target = target,
    //     .optimize = optimize,
    // }).createModule();
    // if (target.result.os.tag != .windows) {
    //     xdg.linkSystemLibrary("wayland-client", .{});
    //     xdg.addCSourceFile(.{ .file = b.path("include/xdg-shell-protocol.c") });
    // }

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = zigwin32 },
            // .{ .name = "xdg", .module = xdg },
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
            if (opengl) {
                mod.linkSystemLibrary("wayland-egl", .{});
                mod.linkSystemLibrary("egl", .{});
                mod.linkSystemLibrary("GLESv2", .{});
            }
        },
    }
}
