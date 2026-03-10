const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");
const gl = @import("opengl");
const nz = @import("numz");

const vertex_shader_source = @embedFile("shaders/default.vert");
const fragment_shader_source = @embedFile("shaders/default.frag");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var cross_platform: yes.Platform.Cross = try .init(allocator, io, init.minimal);
    defer cross_platform.deinit();
    const platform = cross_platform.platform();

    var cross_window: yes.Platform.Cross.Window = .empty(platform);
    const window = cross_window.interface(platform);
    try window.open(platform, .{
        .title = "OpenGL Triangle",
        .size = .{ .width = 600, .height = 400 },
        .min_size = .{ .width = 300, .height = 200 },
        .max_size = .{ .width = 900, .height = 600 },
        .surface_type = .{ .opengl = .{ .major = 3, .minor = 3 } },
    });
    defer window.close(platform);
    try window.setAlwaysOnTop(platform, true);

    try yes.opengl.makeCurrent(platform, window);
    try yes.opengl.swapInterval(platform, window, 1);

    gl.load(yes.opengl.getProcAddress, false);

    if (gl.String.get(.version, null)) |version| std.log.info("OpenGL version: {s}", .{version});

    const vertex_shader: gl.Shader = .init(.vertex);
    vertex_shader.source(vertex_shader_source);
    try vertex_shader.compile();

    const fragment_shader: gl.Shader = .init(.fragment);
    fragment_shader.source(fragment_shader_source);
    try fragment_shader.compile();

    const program: gl.Program = try .init();
    defer program.deinit();
    program.attach(vertex_shader);
    program.attach(fragment_shader);
    try program.link();

    vertex_shader.deinit();
    fragment_shader.deinit();

    var vao: c_uint = 0;
    var vbo: c_uint = 0;
    gl.c.glGenVertexArrays(1, &vao);
    gl.c.glGenBuffers(1, &vbo);
    defer {
        gl.c.glDeleteBuffers(1, &vbo);
        gl.c.glDeleteVertexArrays(1, &vao);
    }

    gl.c.glBindVertexArray(vao);
    gl.c.glBindBuffer(gl.c.GL_ARRAY_BUFFER, vbo);

    program.use();

    gl.State.enable(.blend, null);
    gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

    var color: [4]f32 = .{ 0.1, 0.5, 0.3, 1.0 };
    const color_step = 0.05;
    main_loop: while (true) {
        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main_loop,
            .resize => |size| {
                std.log.info("resize: {d}x{d}", .{ size.width, size.height });
                gl.draw.viewport(0, 0, size.width, size.height);
            },
            .key => |key| switch (key.sym) {
                .a => color[1] = @mod(color[1] + color_step, 1.0),
                .d => color[1] = @mod(color[1] - color_step, 1.0),
                .w => color[2] = @mod(color[2] + color_step, 1.0),
                .s => color[2] = @mod(color[2] - color_step, 1.0),
                else => {},
            },
            else => {},
        };

        gl.clear.color(color[0], color[1], color[2], color[3]);
        gl.clear.buffer(.{ .color = true, .depth = true });

        gl.c.glBindVertexArray(vao);
        gl.draw.arrays(.triangles, 0, 3);

        try yes.opengl.swapBuffers(platform, window);
    }
}
