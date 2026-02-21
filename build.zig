const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const win32 = b.dependency("win32", .{}).module("win32");
    const xpz = b.dependency("xpz", .{ .target = target, .optimize = optimize }).module("xpz");

    // const xkbcommon_headers = b.addTranslateC(.{
    //     .root_source_file =
    //     // b.dependency("xkbcommon_headers", .{}).path("include/xkbcommon/xkbcommon.h"),
    //     b.addWriteFiles().add("xkb.c",
    //         \\#include <xkbcommon/xkbcommon.h>
    //         \\#include <xkbcommon/xkbcommon-keysyms.h>
    //     ),
    //     .target = target,
    //     .optimize = optimize,
    // }).createModule();

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = win32 },
            .{ .name = "xpz", .module = xpz },
            // .{ .name = "xkbcommon", .module = xkbcommon_headers },
        },
    });

    _ = mod;
    // const options = b.addOptions();

    // switch (target.result.os.tag) {
    //     .windows, .wasi => {},
    //     .macos => {},
    //     else => {
    //         const xcb = b.option(bool, "xcb", "Links with xcb") orelse false;
    //         const wayland = b.option(bool, "wayland", "Links with wayland libraries") orelse false;

    //         options.addOption(bool, "xcb", xcb);
    //         options.addOption(bool, "wayland", wayland);

    //         if (xcb) mod.addImport("xcb", addXcb(b));
    //         if (wayland) mod.addImport("wayland", addWayland(b));

    //         if (xcb or wayland) {
    //             mod.link_libc = true;

    //             const xkbcommon = b.dependency("xkbcommon", .{
    //                 .target = target,
    //                 .optimize = optimize,

    //                 .@"xkb-config-root" = "/usr/share/X11/xkb",
    //                 .@"x-locale-root" = "/usr/share/X11/locale",
    //             });
    //             mod.addIncludePath(b.dependency("xkbcommon_headers", .{}).path("include/"));
    //             mod.linkLibrary(xkbcommon.artifact("xkbcommon"));
    //         }
    //     },
    // }

    // mod.addOptions("build_options", options);
}

pub fn addXcb(b: *std.Build) *std.Build.Module {
    _ = b;
    return undefined;
}

pub fn addWayland(b: *std.Build) *std.Build.Module {
    _ = b;
    return undefined;
}
