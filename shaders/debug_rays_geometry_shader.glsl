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
layout ( line_strip, max_vertices = 2 ) out;

in int vertexID_gs[];
out vec4 color;

uniform mat4 projectionView;
uniform int selected_probe;

void main(){

	const ProbeDescriptor desc = world.probes[selected_probe];
	if(desc.status == 0){
		return;
	}

	const vec3 coords = desc.coords * 4;
	const vec4 ray = world.probes_ray_dirs[vertexID_gs[0]];
	
	const bool invalid = ray.w == 0.0f;

	const vec4 v = world.probes_values[selected_probe * 16 + 0];
	
	if(vertexID_gs[0] == 0){
		reportBufferError(0, 0, 0, v);
	}
	
	const float validity_proportion = v.w;
	if(validity_proportion == 0){
		return;
	}
	
	vec4 c = invalid ? vec4(1, 0, 0, 1) : vec4(0, 1, 0, 1);

	color = c;

	gl_Position = projectionView * vec4(toWorldCoords(coords), 1.0f);
	EmitVertex();
	
	color = c;
	
	float d = invalid ? 10 : ray.w;

	gl_Position = projectionView * vec4(toWorldCoords(coords + ray.xyz * d), 1.0f);
	EmitVertex();

	EndPrimitive();
}
