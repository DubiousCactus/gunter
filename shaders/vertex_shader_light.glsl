#version 410 core

layout (location = 0) in vec3 l_pos;
layout (location = 1) in vec3 l_tex_coord;
layout (location = 2) in vec3 l_normal;

out vec3 io_normal;
out vec3 io_frag_w_pos;

uniform mat4 u_view;
uniform mat4 u_model;
uniform mat4 u_proj;

void main() {
	gl_Position = u_proj * u_view * u_model *vec4(l_pos, 1.0);
	io_normal = mat3(transpose(inverse(u_model))) * l_normal;
	io_frag_w_pos = vec3(u_model * vec4(l_pos, 1.0));
}
