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
#include "/generation.glsl"

shared float16_t densityCube[6*6*6];

void generateDensities(const TileDescriptor descriptor){
    for(int i=int(gl_LocalInvocationIndex); i < 6*6*6; i += 64){
        ivec3 localCoords = unwind3D(i, 6) - 1;
        ivec3 world_coords = ivec3(descriptor.coords) * 4 + localCoords;
        float density = generateDensity(world_coords);
        densityCube[i] = float16_t(density);
    }
    barrier();
}

float getDensity(ivec3 offset){
    return densityCube[wind3D(ivec3(gl_LocalInvocationID) + offset + 1, 6)];
}

vec3 getNormal(){
    vec3 N = vec3(0);
    N.x = getDensity(ivec3(+1, 0, 0)) - getDensity(ivec3(-1, 0, 0));
    N.y = getDensity(ivec3(0, +1, 0)) - getDensity(ivec3(0, -1, 0));
    N.z = getDensity(ivec3(0, 0, +1)) - getDensity(ivec3(0, 0, -1));
    return normalize(N);
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

    generateDensities(descriptor);
    const vec3 N = getNormal();

    // unwrap the tile index

    // x, y, z < atlas_tile_size
    // tile_id == x + y * atlas_tile_size + z * atlas_tile_size * atlas_tile_size

    const int atlas_tile_size = world.atlas_tile_size;
    int z = tile_id / (atlas_tile_size * atlas_tile_size);
    int y = (tile_id % (atlas_tile_size * atlas_tile_size)) / atlas_tile_size;
    int x = tile_id % atlas_tile_size;

    imageStore(image3D(world.atlas_normals.img), ivec3(x, y, z) * 4 + ivec3(gl_LocalInvocationID), vec4(N, 0));

}