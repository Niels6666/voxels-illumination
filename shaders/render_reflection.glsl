#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shader_clock : enable
#extension GL_ARB_shading_language_include :   require
#extension GL_KHR_shader_subgroup_arithmetic : enable

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

#include "/definitions.glsl"
#include "/render_common.glsl"

uniform vec4 K;
uniform mat4 ViewMatrix;
uniform uint64_t RenderImageHandle;
uniform uint64_t RenderDepthImageHandle;
uniform uint64_t RenderNormalImageHandle;
uniform uint64_t RenderReflectionImageHandle;
uniform uint64_t RenderReflectionDepthImageHandle;
uniform uint64_t RenderReflectionNormalImageHandle;

uniform vec3 light_pos;
uniform vec3 light_color;
uniform uint64_t light_cubemap_handle;

bool testCubeMap(vec3 start, vec3 ray, inout float tcube, out vec4 cubecolor){

	vec3 center = toGridCoords(light_pos);
	float sun_radius = 10;

	float tmin, tmax;
	bool ok = rayVSbox(start, 1.0f / ray, center - sun_radius, center + sun_radius, tmin, tmax);

	if(!ok || tmin < 0.0f){
		return false;
	}

	tcube = tmin * world.voxelSize;

	cubecolor = vec4(vec3(10000), 1);

	//vec3 cuberay = normalize(start + ray * tmin - center);
	//cubecolor = texture(samplerCube(light_cubemap_handle), cuberay);

	return true;
}

float computeShadowing(vec3 worldCoords) {
	// http://igm.univ-mlv.fr/~biri/Enseignement/MII2/Donnees/variance_shadow_maps.pdf
	vec3 dir = worldCoords - light_pos;
	float point_dist = length(dir);

	float eps = 2.0f * world.voxelSize;

	vec2 rr2 = texture(samplerCube(light_cubemap_handle), normalize(dir)).xy;
	float mu = rr2.x;

	if(point_dist < mu + eps){
		return 1.0f;
	}else{
		return 0.0f;
	}

	float sigma2 = rr2.y - mu*mu;
	float pmax = sigma2 / (sigma2 + (point_dist - mu) * (point_dist - mu));
	return pmax;

	//float light_dist = mu;
	//return point_dist > light_dist + eps;
}

void main(void){

    const ivec2 pixelCoords = ivec2(gl_GlobalInvocationID);

    vec3 ray = computeRay(pixelCoords, K, ViewMatrix);
    vec3 start = toGridCoords(computeCamCenter(ViewMatrix));

    float t_voxel = imageLoad(layout(r32f) image2D(RenderDepthImageHandle), pixelCoords).x;
    vec3 normal = normalize(imageLoad(layout(rgba8_snorm) image2D(RenderNormalImageHandle), pixelCoords).xyz);
	vec3 baseNormal = normal;

    vec4 color = vec4(0, 0, 0, 1);
    int iterations = 0;
    bool isPixelOnVoxel = false;
    bool hitBox = false;

	bool skyFirstHit = isinf(t_voxel);

    if(!skyFirstHit){

        start = start + ray * t_voxel;
        ray = reflect(ray, normal);


        vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);

        float tmin, tmax;
        hitBox = rayVSbox(start, 1.0f / ray, vec3(0.0f), maxCorner, tmin, tmax);

        normal = vec3(0,0,0);

        t_voxel = +1.0f / 0.0f;
        if(hitBox){
            tmin = max(tmin, 0.0f);
            
            bvec3 last_step;
            uvec3 cell = trace(start, ray, tmin, tmax, t_voxel, iterations, last_step);
            if(!isinf(t_voxel)){
                const int packedAtlasCoords = texelFetch(isampler3D(world.occupancy.tex), ivec3(cell >> 2u), 0).x;
                const ivec3 atlasCoords = unpackivec3(packedAtlasCoords) * 4 + ivec3(cell & 3u);
                color = texelFetch(sampler3D(world.atlas_colors.tex), atlasCoords, 0);
                normal = -mix(vec3(last_step), -vec3(last_step), lessThan(ray, vec3(0)));

                if(color.a != 1.0){
                    vec3 voxel_center = toWorldCoords(start) + ray * t_voxel;
                    vec3 light_dir = light_pos - voxel_center;
                    float dist = length(light_dir);
                    light_dir /= dist;
                    float attenuation = 1.0 / (1.0 + 0.0001 * dist * dist);
                    float brightness = max(dot(normal, light_dir), 0.0) * attenuation;
                    brightness *= max(computeShadowing(voxel_center), 0.1f);

                    vec4 diffuse = vec4(brightness * light_color, 1f);
                    color *= diffuse;
                }

                isPixelOnVoxel = true;
            }

        }
    }
	
	if(isinf(t_voxel)){
		vec3 c0 = vec3(0.3f, 0.6f, 4) * 2;
		vec3 c1 = vec3(0.3f, 0.6f, 2) * 0.25f;
		vec3 cam = toWorldCoords(start);
		vec3 toLight = normalize(light_pos - cam);
		float s = dot(ray, toLight) * 0.5f + 0.5f;
		color = vec4(mix(c1, c0, s), 1);
	}

	float tcube = +1.0f/0.0f;
	vec4 cubecolor = vec4(0.0f);
	if(testCubeMap(start, ray, tcube, cubecolor)){
		if(tcube < t_voxel){
			color = cubecolor;
		}
	}

	vec4 baseColor = imageLoad(layout(rgba16f) image2D(RenderImageHandle), pixelCoords);
	if(skyFirstHit){
		color = baseColor;
	}else{
		float R0 = 0.04;
		vec3 baseRay = computeRay(pixelCoords, K, ViewMatrix);
		float NdotV = max(dot(baseNormal, -baseRay), 0.0f);
		float reflectivity = R0 + (1.0f - R0) * pow(1.0f - NdotV, 5.0f);
		color = baseColor + reflectivity * color;
	}


    imageStore(image2D(RenderReflectionImageHandle), pixelCoords, color);
    imageStore(image2D(RenderReflectionDepthImageHandle), pixelCoords, vec4(t_voxel, 0, 0, 0));
    imageStore(image2D(RenderReflectionNormalImageHandle), pixelCoords, vec4(normal, 0));

	ivec4 total = subgroupAdd(ivec4(int(iterations), int(isPixelOnVoxel), int(hitBox), 0));

	if(gl_SubgroupInvocationID == 0u){

		atomicAdd((int*)world.perf + 0, total.x);
		atomicAdd((int*)world.perf + 1, total.y);
		atomicAdd((int*)world.perf + 2, total.z);

	}


}