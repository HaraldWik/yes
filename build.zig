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

    const wayland_headers = b.dependency("wayland", .{});

    const wayland_scanner_cmd = b.addSystemCommand(&.{
        "wayland-scanner",
        "client-header",
        "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
    });
    const xdg_shell_client_protocol = wayland_scanner_cmd.addOutputFileArg("xdg-shell-client-protocol.h");

    const wayland = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("wayland.h",
            \\#include <wayland-client.h>
            // \\#include <wayland-egl.h>
            // \\#include <EGL/egl.h>
            // \\#include <xdg-shell-client-protocol.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    if (target.result.os.tag != .windows) {
        wayland.step.dependOn(&wayland_scanner_cmd.step);
        wayland.addIncludePath(xdg_shell_client_protocol.dirname());
        wayland.addIncludePath(wayland_headers.path("src/"));
    }

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = zigwin32 },
            .{ .name = "wayland", .module = wayland.createModule() },
        },
        .link_libc = true,
    });
    mod.addOptions("build_options", options);

    switch (target.result.os.tag) {
        .windows => {
            mod.linkSystemLibrary("user32", .{});
            mod.linkSystemLibrary("kernel32", .{});
            mod.linkSystemLibrary("opengl32", .{});
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
