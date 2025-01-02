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
#include "/render_common.glsl"
#include "/PBR.glsl"

void main(){
	
	const int probe_index = int(gl_GlobalInvocationID.x);
	
	bool ok_for_rendering = true;
	bool ok_for_raytracing = true;

	if(probe_index < world.maxTiles){
		const ProbeDescriptor desc = ArrayLoad(ProbeDescriptor, world.probes, probe_index, default_ProbeDescriptor);
	
		if(desc.status == 0){
			ok_for_rendering = ok_for_raytracing = false;
		}else{
			const ivec3 start = ivec3(desc.coords * 4);
			int outside_count=0;
			for(int i=0; i<8; i++){
				ivec3 c = start - unwind3D(i, 2);
				outside_count += int(c.x < 0 || c.y < 0 || c.z < 0 || !testBlockSolid(c));
			}
			
			ok_for_raytracing = outside_count > 4;
			
			//if(ok_for_raytracing) ok_for_rendering = false;
		}
	}else{
		ok_for_rendering = ok_for_raytracing = false;
	}
	
	subgroupBarrier();
	
	uint valid_for_rendering_mask = subgroupBallot(ok_for_rendering).x;
	uint valid_for_raytracing_mask = subgroupBallot(ok_for_raytracing).x;
	
	uint valid_for_rendering_count = subgroupBallotBitCount(uvec4(valid_for_rendering_mask, 0, 0, 0));
	uint valid_for_raytracing_count = subgroupBallotBitCount(uvec4(valid_for_raytracing_mask, 0, 0, 0));
	
	if(valid_for_rendering_count == 0){
		return;
	}
	
	if(gl_SubgroupInvocationID == 0){
		if(valid_for_rendering_count > 0)
			valid_for_rendering_count = atomicAdd(world.num_valid_probes_for_rendering, (int)valid_for_rendering_count);
		if(valid_for_raytracing_count > 0)
			valid_for_raytracing_count = atomicAdd(world.num_valid_probes_for_raytracing, (int)valid_for_raytracing_count);
	}
	
	valid_for_rendering_count = subgroupBroadcast(valid_for_rendering_count, 0);
	valid_for_raytracing_count = subgroupBroadcast(valid_for_raytracing_count, 0);
	
	valid_for_rendering_count += subgroupBallotExclusiveBitCount(uvec4(valid_for_rendering_mask, 0, 0, 0));
	valid_for_raytracing_count += subgroupBallotExclusiveBitCount(uvec4(valid_for_raytracing_mask, 0, 0, 0));
	
	if(ok_for_rendering){
		ArrayStore(int, world.valid_probes_for_rendering, int(valid_for_rendering_count), probe_index);
	}
	if(ok_for_raytracing){
		ArrayStore(int, world.valid_probes_for_raytracing, int(valid_for_raytracing_count), probe_index);
	}
	
	
}
