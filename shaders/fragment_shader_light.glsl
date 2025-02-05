#version 410 core


out vec4 FragColor;

uniform bool isSource;
uniform vec3 lightColor;
uniform vec3 objColor;

void main() {
	if (isSource)
		FragColor = vec4(lightColor, 1.0);
	else
		FragColor = vec4(lightColor * objColor, 1.0);
}
