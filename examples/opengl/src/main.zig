const std = @import("std");
const yes = @import("yes");
const gl = @import("opengl");

var vertices = [_]f32{
    // x,    y,    z
    -0.5, -0.5, 0.0, // Bottom-left
    0.5, -0.5, 0.0, // Bottom-right
    0.0, 0.5, 0.0, // Top
};

var indices = [_]u32{
    0, 1, 2,
};

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

pub fn main() !void {
    const window: yes.Window = try .open(.{
        .title = "Title",
        .size = .{ .width = 900, .height = 600 },
        // .resizable = false,
        .api = .{ .opengl = .{} }, // Don't forget to set to OpenGL
    });
    defer window.close();

    gl.load(yes.opengl.getProcAddress, true);
    gl.debug.set(null);

    if (gl.String.get(.version, null)) |version| std.debug.print("GL version: {s}\n", .{version});

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

    const vao: gl.Vao = try .init();
    const vbo: gl.Buffer = try .init();
    const ebo: gl.Buffer = try .init();
    defer vao.deinit();
    defer vbo.deinit();
    defer ebo.deinit();

    vbo.bufferData(.static_draw, &vertices);
    ebo.bufferData(.static_draw, &indices);

    vao.vertexAttribute(0, 0, 3, f32, false, 0);

    vao.vertexBuffer(vbo, 0, 0, 3 * @sizeOf(f32));
    vao.elementBuffer(ebo);

    try yes.opengl.swapInterval(window, 1);

    var color: [4]f32 = .{ 0.1, 0.5, 0.3, 1.0 };
    const color_step = 0.05;

    main_loop: while (true) {
        while (try window.poll()) |event| {
            switch (event) {
                .close => break :main_loop,
                .resize => |size| {
                    std.debug.print("Resize: {d}x{d}\n", .{ size.width, size.height });
                    gl.draw.viewport(0, 0, size.width, size.height);
                },
                .key_up => |key| switch (key) {
                    .a => color[1] = @mod(color[1] + color_step, 1.0),
                    .d => color[1] = @mod(color[1] - color_step, 1.0),
                    .w => color[2] = @mod(color[2] + color_step, 1.0),
                    .s => color[2] = @mod(color[2] - color_step, 1.0),
                    else => {},
                },
                else => {},
            }
        }

        gl.clear.buffer(.{ .color = true });
        gl.clear.color(color[0], color[1], color[2], color[3]);

        program.use();
        vao.bind();

        gl.draw.elements(.triangles, indices.len, u32, null);

        try yes.opengl.swapBuffers(window);
    }
}
