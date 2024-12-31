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

uniform uint64_t RenderImageHandle;
uniform vec3 light_pos;

vec3 getCubeMapRay(){
    const int cubemap_face = int(gl_GlobalInvocationID.z);
    const int x = int(gl_GlobalInvocationID.x);
    const int y = int(gl_GlobalInvocationID.y);
    
    const int w = int(gl_NumWorkGroups.x) * 8;

    const float u = 2.0f * (x + 0.5f) / w - 1.0f;
    const float v = 2.0f * (y + 0.5f) / w - 1.0f;
    
    //GL_TEXTURE_CUBE_MAP_POSITIVE_X
    //GL_TEXTURE_CUBE_MAP_NEGATIVE_X
    //GL_TEXTURE_CUBE_MAP_POSITIVE_Y
    //GL_TEXTURE_CUBE_MAP_NEGATIVE_Y
    //GL_TEXTURE_CUBE_MAP_POSITIVE_Z
    //GL_TEXTURE_CUBE_MAP_NEGATIVE_Z

    vec3 ray;
    if(cubemap_face == 0){
        // -z, -y
        ray = vec3(+1, -v, -u);
    }else if(cubemap_face == 1){
        // +z, -y
        ray = vec3(-1, -v, +u);
    }else if(cubemap_face == 2){
        // +x, +z
        ray = vec3(u, +1, v);
    }else if(cubemap_face == 3){
        // +x, -z
        ray = vec3(u, -1, -v);
    }else if(cubemap_face == 4){
    	// +x, -y
        ray = vec3(u, -v, +1);
    }else if(cubemap_face == 5){
        // -x, -y
        ray = vec3(-u, -v, -1);
    }

    return normalize(ray);
}

void main(void){

    vec3 ray = getCubeMapRay();
    vec3 start = toGridCoords(light_pos);

    vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);

    float tmin, tmax;
    bool hitBox = rayVSbox(start, 1.0f / ray, vec3(0.0f), maxCorner, tmin, tmax);

    float t_voxel = +1.0f / 0.0f; // +inf
    int iterations = 0;
    vec4 color = vec4(0, 0, 0, 1);
    if(hitBox){
		tmin = max(tmin, 0.0f);
		bvec3 last_step;
		uvec3 cell = trace(start, ray, tmin, tmax, t_voxel, iterations, last_step);
    }

	float eps = 2.0f * world.voxelSize;
    //t_voxel += eps;

    //t_voxel *= 1.005f;

    imageStore(layout(rg32f) imageCube(RenderImageHandle), ivec3(gl_GlobalInvocationID), vec4(t_voxel, t_voxel*t_voxel, 0, 1.0f));
}