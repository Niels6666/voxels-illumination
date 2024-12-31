#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_ARB_bindless_texture : enable

uniform uint64_t ImageHandle;

in vec2 tex_coords;
out vec4 out_Color;

void main(void){
    layout(rgba16f) image2D img = layout(rgba16f) image2D(ImageHandle);
    ivec2 imgSize = imageSize(img);

	vec4 c = imageLoad(img, ivec2(tex_coords * imgSize));
	out_Color = c;
    
}