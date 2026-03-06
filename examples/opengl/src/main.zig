const std = @import("std");
const builtin = @import("builtin");
const yes = @import("yes");
const gl = @import("opengl");

pub const vertex_source: [*:0]const u8 =
    \\#version 460 core
    \\layout(location = 0) in vec3 aPos;
    \\out vec3 vertexColor;
    \\
    \\void main() {
    \\    gl_Position = vec4(aPos, 1.0);
    \\    int i = gl_VertexID % 3;
    \\    if (i == 0) vertexColor = vec3(1.0, 0.0, 0.0);
    \\    else if (i == 1) vertexColor = vec3(0.0, 1.0, 0.0);
    \\    else vertexColor = vec3(0.0, 0.0, 1.0);
    \\}
;

pub const fragment_source: [*:0]const u8 =
    \\#version 460 core
    \\in vec3 vertexColor;
    \\out vec4 FragColor;
    \\
    \\void main() {
    \\    FragColor = vec4(vertexColor, 1.0);
    \\}
;

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
        .surface_type = .{ .opengl = .{ .major = 4, .minor = 6, .patch = 0 } },
    });
    defer window.close(platform);

    try yes.opengl.makeCurrent(platform, window);
    try yes.opengl.swapInterval(platform, window, 1);

    gl.load(yes.opengl.getProcAddress, false);
    gl.debug.set(null);

    if (gl.String.get(.version, null)) |version| std.log.info("OpenGL version: {s}", .{version});

    const vertex_shader: gl.Shader = .init(.vertex);
    defer vertex_shader.deinit();
    vertex_shader.source(vertex_source);
    try vertex_shader.compile();

    const fragment_shader: gl.Shader = .init(.fragment);
    defer fragment_shader.deinit();
    fragment_shader.source(fragment_source);
    try fragment_shader.compile();

    const program: gl.Program = try .init();
    defer program.deinit();
    program.attach(vertex_shader);
    program.attach(fragment_shader);
    try program.link();

    var color: [4]f32 = .{ 0.1, 0.5, 0.3, 1.0 };
    const color_step = 0.05;
    main_loop: while (true) {
        while (try window.poll(platform)) |event|
            switch (event) {
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

        gl.clear.buffer(.{ .color = true });
        gl.clear.color(color[0], color[1], color[2], color[3]);

        program.use();

        gl.draw.elements(.triangles, 3, u32, null);

        try yes.opengl.swapBuffers(platform, window);
    }
}
