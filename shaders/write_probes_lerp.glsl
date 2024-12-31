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

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

#include "/definitions.glsl"

uniform int probe_index_offset;
uniform int num_updated_probes;
uniform int raytracing_or_smoothing; // 0 for raytracing, 1 for smoothing

void main(){
	
	const int thread_index = int(gl_GlobalInvocationID.x);
	const int coeff = thread_index % 16;
	const int updated_probe_index = thread_index / 16;
	
	int probe_index = 0;
	if(raytracing_or_smoothing == 0){
		int num_probes = *world.num_valid_probes_for_raytracing;
		probe_index = world.valid_probes_for_raytracing[(probe_index_offset + updated_probe_index) % num_probes];
	}else{
		int num_probes = *world.num_valid_probes_for_rendering;
		probe_index = world.valid_probes_for_rendering[(probe_index_offset + updated_probe_index) % num_probes];
	}
	
	if(updated_probe_index > num_updated_probes){
		return;
	}

	const ProbeDescriptor desc = world.probes[probe_index];
	if(desc.status == 0){
		return;
	}
	
	// Step 1: overwrite the old values with the new values
	const f16vec4 value = world.updated_probes_values[updated_probe_index * 16 + coeff];
	
	world.probes_values[probe_index * 16 + coeff] = value;
	
	// Step 2: write the new values in the lerp texture
	layout(r32i) iimage3D tiles_occupancy = layout(r32i) iimage3D(world.occupancy.img);
	layout(rgba16f) image3D probes_lerp = layout(rgba16f) image3D(world.probes_lerp.img);

	for(int i=0; i<8; i++){
		const ivec3 c = desc.coords + unwind3D(i, 2) - ivec3(1);
		if(c.x >= 0 && c.y >= 0 && c.z >= 0 && 
			c.x < world.tiles_width && c.y < world.tiles_height && c.z < world.tiles_depth){
			
			const int atlasCoords = imageLoad(tiles_occupancy, c).r;
			if(atlasCoords >= 0){
				const int tile_index = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);
				const ivec2 C = unwind2D(tile_index, world.probes_lerp_half_size);
				imageStore(probes_lerp, ivec3(C, coeff) * 2 + ivec3(1) - unwind3D(i, 2), value);				
			}
		}
	}
	
}
