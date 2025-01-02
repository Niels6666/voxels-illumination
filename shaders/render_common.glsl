#ifndef RENDER_COMMON
#define RENDER_COMMON

#include "/definitions.glsl"

vec3 computeRay(ivec2 pixelCoords,
    const vec4 K,
    const mat4 ViewMatrix)
{
    float fx = K.x;
    float fy = K.y;
    float cx = K.z;
    float cy = K.w;

    float x = pixelCoords.x + 0.5f;
    float y = pixelCoords.y + 0.5f;

    vec3 ray = vec3((x - cx) / fx, -(y - cy) / fy, -1);
    mat3 R = mat3(ViewMatrix);
    ray = transpose(R) * ray;

    ray = normalize(ray);
    return ray;
}

vec3 computeCamCenter(const mat4 ViewMatrix){
    mat3 R = mat3(ViewMatrix);
    vec3 T = vec3(ViewMatrix[3]);
    return -(transpose(R) * T);
}

// tests if a voxel is allocated at the given coordinate
bool testBlockAllocated(const ivec3 coords){
	const ivec3 worldSize = ivec3(world.tiles_width, world.tiles_height, world.tiles_depth) * 4;
    const ivec3 worldSuperTileSize = worldSize / 16;

	if(any(greaterThanEqual(coords, worldSize)) || any(lessThan(coords, ivec3(0)))){
		return false;
	}
	
	const ivec3 cell_s0 = coords >> 0;
	const ivec3 cell_s2 = coords >> 2;
	const ivec3 cell_s4 = coords >> 4;

	const int super_tile_id = cell_s4.x + worldSuperTileSize.x * (cell_s4.y + cell_s4.z * worldSuperTileSize.y);
	const uint64_t compressedOccupancy0 = fetchCompressedOccupancy(0, super_tile_id);
	
	if(compressedOccupancy0 == 0UL){
		return false;
	}

	if(!checkMask(compressedOccupancy0, cell_s2 & 3)){
		return false;
	}

	const int atlasCoords = texelFetch(isampler3D(world.occupancy.tex), ivec3(cell_s2), 0).x;
	const int tile_id = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);
	const uint64_t compressedOccupancy1 = fetchCompressedOccupancy(1, tile_id);

	if(!checkMask(compressedOccupancy1, cell_s0 & 3)){
		return false;
	}

	return true;
}

// tests if the given coordinate is considered to be inside the terrain
bool testBlockSolid(const ivec3 coords){
	const ivec3 worldSize = ivec3(world.tiles_width, world.tiles_height, world.tiles_depth) * 4;
    const ivec3 worldSuperTileSize = worldSize / 16;

	if(any(greaterThanEqual(coords, worldSize)) || any(lessThan(coords, ivec3(0)))){
		return false;
	}
	
	const ivec3 cell_s0 = coords >> 0;
	const ivec3 cell_s2 = coords >> 2;

	const int atlasCoords = texelFetch(isampler3D(world.occupancy.tex), ivec3(cell_s2), 0).x;
	
	if(atlasCoords == -2){
		// fully solid
		return true;
	}else if(atlasCoords == -1){
		// fully air
		return false;
	}
	
	const int tile_id = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);
	const uint64_t compressedOccupancy1 = fetchCompressedOccupancy(1, tile_id);

	return checkMask(compressedOccupancy1, cell_s0 & 3);
}

int testOccupancy(
        const bvec3 mirrors,
		const vec3 start,
        const vec3 abs_ray,
		const vec3 inv_abs_ray,
		const ivec3 current_cell,
		inout ivec3 previous_true_cell)
{

    const ivec3 worldSize = ivec3(world.tiles_width, world.tiles_height, world.tiles_depth) * 4;
    const ivec3 worldSuperTileSize = worldSize / 16;

	if(any(greaterThanEqual(current_cell, worldSize)) || any(lessThan(current_cell, ivec3(0)))){
		return 16;
	}

    const ivec3 true_cell = mix(current_cell, worldSize - 1 - current_cell, mirrors);
	const ivec3 cell_s0 = true_cell >> 0;
	const ivec3 cell_s2 = true_cell >> 2;
	const ivec3 cell_s4 = true_cell >> 4;

    previous_true_cell = true_cell;

	const int super_tile_id = cell_s4.x + worldSuperTileSize.x * (cell_s4.y + cell_s4.z * worldSuperTileSize.y);
	const uint64_t compressedOccupancy0 = fetchCompressedOccupancy(0, super_tile_id);
	
	if(compressedOccupancy0 == 0UL){
		return 16;
	}

	if(!checkMask(compressedOccupancy0, cell_s2 & 3)){
		return 4;
	}

	const int atlasCoords = texelFetch(isampler3D(world.occupancy.tex), ivec3(cell_s2), 0).x;
	const int tile_id = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);
	const uint64_t compressedOccupancy1 = fetchCompressedOccupancy(1, tile_id);

	if(!checkMask(compressedOccupancy1, cell_s0 & 3)){
		return 1;
	}

	return 0;
}

// All inputs must be in must be in grid coords: start, tmin, tmax
// ray: must be unit length
// t_voxel: distance from start to hit point in grid coords
// last_step: set the x, y, or z component to true if the last iteration moved along the x, y or z axis respectively
// iterations: number of iterations spent in the while loop
// returns: the coords of the first voxel hit by the ray
uvec3 trace(vec3 start, const vec3 ray, const float tmin, const float tmax,
				out float t_voxel, out int iterations, out bvec3 last_step){

	const float eps = 1.0E-2f;
	float t = tmin + eps;

    const bvec3 mirrors = lessThan(ray, vec3(0.0f));
    const vec3 abs_ray = abs(ray);
    const vec3 inv_abs_ray = 1.0f / abs_ray;

    const ivec3 worldSize = ivec3(world.tiles_width, world.tiles_height, world.tiles_depth) * 4;
	// mirror start if necessary
	start = mix(start, worldSize - start, mirrors);

    ivec3 current_cell = ivec3(start + abs_ray * t);
    ivec3 previous_true_cell = ivec3(-1);

	last_step = bvec3(false);

	iterations = 0;
	t_voxel = +1.0f / 0.0f; // +inf
	while(t < tmax - eps && iterations < 500){

		const int skip = testOccupancy(
            mirrors,
            start,
            abs_ray,
            inv_abs_ray,
            current_cell,
            previous_true_cell);

		if(skip == 0){
			t_voxel = t;
			break;
		}

		ivec3 next_cell = (current_cell & ~(skip-1)) + skip;
		const vec3 next_intersections = (vec3(next_cell) - start) * inv_abs_ray;
		const float t_next = min(next_intersections.x, min(next_intersections.y, next_intersections.z));
		const ivec3 predicted_cell = ivec3(start + abs_ray * t_next); // predict the other two coordinates
		last_step = equal(vec3(t_next), next_intersections);
		next_cell = mix(predicted_cell, next_cell, last_step);

        current_cell = next_cell;
		t = t_next;

		iterations++;
	}

	return previous_true_cell;
}

// All inputs must be in grid coords
// start must be within the grid
bool testSunVisibility(const vec3 start, const vec3 ray){
	
    const vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);

    float tmin, tmax;
    bool hitBox = rayVSbox(start, 1.0f / ray, vec3(0.0f), maxCorner, tmin, tmax);
    
    if(!hitBox) return false;
    
	tmin = 0.0f;
	
	float t_voxel = +1.0f / 0.0f;
	
	bvec3 last_step;
	int iterations = 0;
	uvec3 cell = trace(start, ray, tmin, tmax, t_voxel, iterations, last_step);
	
	return isinf(t_voxel);
}


bool testSunHitBox(const vec3 ray, const vec3 sunDir){
	const float sun_distance = 10.0f;

	return dot(ray, sunDir) > 0.985f;
}

vec3 getSkyRadiance(const vec3 ray, const vec3 sunDir){
	// sky color
	vec3 c0 = vec3(0.3f, 0.6f, 1.0f) * 2.0f;
	vec3 c1 = vec3(0.3f, 0.6f, 0.8f) * 0.25f;
	vec3 c2 = vec3(4.0f, 0.3f, 0.3f) * 2.0f;
	vec3 c3 = vec3(2.0f, 0.2f, 0.2f);
	const vec3 up = vec3(0,1,0);
	float s1 = dot(ray, sunDir) * 0.5f + 0.5f; // 1 is close to the sun, 0 is opposite
	float s2 = 1-abs(dot(sunDir, up));  // 1 is midday, 0 is sun set or sun rise
	s2 = s2*s2*s2*s2;
	return mix(mix(c1, c3, s2), mix(c0, c2, s2), s1);
}

#endif