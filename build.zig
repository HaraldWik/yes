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

    const xlib_option = b.option(bool, "xlib", "Allow use of xlib platform") orelse true; // Linux
    const wayland_option = b.option(bool, "wayland", "Links with wayland libraries") orelse false; // Linux

    switch (target.result.os.tag) {
        .windows, .wasi => {},
        .macos => {},
        else => {
            if (xlib_option) addXlib(b, mod, target, optimize);
            // if (wayland_option) addWayland(b, mod, target, optimize);
            if (xlib_option or wayland_option) addXkbcommon(b, mod, target, optimize);
        },
    }

    const options = b.addOptions();
    options.addOption(bool, "xlib", xlib_option);
    options.addOption(bool, "wayland", wayland_option);
    mod.addOptions("build_options", options);
}

pub fn addXlib(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const xlib_dep = b.lazyDependency("xlib", .{}) orelse @panic("fetch lazy dependency \"xlib\"");
    const xlib = b.addTranslateC(.{
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
    xlib.addIncludePath(xlib_dep.path("include/X11/"));
    xlib.linkSystemLibrary("X11", .{});
    xlib.linkSystemLibrary("Xrandr", .{});
    xlib.linkSystemLibrary("glx", .{});
    mod.addImport("xlib", xlib);
}

pub fn addWayland(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const shimizu_build = @import("shimizu");
    const wayland_dep = b.dependency("wayland", .{});
    const wayland_protocols_dep = b.dependency("wayland-protocols", .{});

    const shimizu_dep = b.dependencyFromBuildZig(shimizu_build, .{
        .target = target,
        .optimize = optimize,
    });

    const wayland_unstable_dir = shimizu_build.generateProtocolZig(shimizu_dep.builder, shimizu_dep.artifact("shimizu-scanner"), .{
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

    // this is just so we get something as output
    const lib = b.addLibrary(.{
        .name = "wayland-unstable",
        .root_module = b.createModule(.{
            .root_source_file = wayland_unstable_dir.path(b, "root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "wire", .module = shimizu_dep.module("wire") },
                .{ .name = "core", .module = shimizu_dep.module("core") },
                .{ .name = "wayland-protocols", .module = shimizu_dep.module("wayland-protocols") },
            },
        }),
    });
    lib.installHeadersDirectory(wayland_unstable_dir, "wayland-unstable", .{
        .include_extensions = &.{".zig"},
    });
    b.installArtifact(lib);

    mod.linkLibrary(lib);
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
