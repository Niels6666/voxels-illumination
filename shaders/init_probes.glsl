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

uniform uint64_t noiseTexHandle;

vec4 generateCoeffs(ivec3 world_coords) {

    sampler3D NoiseTex = sampler3D(noiseTexHandle);

    // map voxel coordinates to [-1, 1]
    vec3 c = 2.0f * (vec3(world_coords) + 0.5f) / (4.0f * vec3(world.tiles_height, world.tiles_width, world.tiles_depth)) - 1.0f;

    // Perlin's noise
    float amplitude = 1.0f;
    float frequency = 0.5f;
    
    vec4 value = vec4(0.0f);
    for(int i=0; i<6; i++){
        value += amplitude * (texture(NoiseTex, c * frequency)*2.0f - 1.0f);
        amplitude /= 2.457f;
        frequency *= 2.093;
    }

    return value;
}

void main(){
	
	const int probe_index = int(gl_GlobalInvocationID.x) / 16;
	const int coeff = int(gl_GlobalInvocationID.x) % 16;

	if(probe_index > world.maxTiles){
		return;
	}
	
	const ProbeDescriptor desc = world.probes[probe_index];
	if(desc.status == 0){
		return;
	}
	
	vec4 value = generateCoeffs(desc.coords * 4);
	
	if(coeff == 0){
		value = vec4(0.0f);
	}
	
	world.probes_values[probe_index * 16 + coeff] = f16vec4(value);
	
	layout(r32i) iimage3D tiles_occupancy = layout(r32i) iimage3D(world.occupancy.img);
	layout(rgba16f) image3D probes_lerp = layout(rgba16f) image3D(world.probes_lerp.img);

	for(int i=0; i<8; i++){
		const ivec3 c = desc.coords + unwind3D(i, 2) - ivec3(1);
		if(c.x >= 0 && c.y >= 0 && c.z >= 0 && 
			c.x < world.tiles_width && c.y < world.tiles_height && c.z < world.tiles_depth){
			
			const int atlasCoords = imageLoad(tiles_occupancy, c).r;
			const int tile_index = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);
			
			if(tile_index >= 0){
				const ivec2 C = unwind2D(tile_index, world.probes_lerp_half_size);
				imageStore(probes_lerp, ivec3(C, coeff) * 2 + ivec3(1) - unwind3D(i, 2), value);				
			}
		}
	}
	
	
}
