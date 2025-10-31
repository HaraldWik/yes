const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // const windows = b.dependency("windows", .{});

    // const header = b.addTranslateC(.{
    //     .root_source_file = windows.path("include/win32/window.h"),
    //     .target = target,
    //     .optimize = optimize,
    //     .use_clang = false,
    //     .link_libc = true,
    // }).createModule();
    // header.linkSystemLibrary("c", .{});
    // header.addIncludePath(windows.path("include/win32/"));
    // header.addCMacro("_WIN64", "1");
    // header.addCMacro("INT64", "long long");
    // header.addCMacro("_MSC_VER", "1");

    const zigwin32 = b.dependency("zigwin32", .{}).module("win32");

    const mod = b.addModule("yes", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "win32", .module = zigwin32 },
        },
        .link_libc = true,
    });

    switch (target.result.os.tag) {
        .windows => {
            mod.linkSystemLibrary("user32", .{});
            mod.linkSystemLibrary("kernel32", .{});
        },
        else => {
            mod.linkSystemLibrary("glx", .{});
            mod.linkSystemLibrary("X11", .{});
        },
    }
}
