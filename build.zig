const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

    const x11 = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#include <X11/Xlib.h>
            \\#include <X11/Xutil.h>
            \\#include <X11/Xatom.h>
            \\#include <GL/glx.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    x11.addIncludePath(b.dependency("x11", .{}).path("include/X11/"));

    const wayland = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("wayland.h",
            \\#include <wayland-client.h>
            \\#include <wayland-egl.h>
        ),
        .target = target,
        .optimize = optimize,
    }).createModule();
    wayland.addIncludePath(b.dependency("wayland", .{}).path("src/"));
    wayland.addIncludePath(b.dependency("wayland", .{}).path("egl/"));

    const xdg_scanner_h = b.addSystemCommand(&.{
        "wayland-scanner", "client-header", "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
    });
    const xdg_scanner_c = b.addSystemCommand(&.{
        "wayland-scanner", "private-code", "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml",
    });
    const xdg = b.addTranslateC(.{
        .root_source_file = xdg_scanner_h.addOutputFileArg("xdg-shell-client-protocol.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();
    xdg.addCSourceFile(.{ .file = xdg_scanner_c.addOutputFileArg("xdg-shell-protocol.c") });

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

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = switch (target.result.os.tag) {
            .windows => &.{
                .{ .name = "win32", .module = zigwin32 },
            },
            else => &.{
                .{ .name = "win32", .module = zigwin32 }, // just for lsp
                .{ .name = "x11", .module = x11 },
                .{ .name = "wayland", .module = wayland },
                .{ .name = "xdg", .module = xdg },
                .{ .name = "xkb", .module = xkbcommon_headers },
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
            mod.linkSystemLibrary("X11", .{});
            mod.linkSystemLibrary("glx", .{});

            mod.linkSystemLibrary("wayland-client", .{});
            mod.linkSystemLibrary("wayland-egl", .{});
            mod.linkSystemLibrary("egl", .{});
        },
    }
}
