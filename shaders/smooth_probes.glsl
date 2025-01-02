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

const int PROBES_PER_GROUP = 4;

layout(local_size_x = PROBES_PER_GROUP*16, local_size_y = 1, local_size_z = 1) in;

#include "/definitions.glsl"
#include "/render_common.glsl"
#include "/PBR.glsl"

uniform int probe_index_offset;
uniform float SmoothnessWeight;
uniform float LearningRate;

shared int neighbors[PROBES_PER_GROUP][6];

void loadNeighborProbesIndices(const ProbeDescriptor desc, const int lane, const int group){
	layout(r32i) iimage3D probes_occupancy = layout(r32i) iimage3D(world.probes_occupancy.img);

	if(lane < 6){
		const ivec3 offsets[6] = {
			ivec3(+1, 0, 0),
			ivec3(-1, 0, 0),
			ivec3(0, +1, 0),
			ivec3(0, -1, 0),
			ivec3(0, 0, +1),
			ivec3(0, 0, -1),
		};
		const ivec3 c = desc.coords + offsets[lane];
		if(
			c.x >= 0 && c.y >= 0 && c.z >= 0 && 
			c.x <= world.tiles_width && c.y <= world.tiles_height && c.z <= world.tiles_depth)
		{
			neighbors[group][lane] = imageLoad(probes_occupancy, c).r;
		}else{
			neighbors[group][lane] = -1;
		}
	}
}

void main(){

	const int num_valid_probes_for_smoothing = *world.num_valid_probes_for_rendering;
	
	const int coeff = int(gl_GlobalInvocationID.x) % 16;
	const int probe_idx = int(gl_GlobalInvocationID.x) / 16;
	
	const int k = (probe_idx + probe_index_offset) % num_valid_probes_for_smoothing;
	const int probe_index = ArrayLoad(int, world.valid_probes_for_rendering, k, -1);

	const ProbeDescriptor desc = ArrayLoad(ProbeDescriptor, world.probes, probe_index, default_ProbeDescriptor);
	if(desc.status == 0){
		return;
	}
	
	const int group = probe_idx % PROBES_PER_GROUP;
	
	loadNeighborProbesIndices(desc, coeff, group);
	subgroupBarrier();
	
	const vec4 previous_value = ArrayLoad(f16vec4, world.probes_values, (probe_index * 16 + coeff), f16vec4(0.0f));
	
	float sum_weights = 1.0f;
	vec4 avg = vec4(previous_value) * sum_weights;
	for(int i=0; i<6; i++){
		if(neighbors[group][i] >= 0){
			const float w = SmoothnessWeight;
			avg += ArrayLoad(f16vec4, world.probes_values, (neighbors[group][i] * 16 + coeff), f16vec4(0.0f)) * w;
			sum_weights += w;
		}
	}
	avg /= sum_weights;
	
	const vec4 new_value = mix(previous_value, avg, LearningRate);
	
	ArrayStore(f16vec4, world.updated_probes_values, (probe_idx * 16 + coeff), f16vec4(new_value));

}
