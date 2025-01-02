#ifndef GENERATION
#define GENERATION

uniform uint64_t noiseTexHandle;
const int noiseTexWidth = 16; // Must be a power of 2

vec4 cubicLerpPolynomial(const float t){
	return vec4(1, t, t*t, t*t*t) *
		mat4(
			vec4(0.0f, -0.5f,  1.0f, -0.5f),
			vec4(1.0f,  0.0f, -2.5f,  1.5f),
			vec4(0.0f,  0.5f,  2.0f, -1.5f),
			vec4(0.0f,  0.0f, -0.5f, 0.5f)
		);
}

vec4 cubicLerpTex(vec3 c) {
	c *= noiseTexWidth;
	const int M = noiseTexWidth - 1;
	
	vec3 if_part = floor(c);
	const ivec3 i_part = ivec3(if_part);
	const vec3 u = c - if_part;
	
	const vec4 a0 = cubicLerpPolynomial(u.x);
	const vec4 a1 = cubicLerpPolynomial(u.y);
	const vec4 a2 = cubicLerpPolynomial(u.z);

	vec4 f = vec4(0.0f); // result
	
	#pragma unroll
	for(int k=0; k<=3; k++){
		#pragma unroll
		for(int j=0; j<=3; j++){
			#pragma unroll
			for(int i=0; i<=3; i++){
				const ivec3 lookup = (i_part + ivec3(i-1, j-1, k-1)) & M;
				const vec4 value = texelFetch(sampler3D(noiseTexHandle), lookup, 0);
				f += value * (a0[i] * a1[j] * a2[k]);
			}
		}
	}
	
	return f;
}


float lerpTex(vec3 c){
	c *= noiseTexWidth;
	const int M = noiseTexWidth - 1;
	
	vec3 if_part = floor(c);
	const ivec3 i_part = ivec3(if_part);
	const vec3 u = c - if_part;
	const vec3 v = vec3(1.0f) - u;
	
	float value = 0.0f;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(0,0,0)) & M, 0).x * v.x * v.y * v.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(1,0,0)) & M, 0).x * u.x * v.y * v.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(0,1,0)) & M, 0).x * v.x * u.y * v.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(1,1,0)) & M, 0).x * u.x * u.y * v.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(0,0,1)) & M, 0).x * v.x * v.y * u.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(1,0,1)) & M, 0).x * u.x * v.y * u.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(0,1,1)) & M, 0).x * v.x * u.y * u.z;
	value += texelFetch(sampler3D(noiseTexHandle), (i_part + ivec3(1,1,1)) & M, 0).x * u.x * u.y * u.z;
	
	return value;
}

float generateDensity(ivec3 world_coords) {

    sampler3D NoiseTex = sampler3D(noiseTexHandle);

    // map voxel coordinates to [-1, 1]
    vec3 c = 2.0f * (vec3(world_coords) + 0.5f) / (4.0f * vec3(min(world.tiles_width, world.tiles_depth))) - 1.0f;

    float density = c.y+0.5f;
    
    // Perlin's noise
    float amplitude = 0.4f;
    float frequency = 0.1f;
    
    for(int i=0; i<6; i++){
    	const vec4 f = cubicLerpTex(c * frequency);
    	
    	density += amplitude * abs(f.x);
    	
        amplitude /= 2.453f;
        frequency *= 1.734f;
        
        c += f.yzw * amplitude * 1.5f; // The warp sholololowwww
    }

    return density;
}


bool testIsInside(ivec3 world_coords) {
    return generateDensity(world_coords) < 0.0f;
}

#endif