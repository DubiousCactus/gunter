#version 410 core

layout (location = 0) in vec3 l_pos;


out vec3 io_tex_coord;

uniform mat4 u_proj;
uniform mat4 u_view;

void main() {
	io_tex_coord = l_pos;
	gl_Position = (u_proj * u_view * vec4(l_pos, 1.0)).xyww;
}

