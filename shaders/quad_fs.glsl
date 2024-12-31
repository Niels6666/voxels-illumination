#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_ARB_bindless_texture : enable

uniform uint64_t ImageHandle;

in vec2 tex_coords;
out vec4 out_Color;

void main(void){
    layout(rgba16f) image2D img = layout(rgba16f) image2D(ImageHandle);
    ivec2 imgSize = imageSize(img);
	
	ivec2 coords = ivec2(tex_coords * imgSize);
	vec4 c = imageLoad(img, coords)*4;
	c += imageLoad(img, coords+ivec2(+1, 0));
	c += imageLoad(img, coords+ivec2(-1, 0));
	c += imageLoad(img, coords+ivec2(0, +1));
	c += imageLoad(img, coords+ivec2(0, -1));
	out_Color = c / 8;
    
}