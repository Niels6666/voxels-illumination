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

const int num_samples = 128;

layout(local_size_x = num_samples, local_size_y = 1, local_size_z = 1) in;

#include "/definitions.glsl"
#include "/render_common.glsl"
#include "/PBR.glsl"

uniform mat4 random_rotation;
uniform int probe_index_offset;
uniform vec3 sunDir;
uniform vec3 sunLight;
uniform float LearningRate;

shared vec3 shared_betas[gl_NumSubgroups][16];
shared int shared_sumHitRays[gl_NumSubgroups];
shared int shared_sumRaysInsideTerrain[gl_NumSubgroups];

vec3 computeRadiance(vec3 start, vec3 ray, out float t_voxel) {
	t_voxel = 1.0f / 0.0f;
	vec3 radiance = vec3(0.0f);
	
    const vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);
    float tmin, tmax;
    bool hitBox = rayVSbox(start, 1.0f / ray, vec3(0.0f), maxCorner, tmin, tmax);
    if(hitBox){
		tmin = max(tmin, 0.0f);
		
		bvec3 last_step;
		int iterations = 0;
		uvec3 cell = trace(start, ray, tmin, tmax, t_voxel, iterations, last_step);
		if(!isinf(t_voxel)){
			const vec3 voxel_hit_pos = start + ray * t_voxel;
			
			const int packedAtlasCoords = texelFetch(isampler3D(world.occupancy.tex), ivec3(cell >> 2u), 0).x;
			const ivec3 atlasCoords = unpackivec3(packedAtlasCoords) * 4 + ivec3(cell & 3u);
			const int voxel_type = texelFetch(isampler3D(world.block_ids.tex), atlasCoords, 0).x;
			
			const vec3 normal = -sign(ray) * vec3(last_step);
			
			const BlockData data = ArrayLoad(BlockData, world.block_types, voxel_type, default_BlockData);
			const vec4 albedo_emission = data.albedo_emission_strength / 255.0f;
			const vec2 roughness_metallic = (data.roughness_metallic / 255.0f).xy;
			const vec3 albedo = vec3(albedo_emission);
			const float roughness = roughness_metallic.x;
			const float metallic = roughness_metallic.y;
			const float emission_strength = albedo_emission.w;
			
			const float attenuation_drop = 0.0f;
			const float attenuation = 1.0f / max(1.0f, attenuation_drop * t_voxel*t_voxel);

			radiance = PBR(voxel_hit_pos, normal, ray, albedo, roughness, metallic, emission_strength);
			radiance *= attenuation;
			radiance = max(radiance, vec3(0.0f));
		}
    }
	
	if(isinf(t_voxel)){
		if(testSunHitBox(ray, sunDir)){
			radiance = sunLight;
		}else{
			radiance = getSkyRadiance(ray, sunDir);
		}
	}
	return radiance;
}

void computeCoefficients(const vec3 ray, const vec3 radiance){

	const float x = ray.x, y = ray.y, z = ray.z;
	
	const float Ys[16] = {
	    1.0f,
	
	    x,
	    y,
	    z,
	
	    (x*y),
	    (y*z),
	    (3.0f*z*z - 1.0f),
	    (x*z),
	    (x*x-y*y),
	
	    y * (3.0f * x*x - y*y),
	    (x*y*z),
	    y * (5.0f*z*z - 1.0f),
	    z * (5.0f*z*z - 3.0f),
	    x * (5.0f*z*z - 1.0f),
	    z * (x*x - y*y),
	    x * (x*x - 3.0f*y*y),
	};

	for(int i=0; i<16; i++){
		const vec3 sum = subgroupAdd(radiance * Ys[i] * SH_COEFFS[i]);
		if(gl_SubgroupInvocationID == 0){
			shared_betas[gl_SubgroupID][i] = sum;
		}
	}
}

void main(){

	const int num_valid_probes_for_raytracing = *world.num_valid_probes_for_raytracing;
	
	const int k = (int(gl_WorkGroupID.x) + probe_index_offset) % num_valid_probes_for_raytracing;
	const int probe_index = ArrayLoad(int, world.valid_probes_for_raytracing, k, -1);

	const ProbeDescriptor desc = ArrayLoad(ProbeDescriptor, world.probes, probe_index, default_ProbeDescriptor);
	if(desc.status == 0){
		return;
	}
	
	// Step 1: trace rays
	const vec3 start = vec3(desc.coords * 4);
	const vec3 ray = mat3(random_rotation) * vec3(ArrayLoad(vec4, world.probes_ray_dirs, int(gl_LocalInvocationID.x), vec4(0)));
	const vec3 offset_start = start + ray * 0.01f;
	const bool isRayInsideTerrain = offset_start.x >= 0.0f && offset_start.y >= 0.0f && offset_start.z >= 0.0f && testBlockSolid(ivec3(offset_start));
	
	float t_voxel = +1.0f / 0.0f;
	vec3 radiance = vec3(0.0f);
	
	if(subgroupAny(!isRayInsideTerrain)){
		if(!isRayInsideTerrain) {
			radiance = computeRadiance(start, ray, t_voxel);
		}
	}
	
	// Step 2: update coefficients
	
	computeCoefficients(ray, radiance);
	
	{
		const int insideTerrainCount = subgroupAdd(int(isRayInsideTerrain));
		const int hitCount = subgroupAdd(int(!isinf(t_voxel)));
	
		if(gl_SubgroupInvocationID == 0) {
			shared_sumHitRays[gl_SubgroupID] = hitCount;
			shared_sumRaysInsideTerrain[gl_SubgroupID] = insideTerrainCount;
		}
	}
	
	barrier();
	
	if(gl_SubgroupID != 0){
		return;
	}
	
	const int lane = int(gl_SubgroupInvocationID);
	
	int sumHitRays = 0;
	int sumInsideTerrain = 0;
	vec3 sumCoeff = vec3(0.0f);
	
	for(int i=0; i<gl_NumSubgroups; i++){
		sumHitRays += shared_sumHitRays[i];
		sumInsideTerrain += shared_sumRaysInsideTerrain[i];
		sumCoeff += shared_betas[i][lane];
	}
	
	subgroupBarrier();
	
	if(lane >= 16){
		return;
	}
	
	const int valid_samples = num_samples - sumInsideTerrain;
	
	const vec4 previous_value = ArrayLoad(f16vec4, world.probes_values, (probe_index * 16 + lane), f16vec4(0.0f));
	
	vec4 new_value = vec4(sumCoeff / max(valid_samples, 1), valid_samples / float(num_samples));
	
	new_value = mix(previous_value, new_value, LearningRate);
	
	ArrayStore(f16vec4, world.updated_probes_values, (int(gl_WorkGroupID.x) * 16 + lane), f16vec4(new_value));

}
