#version 300 es

vec2 positions[3] = vec2[3](
    vec2( 0.0,  0.5),
    vec2(-0.5, -0.5),
    vec2( 0.5, -0.5)
);

vec3 colors[3] = vec3[3](
    vec3(1.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 1.0)
);

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec3 frag_color;

void main() {
    vec4 pos = vec4(positions[gl_VertexID], 0.0, 1.0);
    gl_Position = projection * view * model * pos;
    frag_color = colors[gl_VertexID];
}