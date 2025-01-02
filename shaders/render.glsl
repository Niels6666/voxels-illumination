#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shader_clock : enable
#extension GL_ARB_shading_language_include :   require
#extension GL_KHR_shader_subgroup_arithmetic : enable
#extension GL_NV_shader_atomic_int64 : enable

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

#include "/definitions.glsl"
#include "/render_common.glsl"
#include "/PBR.glsl"

uniform vec4 K;
uniform mat4 ViewMatrix;
uniform uint64_t RenderImageHandle;

uniform vec3 sunDir;
uniform vec3 sunLight;
uniform float exposure;

void main(void){

    const ivec2 pixelCoords = ivec2(gl_GlobalInvocationID);

    vec3 ray = computeRay(pixelCoords, K, ViewMatrix);
    vec3 start = toGridCoords(computeCamCenter(ViewMatrix));

    const vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);

    float tmin, tmax;
    bool hitBox = rayVSbox(start, 1.0f / ray, vec3(0.0f), maxCorner, tmin, tmax);

    vec3 color = vec3(0, 0, 0);

	int iterations = 0;
	bool isPixelOnVoxel = false;

	float t_voxel = +1.0f / 0.0f;
    if(hitBox){
		tmin = max(tmin, 0.0f);
		
		bvec3 last_step;
		uvec3 cell = trace(start, ray, tmin, tmax, t_voxel, iterations, last_step);
		if(!isinf(t_voxel)){
			const vec3 voxel_hit_pos = start + ray * t_voxel;
			//const bool sunVisible = testSunVisibility(voxel_hit_pos, sunDir);
			//const bool sunVisible = false;
		
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
			
			//vec3 brightness = max(dot(normal, sunDir), 0.0f) * sunLight;
			
			//if(!sunVisible) brightness = vec3(0.05f);
			//brightness = max(brightness, vec3(0.05f));
			
			//brightness = evalLightProbes(voxel_hit_pos, reflect(ray, normal));
			//brightness = evalLightProbes(voxel_hit_pos, ray);

			//color = vec3(albedo_emission) * brightness;
			//color = brightness;
			
			//color = evalLightProbesCoeff(voxel_hit_pos, reflect(ray, normal), 0);
			
			color = PBR(voxel_hit_pos, normal, ray, albedo, roughness, metallic, emission_strength);

			isPixelOnVoxel = true;
		}
    }
	
	if(isinf(t_voxel)){
		// sky color
		if(testSunHitBox(ray, sunDir)){
			color = sunLight * 100.0f;
		}else{
			color = getSkyRadiance(ray, sunDir);
		}
	}
	
    color = color / (color + exposure);  //tone mapping
    color = pow(color, vec3(1.0/2.2)); //gamma correction

    imageStore(image2D(RenderImageHandle), pixelCoords, vec4(color, 1.0f));
    
	ivec4 total = subgroupAdd(ivec4(int(iterations), int(isPixelOnVoxel), int(hitBox), 0));

	if(gl_SubgroupInvocationID == 0u){
		atomicAdd((restrict int*)world.performanceCounters.ptr + 0, total.x);
		atomicAdd((restrict int*)world.performanceCounters.ptr + 1, total.y);
		atomicAdd((restrict int*)world.performanceCounters.ptr + 2, total.z);
	}


}


