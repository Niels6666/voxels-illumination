#version 460 core
#extension GL_NV_gpu_shader5 : enable
#extension GL_NV_shader_buffer_load : enable
#extension GL_ARB_bindless_texture : enable
#extension GL_ARB_shader_clock : enable
#extension GL_ARB_shading_language_include :   require
#extension GL_NV_shader_atomic_int64 : enable

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

#include "/definitions.glsl"

uniform int AllocateOrDelete;

void main(void){




}