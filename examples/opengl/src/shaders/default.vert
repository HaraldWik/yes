#version 300 es
precision mediump float;

// Vertex attributes
layout(location = 0) in vec3 a_position; // xyz
layout(location = 1) in vec3 a_color;    // rgb

// Uniforms
uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

// Pass color to fragment shader
out vec3 v_color;

void main() {
    gl_Position = projection * view * model * vec4(a_position, 1.0);
    v_color = a_color;
}