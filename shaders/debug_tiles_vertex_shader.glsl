#version 460 core

out int vertexID_gs;

void main(void){
	vertexID_gs = gl_VertexID;
	gl_Position = vec4(0, 0, 0, 1);
}