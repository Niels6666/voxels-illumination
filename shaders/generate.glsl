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

bool testOccupancyCube(){

    int insideCount = 0;
    for(int i=int(gl_LocalInvocationIndex); i < 6*6*6; i += 64){
        ivec3 localCoords = unwind3D(i, 6) - 1;
        ivec3 world_coords = ivec3(gl_WorkGroupID) * 4 + localCoords;
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

    const ivec3 world_coords = ivec3(gl_GlobalInvocationID); // in [(0, 0, 0), (width, height, depth)[

    // Step 1:
    // Check if we are inside or outside

    bool isInside = testOccupancyCube();

    uint local_mask = subgroupBallot(isInside).x;
    if(gl_SubgroupInvocationID == 0){
        local_masks[gl_SubgroupID] = local_mask;
    }

    barrier();

    int totalInsideCount = sharedInsideCounts[0] + sharedInsideCounts[1]; 

    if(totalInsideCount == 0){
        // the tile is fully outside
        if(gl_LocalInvocationIndex == 0){
            imageStore(layout(r32i) iimage3D(world.occupancy.img), ivec3(gl_WorkGroupID), ivec4(-1, 0, 0, 0));
        }
        return;
    }

    if(totalInsideCount == 6*6*6){
        // the tile is fully inside
        if(gl_LocalInvocationIndex == 0){
            imageStore(layout(r32i) iimage3D(world.occupancy.img), ivec3(gl_WorkGroupID), ivec4(-2, 0, 0, 0));
            
            ivec3 coarseCoords = ivec3(gl_WorkGroupID) / 4;
            int offset = coarseCoords.x + coarseCoords.y * (world.tiles_width/4) + coarseCoords.z * (world.tiles_width/4) * (world.tiles_height/4);
            ivec3 subCoords = ivec3(gl_WorkGroupID) % 4;
            int n = subCoords.x + subCoords.y * 4 + subCoords.z * 16; // in [0, 63]
            atomicOr(world.compressed_inside_terrain + offset, uint64_t(1UL) << n);
            
        }
        return;
    }

    // we are neither fully inside nor outside
    // we must allocate a new tile!

    if(gl_LocalInvocationIndex == 0){
        // allocate one tile
        int free_tile_index = stack_pop((volatile int*)world.num_free_tiles, 1);
        if(free_tile_index < 0){
            // we ran out of space, abort
            tile_index = -1;
        }else{
            // grab the index of the tile from the stack of free tiles
            tile_index = world.free_tiles_stack[free_tile_index];
            // write -1 to show that the tile is no longer available
            world.free_tiles_stack[free_tile_index] = -1;

            // write the occupancy masks
            ((uvec2*)world.compressed_atlas)[tile_index] = local_masks;

            // write the compressed_occupancy mask
    
            ivec3 coarseCoords = ivec3(gl_WorkGroupID) / 4;
            int offset = coarseCoords.x + coarseCoords.y * (world.tiles_width/4) + coarseCoords.z * (world.tiles_width/4) * (world.tiles_height/4);
            ivec3 subCoords = ivec3(gl_WorkGroupID) % 4;
            int n = subCoords.x + subCoords.y * 4 + subCoords.z * 16; // in [0, 63]
            atomicOr(world.compressed_occupancy + offset, uint64_t(1UL) << n);

            // write the tile descriptor
            world.tiles[tile_index] = TileDescriptor(ivec3(gl_WorkGroupID), 1);

            const int atlasCoords = packivec3(unwind3D(tile_index, world.atlas_tile_size));
            imageStore(layout(r32i) iimage3D(world.occupancy.img), ivec3(gl_WorkGroupID), ivec4(atlasCoords, 0, 0, 0));
        }
    }
    barrier();

    if(tile_index < 0){
        // we ran out of space, abort
        return;
    }

}
