const std = @import("std");
const build_options = @import("build_options");

comptime {
    if (!build_options.wayland) @compileError("wayland backend not available unless build options wayland is set to true");
}
