const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const win32 = b.dependency("win32", .{}).module("win32");
    const xpz = b.dependency("xpz", .{ .target = target, .optimize = optimize }).module("xpz");

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = win32 },
            .{ .name = "xpz", .module = xpz },
        },
    });

    const opengl_option = b.option(bool, "opengl", "Link with native OpenGL libs") orelse false;
    const xlib_option = b.option(bool, "xlib", "Allow use of xlib platform") orelse true; // Linux
    const libwayland_option = b.option(bool, "libwayland", "Links with wayland libraries") orelse true; // Linux

    switch (target.result.os.tag) {
        .windows => {},
        .macos => {},
        else => {
            if (xlib_option) addXlib(b, mod, target, optimize);
            if (libwayland_option) addWayland(b, mod, target, optimize);
            if (xlib_option or libwayland_option) addXkbcommon(b, mod, target, optimize);

            if (xlib_option and opengl_option) {
                mod.linkSystemLibrary("glx", .{});
            }
            if (libwayland_option and opengl_option) {
                mod.linkSystemLibrary("EGL", .{ .weak = true });
                mod.linkSystemLibrary("wayland-egl", .{ .weak = true });
            }
        },
    }

    const options = b.addOptions();
    options.addOption(bool, "opengl", opengl_option);
    options.addOption(bool, "xlib", xlib_option);
    options.addOption(bool, "libwayland", libwayland_option);
    mod.addOptions("build_options", options);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

pub fn addXlib(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const xlib_dep = b.lazyDependency("xlib", .{}) orelse @panic("fetch lazy dependency \"xlib\"");
    const xlib = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include <X11/Xlib.h>
            \\#include <X11/Xutil.h>
            \\#include <X11/Xatom.h>
            \\#include <X11/cursorfont.h>
            \\#include <X11/Xcursor/Xcursor.h>
            \\#include <GL/glx.h>
            \\#include <X11/extensions/Xrandr.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    xlib.addIncludePath(xlib_dep.path("include/X11/"));
    xlib.linkSystemLibrary("X11", .{});
    xlib.linkSystemLibrary("Xrandr", .{});
    xlib.linkSystemLibrary("Xcursor", .{});
    mod.addImport("xlib", xlib);
}

pub fn addWayland(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const Scanner = @import("wayland").Scanner;
    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{
        .root_source_file = scanner.result,
        .target = target,
        .optimize = optimize,
    });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addSystemProtocol("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml");
    scanner.addSystemProtocol("staging/cursor-shape/cursor-shape-v1.xml");
    scanner.addSystemProtocol("unstable/tablet/tablet-unstable-v2.xml");

    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_seat", 4);
    scanner.generate("xdg_wm_base", 3);
    scanner.generate("zxdg_decoration_manager_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 2);

    scanner.generate("zwp_tablet_manager_v2", 1);

    mod.addImport("wayland", wayland);
    mod.link_libc = true;
    mod.linkSystemLibrary("wayland-client", .{});
}

pub fn addXkbcommon(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const xkbcommon_dep = b.lazyDependency("xkbcommon", .{
        .target = target,
        .optimize = optimize,

        .@"xkb-config-root" = "/usr/share/X11/xkb",
        .@"x-locale-root" = "/usr/share/X11/locale",
    }).?;
    const xkbcommon_headers = b.lazyDependency("xkbcommon_headers", .{}).?;
    const xkbcommon = b.addTranslateC(.{
        .root_source_file =
        // b.dependency("xkbcommon_headers", .{}).path("include/xkbcommon/xkbcommon.h"),
        b.addWriteFiles().add("xkb.c",
            \\#include <xkbcommon/xkbcommon.h>
            \\#include <xkbcommon/xkbcommon-keysyms.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    xkbcommon.addIncludePath(xkbcommon_headers.path("include/"));
    xkbcommon.linkLibrary(xkbcommon_dep.artifact("xkbcommon"));
    mod.addImport("xkbcommon", xkbcommon);
}
