const std = @import("std");

pub const WaylandBackend = enum {
    none,
    libwayland,
};

pub const XBackend = enum {
    none,
    xcb,
    xpz,
    xlib,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const win32 = b.dependency("win32", .{}).module("win32");

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = win32 },
        },
    });

    const opengl_option = b.option(bool, "opengl", "Link with native OpenGL libs") orelse false;
    const wayland_backend_option = b.option(WaylandBackend, "wayland_backend", "Which Wayland backend to use by default") orelse .libwayland; // Linux
    const x_backend_option = b.option(XBackend, "x_backend", "Which X backend to use by default") orelse @as(XBackend, if (opengl_option) .xlib else .xcb); // Linux
    const glfw_option = b.option(bool, "glfw", "Allow usage of glfw backend") orelse false;

    if (glfw_option) {
        const glfw_dep = b.lazyDependency("glfw", .{}).?;
        const glfw = b.addTranslateC(.{
            .root_source_file = b.addWriteFiles().add("glfw.h",
                \\#include <GLFW/glfw3.h>
                \\#define GLFW_EXPOSE_NATIVE_X11
                \\#define GLFW_EXPOSE_NATIVE_WAYLAND
                \\#include <GLFW/glfw3native.h>
            ),
            .target = target,
            .optimize = optimize,
        });
        glfw.addIncludePath(glfw_dep.path("include"));
        const glfw_lib = b.lazyDependency("glfw_lib", .{}).?.artifact("glfw3");

        mod.addImport("glfw", glfw.createModule());
        mod.linkLibrary(glfw_lib);
        return;
    }

    switch (target.result.os.tag) {
        .windows => {},
        .macos => {},
        else => {
            switch (wayland_backend_option) {
                .none => {},
                .libwayland => addWayland(b, mod, target, optimize),
            }

            switch (x_backend_option) {
                .none => {},
                .xcb => addXcb(b, mod, target, optimize),
                .xlib => addXlib(b, mod, target, optimize),
                .xpz => {
                    const xpz = b.lazyDependency("xpz", .{ .target = target, .optimize = optimize }).?.module("xpz");
                    mod.addImport("xpz", xpz);
                },
            }

            addXkbcommon(b, mod, target, optimize, x_backend_option == .xcb);

            if (x_backend_option != .none and opengl_option) {
                mod.linkSystemLibrary("glx", .{});
            }
            if (wayland_backend_option != .none and opengl_option) {
                mod.linkSystemLibrary("EGL", .{ .weak = true });
                mod.linkSystemLibrary("wayland-egl", .{ .weak = true });
            }
        },
    }

    const options = b.addOptions();
    options.addOption(bool, "opengl", opengl_option);
    options.addOption(WaylandBackend, "wayland_backend", wayland_backend_option);
    options.addOption(XBackend, "x_backend", x_backend_option);
    options.addOption(bool, "glfw", glfw_option);
    mod.addOptions("build_options", options);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

pub fn addXcb(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const xcb_dep = b.lazyDependency("xcb", .{ .target = target, .optimize = optimize }).?;

    const xcb_translate_c = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("xcb.h",
            \\#include <xcb/xcb.h>
            \\#include <xcb/glx.h>
            \\#include <xcb/xinput.h>
            \\#include <xcb/xcb_icccm.h>
            \\#include <xcb/shm.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    xcb_translate_c.addIncludePath(xcb_dep.path("include/"));

    mod.addImport("xcb", xcb_translate_c.createModule());
    mod.linkLibrary(xcb_dep.artifact("xcb"));
}

pub fn addXlib(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const xlib_dep = b.lazyDependency("xlib", .{}).?;
    const xlib = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include <X11/Xlib.h>
            \\#include <X11/Xutil.h>
            \\#include <X11/Xatom.h>
            \\#include <X11/cursorfont.h>
            \\#include <X11/Xcursor/Xcursor.h>
            \\#include <X11/extensions/XInput2.h>
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
    xlib.linkSystemLibrary("Xi", .{});

    mod.addImport("xlib", xlib);
}

pub fn addWayland(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const Scanner = @import("wayland").Scanner;
    const scanner = Scanner.create(b, .{});

    const wayland_protocols = b.lazyDependency("wayland_protocols", .{}).?;

    const wayland = b.createModule(.{
        .root_source_file = scanner.result,
        .target = target,
        .optimize = optimize,
    });

    scanner.addCustomProtocol(wayland_protocols.path("stable/xdg-shell/xdg-shell.xml"));
    scanner.addCustomProtocol(wayland_protocols.path("unstable/xdg-decoration/xdg-decoration-unstable-v1.xml"));
    scanner.addCustomProtocol(wayland_protocols.path("staging/cursor-shape/cursor-shape-v1.xml"));
    scanner.addCustomProtocol(wayland_protocols.path("unstable/tablet/tablet-unstable-v2.xml"));

    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_shm", 1);
    scanner.generate("wl_seat", 4);
    scanner.generate("xdg_wm_base", 3);
    // scanner.generate("xdg_activation_v1", 1);
    scanner.generate("zxdg_decoration_manager_v1", 1);
    scanner.generate("wp_cursor_shape_manager_v1", 2);
    scanner.generate("zwp_tablet_manager_v2", 1);

    mod.addImport("wayland", wayland);
}

pub fn addXkbcommon(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, x11: bool) void {
    const xkbcommon_dep = b.lazyDependency("xkbcommon", .{
        .target = target,
        .optimize = optimize,
        .@"xkb-config-root" = "/usr/share/X11/xkb",

        .@"x-locale-root" = "/usr/share/X11/locale",
    }).?;
    const upstream = xkbcommon_dep.builder.dependency("libxkbcommon", .{});
    const xkbcommon = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("xkbcommon.h",
            \\#include <xkbcommon/xkbcommon.h>
            \\#include <xkbcommon/xkbcommon-keysyms.h>
            \\#include <xkbcommon/xkbcommon-x11.h>
        ),
        .target = target,
        .optimize = optimize,
    });

    xkbcommon.addIncludePath(upstream.path("include/"));
    mod.addImport("xkbcommon", xkbcommon.createModule());

    const libxkbcommon = xkbcommon_dep.artifact("xkbcommon");

    if (!x11) {
        mod.linkLibrary(libxkbcommon);
        return;
    }

    const libxkbcommon_x11_sources: []const []const u8 = &.{
        "src/x11/keymap.c",
        "src/x11/state.c",
        "src/x11/util.c",
        "src/context-priv.c",
        "src/keymap-priv.c",
        "src/atom.c",
    };

    libxkbcommon.root_module.addCSourceFiles(.{
        .root = upstream.path("."),
        .files = libxkbcommon_x11_sources,
    });

    const xcb_dep = b.lazyDependency("xcb", .{ .target = target, .optimize = optimize }).?;

    libxkbcommon.root_module.linkLibrary(xcb_dep.artifact("xcb"));
    libxkbcommon.root_module.addIncludePath(xcb_dep.path("include/"));

    mod.linkLibrary(libxkbcommon);
}
