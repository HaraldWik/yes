const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const win32 = b.dependency("win32", .{}).module("win32");

    const x11 = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include <X11/Xlib.h>
            \\#include <X11/Xutil.h>
            \\#include <X11/Xatom.h>
            \\#include <GL/glx.h>
            \\#include <X11/extensions/Xrandr.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    x11.addIncludePath(b.dependency("x11", .{}).path("include/X11/"));
    x11.linkSystemLibrary("X11", .{});
    x11.linkSystemLibrary("Xrandr", .{});
    x11.linkSystemLibrary("glx", .{});

    const xkbcommon = b.dependency("xkbcommon", .{
        .target = target,
        .optimize = optimize,

        .@"xkb-config-root" = "/usr/share/X11/xkb",
        .@"x-locale-root" = "/usr/share/X11/locale",
    });
    const xkbcommon_headers = b.addTranslateC(.{
        .root_source_file =
        // b.dependency("xkbcommon_headers", .{}).path("include/xkbcommon/xkbcommon.h"),
        b.addWriteFiles().add("xkb.c",
            \\#include <xkbcommon/xkbcommon.h>
            \\#include <xkbcommon/xkbcommon-keysyms.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    xkbcommon_headers.addIncludePath(b.dependency("xkbcommon_headers", .{}).path("include/"));
    xkbcommon_headers.linkLibrary(xkbcommon.artifact("xkbcommon"));

    const egl = b.addTranslateC(.{
        .root_source_file = b.dependency("egl", .{}).path("api/EGL/egl.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    }).createModule();
    egl.addIncludePath(b.dependency("egl", .{}).path("api/"));
    egl.linkSystemLibrary("egl", .{});

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = switch (target.result.os.tag) {
            .windows => &.{
                .{ .name = "win32", .module = win32 },
            },
            else => &.{
                .{ .name = "win32", .module = win32 }, // NOTE: Just for lsp on linux

                .{ .name = "xkb", .module = xkbcommon_headers },

                .{ .name = "x11", .module = x11 },

                .{ .name = "egl", .module = egl },
            },
        },
        .link_libc = true,
    });

    switch (target.result.os.tag) {
        .windows => {
            mod.linkSystemLibrary("user32", .{});
            mod.linkSystemLibrary("kernel32", .{});
            mod.linkSystemLibrary("opengl32", .{});
        },
        else => {
            buildWayland(b, mod, target, optimize);
        },
    }
}

pub fn buildWayland(b: *std.Build, module: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shimizu_build = @import("shimizu");

    const wayland_dep = b.dependency("wayland", .{});
    const wayland_protocols_dep = b.dependency("wayland-protocols", .{});

    const shimizu_dep = b.dependencyFromBuildZig(shimizu_build, .{
        .target = target,
        .optimize = optimize,
    });

    const shimizu_scanner = shimizu_dep.artifact("shimizu-scanner");
    const wayland_protocols_generate_result = shimizu_build.generateProtocolZig(b, shimizu_scanner, .{
        .output_directory_name = "wayland-unstable",
        .source_files = &.{
            wayland_protocols_dep.path("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"),
        },
        .interface_versions = &.{
            .{ .interface = "zxdg_decoration_manager_v1", .version = 1 },
        },
        .imports = &.{
            .{ .file = wayland_dep.path("protocol/wayland.xml"), .import_string = "@import(\"core\")" },
            .{ .file = wayland_protocols_dep.path("stable/xdg-shell/xdg-shell.xml"), .import_string = "@import(\"wayland-protocols\").xdg_shell" },
        },
    });

    const wayland_protocols_module = b.addModule("wayland-protocols", .{
        .root_source_file = wayland_protocols_generate_result.output_directory.?.path(b, "root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "wire", .module = shimizu_dep.module("wire") },
            .{ .name = "core", .module = shimizu_dep.module("core") },
        },
    });

    module.addImport("shimizu", shimizu_dep.module("shimizu"));
    module.addImport("wayland-protocols", wayland_protocols_module);
}
