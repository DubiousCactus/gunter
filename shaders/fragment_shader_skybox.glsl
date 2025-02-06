#version 410 core

out vec4 o_frag_color;
in vec3 io_tex_coord;

uniform samplerCube cubemap;


void main() {
	o_frag_color = texture(cubemap, io_tex_coord);
}
