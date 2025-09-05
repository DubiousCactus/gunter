#version 410 core

in vec3 io_normal; // This gets interpolated from the output vertices
in vec3 io_frag_w_pos; // This gets interpolated as well
in vec2 io_text_coords;
out vec4 o_frag_color;

uniform vec3 u_cam_pos;
uniform samplerCube u_skybox;
uniform float u_refractive_index;
uniform float u_refraction_pct;

void main() {
    vec3 normal = normalize(io_normal);
    vec3 view_dir = normalize(u_cam_pos - io_frag_w_pos);
    vec3 reflection_vec = reflect(-view_dir, normal);
    vec3 refraction_vec = refract(view_dir, normal, 1.00 / u_refractive_index);
    vec3 reflection = texture(u_skybox, reflection_vec).rgb;
    vec3 refraction = texture(u_skybox, refraction_vec).rgb;
    o_frag_color = vec4((1 - u_refraction_pct) * reflection + u_refraction_pct * refraction, 1.0);
}
