#version 410 core

in vec2 texCoord;

uniform sampler2D texture1;
uniform sampler2D texture2;
uniform sampler2D cubemap;

out vec4 FragColor;

void main() {
	vec4 t1 = texture(texture1, texCoord);
	vec4 t2 = texture(texture2, texCoord);
	FragColor = mix(t1, t2, t2.a);
}
