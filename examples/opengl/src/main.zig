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
        .resize_policy = .{ .specified = .{
            .min_size = .{ .width = 300, .height = 200 },
        } },
        .surface_type = .{ .opengl = .{ .major = 3, .minor = 3 } },
        .decorated = false,
    });
    defer window.close(platform);
    try window.setAlwaysOnTop(platform, true);
    try window.setDecorated(platform, true);

    try yes.opengl.makeCurrent(platform, window);
    try yes.opengl.swapInterval(platform, window, 1);

    gl.load(yes.opengl.getProcAddress, false);
    gl.debug.set(null);

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

    var model_transform: nz.Transform3D(f32) = .{};
    var view_transform: nz.Transform3D(f32) = .{ .position = .{ 0.0, 0.0, -2.0 } };
    var projection_matrix: nz.Mat4x4(f32) = .identity;

    program.use();

    const model_loc = gl.c.glGetUniformLocation(@intFromEnum(program), "model");
    const view_loc = gl.c.glGetUniformLocation(@intFromEnum(program), "view");
    const projection_loc = gl.c.glGetUniformLocation(@intFromEnum(program), "projection");

    gl.c.glUniformMatrix4fv(model_loc, 1, 0, model_transform.toMat4x4().d[0..].ptr);
    gl.c.glUniformMatrix4fv(view_loc, 1, 0, view_transform.toMat4x4().d[0..].ptr);
    gl.c.glUniformMatrix4fv(projection_loc, 1, 0, projection_matrix.d[0..].ptr);

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

    gl.State.enable(.blend, null);
    gl.c.glBlendFunc(gl.c.GL_SRC_ALPHA, gl.c.GL_ONE_MINUS_SRC_ALPHA);

    main_loop: while (true) {
        const delta_time = getDeltaTime(io);

        while (try window.poll(platform)) |event| switch (event) {
            .close => break :main_loop,
            .resize => |size| {
                std.log.info("resize: {d}x{d}", .{ size.width, size.height });
                gl.draw.viewport(0, 0, size.width, size.height);

                projection_matrix = perspectiveOpenGl(f32, std.math.degreesToRadians(45), window.size.aspect(), 0.1, 100);
                std.log.debug("projection_matrix = {any}", .{projection_matrix.d});

                gl.c.glUniformMatrix4fv(projection_loc, 1, 0, projection_matrix.d[0..].ptr);
            },
            .key => |key| {
                if (key.state != .pressed) continue;
                switch (key.sym) {
                    .w => view_transform.position[2] += 50.0 * delta_time,
                    .s => view_transform.position[2] -= 50.0 * delta_time,
                    .a => view_transform.position[0] += 50.0 * delta_time,
                    .d => view_transform.position[0] -= 50.0 * delta_time,
                    else => {},
                }
                gl.c.glUniformMatrix4fv(view_loc, 1, 0, view_transform.toMat4x4().d[0..].ptr);
            },
            else => {},
        };

        gl.clear.color(0.0, 0.0, 0.0, 0.0);
        gl.clear.buffer(.{ .color = true, .depth = true });

        program.use();

        model_transform.rotation[1] = @mod(model_transform.rotation[1] + 30.0 * delta_time, 360.0);
        gl.c.glUniformMatrix4fv(model_loc, 1, 0, model_transform.toMat4x4().d[0..].ptr);

        gl.c.glBindVertexArray(vao);
        gl.draw.arrays(.triangles, 0, 3);

        try yes.opengl.swapBuffers(platform, window);
    }
}

pub fn getDeltaTime(io: std.Io) f32 {
    const Static = struct {
        var previous: ?std.Io.Timestamp = null;
    };
    if (Static.previous == null) {
        Static.previous = .now(io, .real);
        return getDeltaTime(io);
    }
    const now: std.Io.Timestamp = .now(io, .real);
    const duration = Static.previous.?.durationTo(now);
    Static.previous = now;
    return @as(f32, @floatFromInt(duration.toNanoseconds())) / 1_000_000_000.0;
}

pub fn perspectiveOpenGl(comptime T: type, fovy: T, aspect: T, near: T, far: T) nz.Mat4x4(f32) {
    const f = 1.0 / @tan(fovy / 2);
    const rangeInv = 1 / (near - far);

    return .new(.{
        f / aspect, 0, 0,                         0,
        0,          f, 0,                         0,
        0,          0, (near + far) * rangeInv,   -1,
        0,          0, near * far * rangeInv * 2, 0,
    });
}
