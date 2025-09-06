#version 410 core

in vec3 io_normal; // This gets interpolated from the output vertices
in vec3 io_frag_w_pos; // This gets interpolated as well
in vec2 io_text_coords;
out vec4 o_frag_color;

uniform sampler2D u_texture;

void main() {
    o_frag_color = texture(u_texture, io_text_coords).rgba;
}
