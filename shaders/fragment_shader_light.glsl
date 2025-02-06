#version 410 core

in vec3 io_normal; // This gets interpolated from the output vertices
in vec3 io_frag_w_pos; // This gets interpolated as well
out vec4 o_frag_color;

uniform bool u_is_source;
uniform vec3 u_light_color;
uniform vec3 u_obj_color;
uniform vec3 u_light_pos;

uniform float u_ambient_factor;

void main() {
	vec3 normal = normalize(io_normal);
	vec3 light_dir = normalize(u_light_pos - io_frag_w_pos);
	vec3 diffuse = max(dot(normal, light_dir), 0.0) * u_light_color;
	if (u_is_source)
		o_frag_color = vec4(u_light_color, 1.0);
	else
		o_frag_color = vec4((u_ambient_factor + diffuse) *  u_obj_color, 1.0);
}
