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

    _ = mod;

    // const options = b.addOptions();
    // const wayland_option = b.option(bool, "wayland", "Links with wayland libraries") orelse false; // Linux

    // options.addOption(bool, "wayland", wayland_option);

    // switch (target.result.os.tag) {
    //     .windows, .wasi => {},
    //     .macos => {},
    //     else => if (wayland_option) {
    //         addWayland(b, mod, target, optimize);
    //     },
    // }

    // mod.addOptions("build_options", options);
}

pub fn addWayland(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    _ = b;
    _ = mod;
    _ = target;
    _ = optimize;
}

pub fn addXkbcommon(b: *std.Build, mod: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const lib = b.lazyDependency("xkbcommon", .{
        .target = target,
        .optimize = optimize,

        .@"xkb-config-root" = "/usr/share/X11/xkb",
        .@"x-locale-root" = "/usr/share/X11/locale",
    }).?;
    const headers = b.lazyDependency("xkbcommon_headers", .{}).?;
    const c = b.addTranslateC(.{
        .root_source_file =
        // b.dependency("xkbcommon_headers", .{}).path("include/xkbcommon/xkbcommon.h"),
        b.addWriteFiles().add("xkb.c",
            \\#include <xkbcommon/xkbcommon.h>
            \\#include <xkbcommon/xkbcommon-keysyms.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    c.addIncludePath(headers.path("include/"));
    c.linkLibrary(lib.artifact("xkbcommon"));
    mod.addImport("xcb_common", c);
}
