#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shading_language_include :   require

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

uniform uint64_t input_TextureHandle;
uniform uint64_t output_ImageHandle;

uniform float weight;
uniform int num_cascades;
uniform int cascade_index;

vec4 filterTent(vec2 texCoords){
	sampler2D inputImg = sampler2D(input_TextureHandle);

	//Size of one texel
    vec2 tex_offset = 1.0 / textureSize(inputImg, 0);
    
    //Sampling pattern:
    //
    //   c11   c12   c13
    //   c21   c22   c23   
    //   c31   c32   c33
    //

	vec4 c11 = texture(inputImg, texCoords + tex_offset * ivec2(-1, +1));
	vec4 c12 = texture(inputImg, texCoords + tex_offset * ivec2(+0, +1));
	vec4 c13 = texture(inputImg, texCoords + tex_offset * ivec2(+1, +1));
	                  
	vec4 c21 = texture(inputImg, texCoords + tex_offset * ivec2(-1, +0));
	vec4 c22 = texture(inputImg, texCoords + tex_offset * ivec2(+0, +0));
	vec4 c23 = texture(inputImg, texCoords + tex_offset * ivec2(+1, +0));
	                   
	vec4 c31 = texture(inputImg, texCoords + tex_offset * ivec2(-1, -1));
	vec4 c32 = texture(inputImg, texCoords + tex_offset * ivec2(+0, -1));
	vec4 c33 = texture(inputImg, texCoords + tex_offset * ivec2(+1, -1));
	
	return (1.0/16.0) * ((c11 + c13 + c31 + c33) + (c12 + c23 + c21 + c32) * 2.0 + c22 * 4.0);
}


void main(){
	layout(rgba16f) image2D outputImg = layout(rgba16f) image2D(output_ImageHandle);

    vec4 previous_c = imageLoad(outputImg, ivec2(gl_GlobalInvocationID.xy));

    vec2 texCoords = (vec2(gl_GlobalInvocationID.xy) + 0.5) / imageSize(outputImg);
    vec4 c = filterTent(texCoords);

    if(cascade_index == 0){
		previous_c += c*weight/num_cascades;   	
    }else{
    	previous_c += c*weight;
    }

    imageStore(outputImg, ivec2(gl_GlobalInvocationID.xy), previous_c);


}