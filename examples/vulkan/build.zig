const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yes = b.dependency("yes", .{ .target = target, .optimize = optimize }).module("yes");

    const vulkan_dep = b.dependency("vulkan", .{ .target = target, .optimize = optimize });
    const vulkan = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("vulkan.c",
            \\#include <stdint.h>
            \\typedef struct {} Display;
            \\typedef unsigned int Window;
            \\typedef unsigned int VisualID;
            \\typedef uint32_t DWORD;
            \\typedef void* HANDLE;
            \\typedef const uint16_t* LPCWSTR;
            \\typedef HANDLE HMONITOR;
            \\typedef HANDLE HINSTANCE;
            \\typedef HANDLE HWND; 
            \\
            \\typedef struct _SECURITY_ATTRIBUTES {
            \\    DWORD  nLength;
            \\    void* lpSecurityDescriptor;
            \\    int    bInheritHandle; 
            \\} SECURITY_ATTRIBUTES;
            \\
            \\typedef struct xcb_connection_t {} xcb_connection_t; 
            \\typedef uint32_t xcb_window_t;
            \\typedef uint32_t xcb_visualid_t;
            \\
            \\#include <vulkan/vulkan.h>
            \\#include <vulkan/vulkan_win32.h>
            \\#include <vulkan/vulkan_wayland.h>
            \\#include <vulkan/vulkan_xlib.h>
            \\#include <vulkan/vulkan_xcb.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    vulkan.addIncludePath(vulkan_dep.path("include"));

    const exe = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "yes", .module = yes },
                .{ .name = "vulkan", .module = vulkan.createModule() },
            },
        }),
    });

    switch (target.result.os.tag) {
        .windows => exe.root_module.linkSystemLibrary("vulkan-1", .{}),
        else => exe.root_module.linkSystemLibrary("vulkan", .{}),
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}
