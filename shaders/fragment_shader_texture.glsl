#version 410 core

in vec2 io_tex_coord;

uniform sampler2D u_texture1;
uniform sampler2D u_texture2;
uniform sampler2D u_cubemap;

out vec4 o_frag_color;

void main() {
	vec4 t1 = texture(u_texture1, io_tex_coord);
	vec4 t2 = texture(u_texture2, io_tex_coord);
	o_frag_color = mix(t1, t2, t2.a);
}
