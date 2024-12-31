#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shading_language_include :   require

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform uint64_t input_ImageHandle;
uniform uint64_t output_ImageHandle;

uniform float exposure;

void main(){
	layout(rgba16f) image2D inputImg = layout(rgba16f) image2D(input_ImageHandle);
	layout(rgba16f) image2D outputImg = layout(rgba16f) image2D(output_ImageHandle);

    vec4 color = imageLoad(inputImg, ivec2(gl_GlobalInvocationID.xy));

    color = color / (color + exposure);  //tone mapping
    color = pow(color, vec4(1.0/2.2));//gamma correction
    color.a = 1.0f;
    imageStore(outputImg, ivec2(gl_GlobalInvocationID.xy), color);

}