
#version 410 core

layout(location = 0) in vec3 l_pos;
layout(location = 1) in vec2 l_text_coords;

out vec2 io_text_coords;

void main() {
    gl_Position = vec4(l_pos, 1.0);
    io_text_coords = l_text_coords;
}
