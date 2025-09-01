#version 410 core

layout(location = 0) in vec3 l_pos;

out vec3 io_tex_coord;

uniform mat4 u_proj;
uniform mat4 u_view;

void main() {
    io_tex_coord = l_pos;
    gl_Position = (u_proj * u_view * vec4(l_pos, 1.0)).xyww; // Set z component to
    // w so after perspective division, z=1.0 and the skybox is at the far depth.
    // This allows drawing it last while passing depth tests only when no objects
    // are in front of it.
}
