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

vec3 computeDirectionalLight(DirectionalLight light, vec3 normal,
                             vec3 view_dir) {
  vec3 light_dir = normalize(-light.direction);
  vec3 diffuse = max(dot(normal, light_dir), 0.0) *
                 vec3(texture(u_material.diffuse, io_text_coords)) *
                 light.diffuse;
  vec3 ambient =
      light.ambient * vec3(texture(u_material.diffuse, io_text_coords));
  vec3 specular = pow(max(dot(reflect(-light_dir, normal), view_dir), 0.0),
                      u_material.shininess) *
                  vec3(texture(u_material.specular, io_text_coords)).r *
                  light.specular;
  return ambient + diffuse + specular;
}

vec3 computePointLight(PointLight light, vec3 normal, vec3 frag_pos,
                       vec3 view_dir) {
  vec3 light_dir = normalize(light.position - frag_pos);
  vec3 diffuse = max(dot(normal, light_dir), 0.0) *
                 vec3(texture(u_material.diffuse, io_text_coords)) *
                 light.diffuse;
  vec3 ambient =
      light.ambient * vec3(texture(u_material.diffuse, io_text_coords));
  vec3 specular = pow(max(dot(reflect(-light_dir, normal), view_dir), 0.0),
                      u_material.shininess) *
                  vec3(texture(u_material.specular, io_text_coords)).r *
                  light.specular;
  float dist = length(frag_pos - light.position);
  float attenuation = 1.0 / (light.constant + light.linear * dist +
                             light.quadratic * pow(dist, 2));
  return attenuation * (ambient + diffuse + specular);
}

vec3 computeSpotLight(SpotLight light, vec3 normal, vec3 frag_pos,
                      vec3 view_dir) {
  vec3 incoming_light_dir = normalize(light.position - frag_pos);
  vec3 ambient =
      light.ambient * vec3(texture(u_material.diffuse, io_text_coords));

  float theta = dot(incoming_light_dir, normalize(-light.direction));
  float epsilon =
      light.inner_cutoff_angle_cosine - light.outer_cutoff_angle_cosine;
  float intensity =
      clamp((theta - light.outer_cutoff_angle_cosine) / epsilon, 0.0, 1.0);

  vec3 diffuse = max(dot(normal, incoming_light_dir), 0.0) *
                 vec3(texture(u_material.diffuse, io_text_coords)) *
                 light.diffuse;
  vec3 specular =
      pow(max(dot(reflect(-incoming_light_dir, normal), view_dir), 0.0),
          u_material.shininess) *
      vec3(texture(u_material.specular, io_text_coords)).r * light.specular;

  float dist = length(frag_pos - light.position);
  float attenuation = 1.0 / (light.constant + light.linear * dist +
                             light.quadratic * pow(dist, 2));
  return ambient + attenuation * intensity * (diffuse + specular);
}

void main() {
  if (u_is_source) {
    o_frag_color = vec4(1.0, 1.0, 1.0, 1.0);
  } else {
    vec3 normal = normalize(io_normal);
    vec3 view_dir = normalize(u_cam_pos - io_frag_w_pos);

    // TODO: Optimize by precomputing reflections, dot products, and etc.

    vec3 total_light = computeDirectionalLight(u_dir_light, normal, view_dir);

    for (int i = 0; i < NR_POINT_LIGHTS; i++)
      total_light +=
          computePointLight(u_point_lights[i], normal, io_frag_w_pos, view_dir);

    total_light +=
        computeSpotLight(u_spot_light, normal, io_frag_w_pos, view_dir);

    o_frag_color = vec4(total_light, 1.0);

    // float near = 0.1;
    // float far = 100.0;
    //
    // float ndc = gl_FragCoord.z * 2.0 - 1.0; // Back to NDC
    // float linearDepth = (2.0 * near * far) / (far + near - ndc * (far -
    // near)); o_frag_color = vec4(vec3(linearDepth) / far, 1.0);
  }
}
