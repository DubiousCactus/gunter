#version 410 core

in vec3 io_normal;     // This gets interpolated from the output vertices
in vec3 io_frag_w_pos; // This gets interpolated as well
in vec2 io_text_coords;
out vec4 o_frag_color;

struct Material {
  sampler2D diffuse;  // Color of the surface under diffuse lighting
  sampler2D specular; // Color of the surface under specular highlights
  float shininess;    // Scattering/radius of the specular hilights
};

struct SpotlLight {
  vec3 position;
  vec3 direction;
  float inner_cutoff_angle_cosine;
  float outer_cutoff_angle_cosine;

  vec3 ambient;
  vec3 diffuse;
  vec3 specular;

  float constant;
  float linear;
  float quadratic;
};

uniform Material u_material;
uniform SpotlLight u_spot_light;

uniform vec3 u_cam_pos;
uniform bool u_is_source;

void main() {
  if (u_is_source) {
    o_frag_color = vec4(1.0, 1.0, 1.0, 1.0);
  } else {
    vec3 normal = normalize(io_normal);
    vec3 incoming_light_dir = normalize(u_spot_light.position - io_frag_w_pos);
    vec3 view_dir = normalize(u_cam_pos - io_frag_w_pos);

    vec3 ambient = u_spot_light.ambient *
                   vec3(texture(u_material.diffuse, io_text_coords));

    float theta = dot(incoming_light_dir, normalize(-u_spot_light.direction));
    float epsilon = u_spot_light.inner_cutoff_angle_cosine -
                    u_spot_light.outer_cutoff_angle_cosine;
    float intensity = clamp(
        (theta - u_spot_light.outer_cutoff_angle_cosine) / epsilon, 0.0, 1.0);

    vec3 diffuse = max(dot(normal, incoming_light_dir), 0.0) *
                   vec3(texture(u_material.diffuse, io_text_coords)) *
                   u_spot_light.diffuse;
    vec3 specular =
        pow(max(dot(reflect(-incoming_light_dir, normal), view_dir), 0.0),
            u_material.shininess) *
        vec3(texture(u_material.specular, io_text_coords)) *
        u_spot_light.specular;

    float dist = length(io_frag_w_pos - u_spot_light.position);
    float attenuation =
        1.0 / (u_spot_light.constant + u_spot_light.linear * dist +
               u_spot_light.quadratic * pow(dist, 2));
    o_frag_color = vec4(ambient, 1.0) +
                   attenuation * intensity * vec4(diffuse + specular, 1.0);
  }
}
