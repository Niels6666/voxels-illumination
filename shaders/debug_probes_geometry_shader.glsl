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
layout ( points, max_vertices = 1 ) out;

in int vertexID_gs[];
out vec4 color;

uniform mat4 projectionView;

void main(){

	const ProbeDescriptor desc = world.probes[vertexID_gs[0]];
	if(desc.status == 0){
		return;
	}

	const vec3 coords = toWorldCoords(desc.coords * 4);

	gl_Position = projectionView * vec4(coords.x, coords.y, coords.z, 1.0f);
	
	vec4 v = world.probes_values[vertexID_gs[0] * 16 + 0];
	
	color = vec4(v.www, 1);

	EmitVertex();
	EndPrimitive();
	
}

