#version 410 core

in vec3 io_normal; // This gets interpolated from the output vertices
in vec3 io_frag_w_pos; // This gets interpolated as well
out vec4 o_frag_color;

struct Material {
	vec3 ambient; // Basically the surface's color
	vec3 diffuse; // Color of the surface under diffuse lighting, typically the ambient color
	vec3 specular; // Color of the surface under specular highlights
	float shininess; // Scattering/radius of the specular hilights
};

struct Light {
	vec3 position;
	vec3 ambient;
	vec3 diffuse;
	vec3 specular;
};

uniform Material u_material;
uniform Light u_light;

uniform vec3 u_cam_pos;
uniform bool u_is_source;

void main() {
	if (u_is_source) {
		o_frag_color = vec4(1.0, 1.0, 1.0, 1.0);
	} else {
		vec3 normal = normalize(io_normal);
		vec3 light_dir = normalize(u_light.position - io_frag_w_pos);
		vec3 view_dir = normalize(u_cam_pos - io_frag_w_pos);

		vec3 ambient = u_material.ambient * u_light.ambient;
		vec3 diffuse = max(dot(normal, light_dir), 0.0) * u_material.diffuse *
			u_light.diffuse;
		vec3 specular = pow(max(dot(reflect(-light_dir, normal), view_dir), 
			0.0), u_material.shininess) * u_material.specular *
			u_light.specular;
		o_frag_color = vec4(ambient + diffuse + specular, 1.0);
	}
}
