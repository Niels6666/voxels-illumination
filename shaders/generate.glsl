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

shared uvec2 local_masks;
shared int tile_index;

#include "/generation.glsl"

shared int8_t occupancyCube[6*6*6];
shared int sharedInsideCounts[2]; // any voxel that is considered inside in the 6*6*6 volume

uniform int GLOBAL_GENERATION_TILE_OFFSET;

bool testOccupancyCube(const ivec3 tile_coords){

    int insideCount = 0;
    for(int i=int(gl_LocalInvocationIndex); i < 6*6*6; i += 64){
        ivec3 localCoords = unwind3D(i, 6) - 1;
        ivec3 world_coords = tile_coords * 4 + localCoords;
        bool inside = testIsInside(world_coords);
        insideCount += int(inside);
        occupancyCube[i] = int8_t(inside);
    }
    insideCount = subgroupAdd(insideCount);

    if(gl_SubgroupInvocationID == 0){
        sharedInsideCounts[gl_SubgroupID] = insideCount;
    }

    barrier();

    return bool(occupancyCube[wind3D(ivec3(gl_LocalInvocationID)+1, 6)]);
}

void main(void){

    // 1 thread per voxel
    
    const int tile_idx = GLOBAL_GENERATION_TILE_OFFSET + int(gl_WorkGroupID.x);
    
    if(tile_idx >= world.tiles_width * world.tiles_height * world.tiles_depth){
    	return;
    }
    
    // tile_idx = x + y * tiles_width + z * tiles_width * tiles_height
    
    const int z = tile_idx / (world.tiles_width * world.tiles_height);
    const int y = (tile_idx - z * world.tiles_width * world.tiles_height) / world.tiles_width;
    const int x = tile_idx - z * world.tiles_width * world.tiles_height - y * world.tiles_width;
    
    const ivec3 world_coords = ivec3(x, y, z) * 4 + ivec3(gl_LocalInvocationID); // in [(0, 0, 0), (width, height, depth)[

    // Step 1:
    // Check if we are inside or outside

    const bool isInside = testOccupancyCube(ivec3(x, y, z));

    const uint local_mask = subgroupBallot(isInside).x;
    if(gl_SubgroupInvocationID == 0){
        local_masks[gl_SubgroupID] = local_mask;
    }

    barrier();
    
    if(gl_LocalInvocationIndex != 0){
    	return;
    }

    int totalInsideCount = sharedInsideCounts[0] + sharedInsideCounts[1]; 

    if(totalInsideCount == 0){
        // the tile is fully outside
        imageStore(layout(r32i) iimage3D(world.occupancy.img), ivec3(world_coords / 4), ivec4(-1, 0, 0, 0));
        return;
    }
    
    const bool onBoundary = any(equal(ivec2(x, z), ivec2(0))) || any(equal(ivec2(x, z), ivec2(
    			world.tiles_width-1, world.tiles_depth-1)));

    if(totalInsideCount == 6*6*6 && !onBoundary){
        // the tile is fully inside
        imageStore(layout(r32i) iimage3D(world.occupancy.img), ivec3(world_coords / 4), ivec4(-2, 0, 0, 0));
        
        const ivec3 coarseCoords = world_coords / 16;
        const int offset = coarseCoords.x + coarseCoords.y * (world.tiles_width/4) + coarseCoords.z * (world.tiles_width/4) * (world.tiles_height/4);
        const ivec3 subCoords = ivec3(world_coords / 4) % 4;
        const int n = subCoords.x + subCoords.y * 4 + subCoords.z * 16; // in [0, 63]
        setFlag(world.compressed_inside_terrain, offset, n);
        
        return;
    }
    
    // we are neither fully inside nor outside
    // we must allocate a new tile!

    // allocate one tile
    int free_tile_index = stack_pop((volatile int*)world.num_free_tiles, 1);
    
    
    if(free_tile_index < 0){
        // we ran out of space, abort
        tile_index = -1;
    }else{
        // grab the index of the tile from the stack of free tiles
        tile_index = ArrayLoad(int, world.free_tiles_stack, free_tile_index, 0);
        // write -1 to show that the tile is no longer available
        ArrayStore(int, world.free_tiles_stack, free_tile_index, -1);

        // write the occupancy masks
        ArrayStore(uvec2, world.compressed_atlas, tile_index, local_masks);

        // write the tile descriptor
        ArrayStore(TileDescriptor, world.tiles, tile_index, TileDescriptor(ivec3(world_coords / 4), 1));

        const int atlasCoords = packivec3(unwind3D(tile_index, world.atlas_tile_size));
        imageStore(layout(r32i) iimage3D(world.occupancy.img), ivec3(world_coords / 4), ivec4(atlasCoords, 0, 0, 0));
        
        // write the compressed_occupancy mask
        const ivec3 coarseCoords = world_coords / 16;
        const int offset = coarseCoords.x + coarseCoords.y * (world.tiles_width/4) + coarseCoords.z * (world.tiles_width/4) * (world.tiles_height/4);
        const ivec3 subCoords = ivec3(world_coords / 4) % 4;
        const int n = subCoords.x + subCoords.y * 4 + subCoords.z * 16; // in [0, 63]
        setFlag(world.compressed_occupancy, offset, n);
        
    }

}
