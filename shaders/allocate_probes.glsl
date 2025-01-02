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

void allocateProbe(const ivec3 coords){

	const int current_value = imageLoad(layout(r32i) iimage3D(world.probes_occupancy.img), coords).r;
	if(current_value >= 0){
		return;
	}

	const int EMPTY = -1;
	const int LOCK = -2;
	
	const int result = imageAtomicCompSwap(layout(r32i) iimage3D(world.probes_occupancy.img), coords, EMPTY, LOCK);
	
	if(result == EMPTY){
		// we have the lock
		int probe_index = -1;
		
        // allocate one probe
        int free_probe_index = stack_pop((volatile int*)world.num_free_probes, 1);
        
        
        if(free_probe_index < 0){
            // we ran out of space, abort
            probe_index = -1;
        }else{
            // grab the index of the tile from the stack of free probes
            probe_index = ArrayLoad(int, world.free_probes_stack, free_probe_index, -1);
            // write -1 to show that the tile is no longer available
            ArrayStore(int, world.free_probes_stack, free_probe_index, -1);
        }
        
        // write the index of the probe or release the lock
		imageAtomicExchange(layout(r32i) iimage3D(world.probes_occupancy.img), coords, probe_index);
		
		if(probe_index != -1) {
			ArrayStore(ProbeDescriptor, world.probes, probe_index, ProbeDescriptor(ivec3(coords), 1));
		}
		
	}else if(result == LOCK){
		// someone else has the lock
	}else if(result >= 0){
		// already allocated
	}else{
		// should not happen
		reportBufferError(__LINE__, 0, 0, vec4(1, 2, 3, 4));
	}
	
}


void main(){
	
	const int tile_index = int(gl_GlobalInvocationID.x) / 8;
	const int corner_index = int(gl_GlobalInvocationID.x) % 8;

	if(tile_index >= world.maxTiles){
		return;
	}
	
	const TileDescriptor desc = ArrayLoad(TileDescriptor, world.tiles, tile_index, default_TileDescriptor);
	if(desc.status == 0){
		return;
	}
	
	const ivec3 coords = desc.coords + unwind3D(corner_index, 2);
	
	if(
		coords.x <= world.tiles_width &&
		coords.y <= world.tiles_height && 
		coords.z <= world.tiles_depth){
		allocateProbe(coords);
	}
	
	
}
