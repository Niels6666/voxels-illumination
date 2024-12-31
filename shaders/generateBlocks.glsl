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


// generate one tile of the terrain
layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;

#include "/definitions.glsl"
#include "/render_common.glsl"


uniform uint64_t noiseTexHandle;

float random(ivec3 world_coords) {

    sampler3D NoiseTex = sampler3D(noiseTexHandle);

    // map voxel coordinates to [-1, 1]
    vec3 c = 2.0f * (vec3(world_coords) + 0.5f) / (4.0f * world.tiles_height) - 1.0f;

    float density = 0.0f;

    // Perlin's noise
    float amplitude = 0.3f;
    float frequency = 0.075f;
    
    for(int i=0; i<6; i++){
        density += amplitude * texture(NoiseTex, c * frequency).x;
        amplitude /= 1.457f;
        frequency *= 1.093;
    }

    return density;
}

uint generateBlockType(const ivec3 coords){
	const bool inside = testBlockSolid(coords);
	if(!inside){
		return BLOCK_AIR;
	}
	
	const bool inside_above = testBlockSolid(coords + ivec3(0,1,0));
	const bool inside_below = testBlockSolid(coords - ivec3(0,1,0));
	
	if(!inside_above){
		if(inside_below){
			return BLOCK_GRASS;
		}else{
			return BLOCK_STONE;
		}
	}
	
	const bool inside_above2 = testBlockSolid(coords + ivec3(0,2,0));
	const bool inside_above3 = testBlockSolid(coords + ivec3(0,3,0));
	
	if(!inside_above2 || !inside_above3){
		return BLOCK_DIRT;
	}
	
	if(random(coords) > 0.1f){
		return BLOCK_URANIUM;
	}
	
	return BLOCK_STONE;

}

void main(void){

    const int tile_id = int(gl_WorkGroupID.x);

    TileDescriptor descriptor = world.tiles[tile_id];

    if(descriptor.status == 0){
        return; // not allocated
    }

    const uint64_t mask = world.compressed_atlas[tile_id];
    const bool isInside = checkMask(mask, ivec3(gl_LocalInvocationID));
    const ivec3 world_coords = descriptor.coords * 4 + ivec3(gl_LocalInvocationID);

    const uint type = generateBlockType(world_coords);

    // unwrap the tile index

    // x, y, z < atlas_tile_size
    // tile_id == x + y * atlas_tile_size + z * atlas_tile_size * atlas_tile_size

    const int atlas_tile_size = world.atlas_tile_size;
    int z = tile_id / (atlas_tile_size * atlas_tile_size);
    int y = (tile_id % (atlas_tile_size * atlas_tile_size)) / atlas_tile_size;
    int x = tile_id % atlas_tile_size;

    imageStore(uimage3D(world.block_ids.img), ivec3(x, y, z) * 4 + ivec3(gl_LocalInvocationID), uvec4(type, 0, 0, 0));

}