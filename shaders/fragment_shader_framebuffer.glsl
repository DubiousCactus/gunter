#version 410 core

in vec3 io_normal; // This gets interpolated from the output vertices
in vec3 io_frag_w_pos; // This gets interpolated as well
in vec2 io_text_coords;
out vec4 o_frag_color;

struct Material {
    sampler2D diffuse; // Color of the surface under diffuse lighting
    sampler2D specular; // Color of the surface under specular highlights
    float shininess; // Scattering/radius of the specular hilights
};

struct DirectionalLight {
    vec3 direction;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;
};

struct PointLight {
    vec3 position;

    vec3 ambient;
    vec3 diffuse;
    vec3 specular;

    float constant;
    float linear;
    float quadratic;
};

struct SpotLight {
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

#define NR_POINT_LIGHTS 4
uniform DirectionalLight u_dir_light;
uniform PointLight u_point_lights[NR_POINT_LIGHTS];
uniform SpotLight u_spot_light;

uniform vec3 u_cam_pos;
uniform bool u_is_source;
uniform bool u_has_diffuse_texture;
uniform bool u_has_specular_texture;

uniform sampler2D u_framebuffer_texture;

void main() {
    o_frag_color = vec4(texture(u_framebuffer_texture, io_text_coords).rgb, 1.0);
}
