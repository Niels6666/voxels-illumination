#version 460 core

in vec2 position;
out vec2 tex_coords;

void main(void){
    tex_coords = vec2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
	gl_Position = vec4(position, 0, 1);
}