#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shading_language_include :   require

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform uint64_t input_TextureHandle;
uniform uint64_t output_ImageHandle;

vec4 filter13tap(vec2 texCoords) {
	sampler2D inputImg = sampler2D(input_TextureHandle);
	//Size of one texel
    vec2 tex_offset = 1.0 / textureSize(inputImg, 0);
    
    //Sampling pattern:
    //
    //   c27   c28   c21
    //      c14   c11
    //   c26   c00   c22   
    //      c13   c12
    //   c25   c24   c23
    //

	vec4 c00 = texture(inputImg, texCoords);
	
	vec4 c11 = texture(inputImg, texCoords + tex_offset * ivec2(+1, +1));
	vec4 c12 = texture(inputImg, texCoords + tex_offset * ivec2(+1, -1));
	vec4 c13 = texture(inputImg, texCoords + tex_offset * ivec2(-1, +1));
	vec4 c14 = texture(inputImg, texCoords + tex_offset * ivec2(-1, -1));
	
	vec4 c21 = texture(inputImg, texCoords + tex_offset * ivec2(+2, +2));
	vec4 c22 = texture(inputImg, texCoords + tex_offset * ivec2(+2, +0));
	vec4 c23 = texture(inputImg, texCoords + tex_offset * ivec2(+2, -2));
	vec4 c24 = texture(inputImg, texCoords + tex_offset * ivec2(+0, -2));
	vec4 c25 = texture(inputImg, texCoords + tex_offset * ivec2(-2, -2));
	vec4 c26 = texture(inputImg, texCoords + tex_offset * ivec2(-2, +0));
	vec4 c27 = texture(inputImg, texCoords + tex_offset * ivec2(-2, +2));
	vec4 c28 = texture(inputImg, texCoords + tex_offset * ivec2(+0, +2));
	
	vec4 box0 = (c11 + c12 + c13 + c14) * 0.25;
	vec4 box1 = (c21 + c22 + c00 + c28) * 0.25;
	vec4 box2 = (c00 + c22 + c23 + c24) * 0.25;
	vec4 box3 = (c26 + c00 + c24 + c25) * 0.25;
	vec4 box4 = (c27 + c28 + c00 + c26) * 0.25;
	
	return box0 * 0.5 + (box1 + box2 + box3 + box4) * 0.125;
}


void main(){
	layout(rgba16f) image2D outputImg = layout(rgba16f) image2D(output_ImageHandle);

    vec2 texCoords = (vec2(gl_GlobalInvocationID.xy) + 0.5) / imageSize(outputImg);
    vec4 c = filter13tap(texCoords);
	
    imageStore(outputImg, ivec2(gl_GlobalInvocationID.xy), c);

}