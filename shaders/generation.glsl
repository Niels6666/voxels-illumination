#ifndef GENERATION
#define GENERATION

uniform uint64_t noiseTexHandle;

float generateDensity(ivec3 world_coords) {

    sampler3D NoiseTex = sampler3D(noiseTexHandle);

    // map voxel coordinates to [-1, 1]
    vec3 c = 2.0f * (vec3(world_coords) + 0.5f) / (4.0f * world.tiles_height) - 1.0f;

    float density = c.y;

    // Perlin's noise
    float amplitude = 0.3f;
    float frequency = 0.0436f;
    
    for(int i=0; i<4; i++){
        density += amplitude * texture(NoiseTex, c * frequency).x;
        amplitude /= 2.457f;
        frequency *= 1.493;
    }

    return density;
}


bool testIsInside(ivec3 world_coords) {
    return generateDensity(world_coords) < 0.0f;
}

#endif