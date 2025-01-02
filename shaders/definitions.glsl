#ifndef DEFINITIONS
#define DEFINITIONS

struct texture_handle{
	uint64_t tex;
	uint64_t img;
};

struct buffer_handle{
	uint64_t ptr;
	int64_t size;
};


struct TileDescriptor{
    ivec3 coords;
    int status; // 0 if not allocated, 1 if allocated
};

struct ProbeDescriptor{
    ivec3 coords;
    int status; // 0 if not allocated, 1 if allocated
};


//// Block types

const int BLOCK_AIR = 0;
const int BLOCK_GRASS = 1;
const int BLOCK_DIRT = 2;
const int BLOCK_STONE = 3;
const int BLOCK_GOLD = 4;
const int BLOCK_URANIUM = 5;

struct BlockData{
	u8vec4 albedo_emission_strength; 
	u8vec4 roughness_metallic;       // last two components are unused 
};

struct PerformanceCounters{
	int mainWindowIterationCount;
	int mainWindowValidPixels; // on a voxel
    int mainWindowPixelsInBoundingBox;
    int padd1;
};

struct World{
    int tiles_width;
    int tiles_height;
    int tiles_depth;
    int maxTiles;

    vec3 minCorner;
    float voxelSize;

    texture_handle occupancy;
    texture_handle block_ids;
	texture_handle probes_occupancy;
	texture_handle probes_lerp;
	
	restrict f16vec4* probes_values;
	restrict vec4* probes_ray_dirs;
	
	restrict int* free_probes_stack;
	restrict int* num_free_probes;
	
	restrict ProbeDescriptor* probes;
	restrict f16vec4* updated_probes_values;
	
    restrict BlockData* block_types;
    int max_block_types;
    int probes_lerp_half_size;
        
    restrict uint64_t* compressed_occupancy; // each bit is 1 if a given tile is allocated, 0 otherwise
    restrict uint64_t* compressed_atlas;     // each bit is 1 if a given voxel is solid, 0 otherwise (air)
    
    restrict TileDescriptor* tiles;
    restrict int* free_tiles_stack;

    restrict int* num_free_tiles;
    int atlas_tile_size;
    int padd1;
    
    restrict PerformanceCounters* perf;
    restrict uint64_t* compressed_inside_terrain; // each bit is 1 if a given tile is fully solid, 0 if the tile is fully empty (air).

	restrict int* valid_probes_for_rendering;  // these probes can be used for exponential averaging and rendering
	restrict int* valid_probes_for_raytracing; // these probes can be used for tracing rays
	
	restrict int* num_valid_probes_for_rendering;
	restrict int* num_valid_probes_for_raytracing;

};

layout(std140, binding = 0) uniform CommonUniformsBlock0
{
    World world;
};


// removes s elements from count.
// if count is less than s, returns -1
// else returns the new value of count
int stack_pop(volatile int* count, int s){
    int old_count = *count;

    int assumed;
    do{
        assumed = old_count;
        if(assumed < s){
            return -1;
        }
        old_count = atomicCompSwap(count, assumed, assumed - s);
    }while(assumed != old_count);

    return old_count - s;
}

vec3 toWorldCoords(vec3 voxelCoords){
    return voxelCoords * world.voxelSize + world.minCorner;
}

vec3 toGridCoords(vec3 worldCoords){
    return (worldCoords - world.minCorner) / world.voxelSize;
}

bool rayVSbox(vec3 base, vec3 ray_inv, vec3 minCorner, vec3 maxCorner, out float tmin, out float tmax) {
	float tx1 = (minCorner.x - base.x) * ray_inv.x;
	float tx2 = (maxCorner.x - base.x) * ray_inv.x;
	
	tmin = min(tx1, tx2);
	tmax = max(tx1, tx2);
	
	float ty1 = (minCorner.y - base.y) * ray_inv.y;
	float ty2 = (maxCorner.y - base.y) * ray_inv.y;
	
	tmin = max(tmin, min(ty1, ty2));
	tmax = min(tmax, max(ty1, ty2));
	
	float tz1 = (minCorner.z - base.z) * ray_inv.z;
	float tz2 = (maxCorner.z - base.z) * ray_inv.z;
	
	tmin = max(tmin, min(tz1, tz2));
	tmax = min(tmax, max(tz1, tz2));
	
 	return tmax >= max(0.0f, tmin);
}

bool checkMask(const uint64_t mask, const ivec3 subCoords){ // in [0, 3]
    const int n = (subCoords.x<<0) | (subCoords.y<<2) | (subCoords.z<<4);
    return (mask & (1UL<<n)) != 0;
}

bool checkMask(const uint64_t mask, const uvec3 subCoords){ // in [0, 3]
    const uint n = (subCoords.x<<0) | (subCoords.y<<2) | (subCoords.z<<4);
    return (mask & (1UL<<n)) != 0;
}

ivec3 unwind3D(int k, int S){
	// k = x + y * S + z * S * S
	const int S2 = S*S;
	ivec3 C;
	C.z = k / S2;
	C.y = (k - C.z * S2) / S;
	C.x = (k - C.y * S - C.z * S2);
	return C;
}

int wind3D(ivec3 c, int S){
	return c.x + (c.y  + c.z * S) * S;
}


ivec2 unwind2D(int k, int S){
	// k = x + y * S
	ivec2 C;
	C.y = k / S;
	C.x = k - C.y * S;
	return C;
}

int wind2D(ivec2 c, int S){
	return c.x + c.y * S;
}

uint64_t fetchCompressedOccupancy(const int level, const uint block_id){
    if(level == 0){
        return world.compressed_occupancy[block_id];
    }else{
        return world.compressed_atlas[block_id];
    }
}

uint64_t fetchCompressedOccupancy(const int level, const int block_id){
    if(level == 0){
        return world.compressed_occupancy[block_id];
    }else{
        return world.compressed_atlas[block_id];
    }
}

/**
 * Packs an ivec3 into a 32 bit integer
 */
int packivec3(ivec3 c){
	int k = 0;
	k = bitfieldInsert(k, c.x, 0, 10);
	k = bitfieldInsert(k, c.y, 10, 10);
	k = bitfieldInsert(k, c.z, 20, 10);
	return k;
}

/**
 * Unpacks a 32 bit integer into an ivec3
 */
ivec3 unpackivec3(int k){
	uvec3 c;
	c.x = bitfieldExtract(uint(k), 0, 10);
	c.y = bitfieldExtract(uint(k), 10, 10);
	c.z = bitfieldExtract(uint(k), 20, 10);
	return ivec3(c);
}

// Debug functions

struct debugStruct{
	int line;  // line of the error
	int index; // index of the error
	int size;  // size of the buffer
	int floatData; // 1 if the debug info should be interpreted as ints, 2 if the debug info should be interpreted as floats
	ivec4 data; // additional debug info
};

layout(std430, binding = 15) restrict buffer DebugBlock
{
    uint32_t debugStructsCount;
    uint32_t debugStructsPadding0;
    uint32_t debugStructsPadding1;
    uint32_t debugStructsPadding2;
    ivec4 debugStructsPadding3;
    debugStruct debugStructsArray[];
};

void reportBufferError(int line, int64_t index, int64_t size){
    uint n = atomicAdd(debugStructsCount, 1u);
    debugStructsArray[n].line = line;
    debugStructsArray[n].index = int(index);
    debugStructsArray[n].size = int(size);
    debugStructsArray[n].floatData = 0;
}

void reportBufferError(int line, int64_t index, int64_t size, ivec4 intData){
    uint n = atomicAdd(debugStructsCount, 1u);
    debugStructsArray[n].line = line;
    debugStructsArray[n].index = int(index);
    debugStructsArray[n].size = int(size);
    debugStructsArray[n].floatData = 1;
    debugStructsArray[n].data = intData;
}
void reportBufferError(int line, int64_t index, int64_t size, vec4 floatData){
    uint n = atomicAdd(debugStructsCount, 1u);
    debugStructsArray[n].line = line;
    debugStructsArray[n].index = int(index);
    debugStructsArray[n].size = int(size);
    debugStructsArray[n].floatData = 2;
    debugStructsArray[n].data = floatBitsToInt(floatData);
}

#define TestBounds(index, size) (index >= 0 && index < size) ? (true) : (reportBufferError(__LINE__, index, size),false)
#define reportFalse(predicate) (predicate) ? (predicate) : (reportBufferError(__LINE__, 0, 0),false)
#define PtrLoad(ptr, index, size, default_res) (((index) >= 0 && (index) < size) ? ptr[(index)] : (reportBufferError(__LINE__, (index), size), default_res))
#define ArrayLoad(type, buf, index, default_res) ((index >= 0 && index < buf.size) ? ((restrict type*)buf.ptr)[index] : (reportBufferError(__LINE__, index, buf.size), default_res))
#define ArrayStore(type, buf, index, val) if(index >= 0 && index < buf.size) { ((restrict type*)buf.ptr)[index] = val; }else{ reportBufferError(__LINE__, index, buf.size); };
#define ArrayStoreField(type, field, buf, index, val) if(index >= 0 && index < buf.size) { ((restrict type*)buf.ptr)[index].field = val; }else{ reportBufferError(__LINE__, index, buf.size); };



#endif