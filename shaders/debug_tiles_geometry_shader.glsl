#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shader_clock : enable
#extension GL_ARB_shading_language_include :   require
#extension GL_NV_shader_atomic_int64 : enable

#extension GL_KHR_shader_subgroup_basic : enable
#extension GL_KHR_shader_subgroup_arithmetic : enable
#extension GL_KHR_shader_subgroup_vote : enable
#extension GL_KHR_shader_subgroup_ballot : enable

#include "/definitions.glsl"

layout ( points ) in;
layout ( line_strip, max_vertices = 24 ) out;

in int vertexID_gs[];

uniform mat4 projectionView;
uniform int level;

void buildEdges(vec4 corners[8], int indices[24]){
	for(int i=0; i<12; i++){
		gl_Position = corners[indices[2*i+0]];
		EmitVertex();
		gl_Position = corners[indices[2*i+1]];
		EmitVertex();
		EndPrimitive();
	}
}

vec4 project3D(vec4 ws_pos){
	return projectionView * ws_pos;
}

void main(){

	vec3 minCorner, maxCorner;
	
	if(level == 0){
		const int u = vertexID_gs[0];
		const int w = world.tiles_width / 4;
		const int h = world.tiles_height / 4;
		const int d = world.tiles_depth / 4;
		// u = i + j * w + k * w * h

		int k = u / (w * h);
		int j = (u - k * w * h) / w;
		int i = (u - k * w * h - j * w);

		uint64_t mask = fetchCompressedOccupancy(0, u);
		if(mask == 0UL){
			return;
		}
	
		const ivec3 coords = ivec3(i, j, k);
		minCorner = toWorldCoords(coords * 16);
		maxCorner = toWorldCoords(coords * 16 + 16);
	}else if(level == 1){
		TileDescriptor desc = ArrayLoad(TileDescriptor, world.tiles, vertexID_gs[0], TileDescriptor(ivec3(0), 0));
		if(desc.status == 0){
			return;
		}

		const ivec3 coords = desc.coords;
		minCorner = toWorldCoords(coords * 4);
		maxCorner = toWorldCoords(coords * 4 + 4);
	}else{
		TileDescriptor desc = ArrayLoad(TileDescriptor, world.tiles, (vertexID_gs[0] / 64), TileDescriptor(ivec3(0), 0));
		if(desc.status == 0){
			return;
		}

		uint64_t mask = fetchCompressedOccupancy(1, vertexID_gs[0] / 64);
		ivec3 localCoords = unwind3D(vertexID_gs[0] % 64, 4);
		if(!checkMask(mask, localCoords)){
			return;
		}

		const ivec3 coords = desc.coords * 4 + localCoords;
		minCorner = toWorldCoords(coords);
		maxCorner = toWorldCoords(coords + 1);
	}


	vec4 corners[8];
	corners[0] = project3D(vec4(minCorner.x, minCorner.y, minCorner.z, 1.0f));
	corners[1] = project3D(vec4(maxCorner.x, minCorner.y, minCorner.z, 1.0f));
	corners[2] = project3D(vec4(minCorner.x, maxCorner.y, minCorner.z, 1.0f));
	corners[3] = project3D(vec4(maxCorner.x, maxCorner.y, minCorner.z, 1.0f));
	corners[4] = project3D(vec4(minCorner.x, minCorner.y, maxCorner.z, 1.0f));
	corners[5] = project3D(vec4(maxCorner.x, minCorner.y, maxCorner.z, 1.0f));
	corners[6] = project3D(vec4(minCorner.x, maxCorner.y, maxCorner.z, 1.0f));
	corners[7] = project3D(vec4(maxCorner.x, maxCorner.y, maxCorner.z, 1.0f));

	int indices[24] = {
		0,1,	2,3,	4,5,	6,7,
		0,2,	1,3,	4,6,	5,7,
		0,4,	1,5,	3,7,	2,6
	};

	buildEdges(corners, indices);
	
}