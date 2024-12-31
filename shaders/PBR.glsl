
#include "/definitions.glsl"

const float PI = 3.141592653589793f;

float DistributionGGX(float NdotH, float roughness){
	float a = roughness*roughness;
    float a2 = a*a;
    float NdotH2 = NdotH*NdotH;

    const float denom  = (NdotH2 * (a2 - 1.0f) + 1.0f);
    return a2 / (PI * denom * denom);
}

float GeometrySmith(float NdotV, float NdotL, float roughness){
//	float k = (roughness + 1.0f) * (roughness + 1.0f) / 8.0f; // direct IBL
	float k = (roughness * roughness) / 2.0f;                 // indirect IBL
    float ggx1 = NdotV * (1.0f - k) + k;
    float ggx2 = NdotL * (1.0f - k) + k;
    return (NdotV * NdotL) / (ggx1 * ggx2);
}

vec3 fresnelSchlick(float HdotV, vec3 F0){
    return F0 + (1.0 - F0) * pow(clamp(1.0f - HdotV, 0.0f, 1.0f), 5.0f);
}

vec3 fresnelSchlickRoughness(const float NdotV, const vec3 F0, const float roughness){
	const float exponent = pow(clamp(1.0f - NdotV, 0.0f, 1.0f), 5.0f);
    return F0 + (max(vec3(1.0f-roughness), F0) - F0) * exponent;
}

const float SH_COEFFS[16] = {
	0.28209479177387814f,
	
	0.4886025119029199f,
	0.4886025119029199f,
	0.4886025119029199f,
	
	1.0925484305920792f,
	-1.0925484305920792f,
	0.31539156525252005f,
	-1.0925484305920792f,
	0.5462742152960396f,
	
	-0.5900435899266435f,
	2.890611442640554f,
	-0.4570457994644658f,
	0.3731763325901154f,
	-0.4570457994644658f,
	1.445305721320277f,
	-0.5900435899266435f
};

vec3 sampleProbeCoeff(vec3 samplingCoords, const int coeff){
	samplingCoords.z += coeff * (1.0f / 16.0f);
	return texture(sampler3D(world.probes_lerp.tex), samplingCoords).xyz * SH_COEFFS[coeff];
}

vec3 evalLightProbesCoeff(vec3 coord, vec3 dir, int coeff) {

    const vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);
	coord = clamp(coord, vec3(0.0f), maxCorner - 0.001f);
	coord = coord / 4.0f;

	const vec3 fcoord = floor(coord);
	const vec3 frac = coord	- fcoord;
	const ivec3 icoord = ivec3(fcoord);

	const int atlasCoords = texelFetch(isampler3D(world.occupancy.tex), icoord, 0).x;
	const int tile_id = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);

	vec3 samplingCoords = vec3(unwind2D(tile_id, world.probes_lerp_half_size), 0.0f) * 2.0f + frac + 0.5f;
	const vec3 lerpTexSize = vec3(world.probes_lerp_half_size, world.probes_lerp_half_size, 16) * 2.0f;
	samplingCoords /= lerpTexSize;
	
	samplingCoords.z += coeff * (1.0f / 16.0f);
	vec4 value = texture(sampler3D(world.probes_lerp.tex), samplingCoords);
	//return .xyz * SH_COEFFS[coeff];

    //return sampleProbeCoeff(samplingCoords, coeff);
    return vec3(value.xyz);
}


vec3 evalLightProbes(vec3 coord, vec3 dir) {

    const vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);
	coord = clamp(coord, vec3(0.0f), maxCorner - 0.001f);
	coord = coord / 4.0f;

	const vec3 fcoord = floor(coord);
	const vec3 frac = coord	- fcoord;
	const ivec3 icoord = ivec3(fcoord);

	const int atlasCoords = texelFetch(isampler3D(world.occupancy.tex), icoord, 0).x;
	const int tile_id = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);

	vec3 samplingCoords = vec3(unwind2D(tile_id, world.probes_lerp_half_size), 0.0f) * 2.0f + frac + 0.5f;
	const vec3 lerpTexSize = vec3(world.probes_lerp_half_size, world.probes_lerp_half_size, 16) * 2.0f;
	samplingCoords /= lerpTexSize;

	const float x = dir.x, y = dir.y, z = dir.z;

    vec3 F = vec3(0.0f);
    F += sampleProbeCoeff(samplingCoords,  0) * 1.0f;
    F += sampleProbeCoeff(samplingCoords,  1) * x;
    F += sampleProbeCoeff(samplingCoords,  2) * y;
    F += sampleProbeCoeff(samplingCoords,  3) * z;
    F += sampleProbeCoeff(samplingCoords,  4) * (x*y);
    F += sampleProbeCoeff(samplingCoords,  5) * (y*z);
    F += sampleProbeCoeff(samplingCoords,  6) * (3.0f*z*z - 1.0f);
    F += sampleProbeCoeff(samplingCoords,  7) * (x*z);
    F += sampleProbeCoeff(samplingCoords,  8) * (x*x-y*y);
    
    F += sampleProbeCoeff(samplingCoords,  9) * y * (3.0f * x*x - y*y);
    F += sampleProbeCoeff(samplingCoords, 10) * (x*y*z);
    F += sampleProbeCoeff(samplingCoords, 11) * y * (5.0f*z*z - 1.0f);
    F += sampleProbeCoeff(samplingCoords, 12) * z * (5.0f*z*z - 3.0f);
    F += sampleProbeCoeff(samplingCoords, 13) * x * (5.0f*z*z - 1.0f);
    F += sampleProbeCoeff(samplingCoords, 14) * z * (x*x - y*y);
    F += sampleProbeCoeff(samplingCoords, 15) * x * (x*x - 3.0f*y*y);
	
	return max(F, 0.0f);
}


void evalLightProbes(
	vec3 coord, 
	const vec3 N, // normal vector for diffuse light
	const vec3 R, // reflected vector for specular light
	out vec3 D,   // diffuse light
	out vec3 S,   // specular light
	const float roughness
	) {

    const vec3 maxCorner = 4 * vec3(world.tiles_width, world.tiles_height, world.tiles_depth);
	coord = clamp(coord, vec3(0.0f), maxCorner - 0.001f);
	coord = coord / 4.0f;

	const vec3 fcoord = floor(coord);
	const vec3 frac = coord	- fcoord;
	const ivec3 icoord = ivec3(fcoord);

	const int atlasCoords = texelFetch(isampler3D(world.occupancy.tex), icoord, 0).x;
	const int tile_id = wind3D(unpackivec3(atlasCoords), world.atlas_tile_size);

	vec3 samplingCoords = vec3(unwind2D(tile_id, world.probes_lerp_half_size), 0.0f) * 2.0f + frac + 0.5f;
	const vec3 lerpTexSize = vec3(world.probes_lerp_half_size, world.probes_lerp_half_size, 16) * 2.0f;
	samplingCoords /= lerpTexSize;

	
	const vec3 C0 = sampleProbeCoeff(samplingCoords,  0);
	const vec3 C1 = sampleProbeCoeff(samplingCoords,  1);
	const vec3 C2 = sampleProbeCoeff(samplingCoords,  2);
	const vec3 C3 = sampleProbeCoeff(samplingCoords,  3);
	
	const float e1 = exp(-roughness);   // exp(- 1.0f * roughness);
	const float e2 = e1*e1*e1;          // exp(- 3.0f * roughness);
	const float e3 = e2*e2;             // exp(- 6.0f * roughness);
	
	D = C0;
    D += C1 * N.x * e1;
    D += C2 * N.y * e1;
    D += C3 * N.z * e1;
	D = max(D, vec3(0.0f));

	const float x = R.x, y = R.y, z = R.z;

    S = C0;
    S += C1 * R.x * e1;
    S += C2 * R.y * e1;
    S += C3 * R.z * e1;
	
    S += sampleProbeCoeff(samplingCoords,  4) * e2 * (x*y);
    S += sampleProbeCoeff(samplingCoords,  5) * e2 * (y*z);
    S += sampleProbeCoeff(samplingCoords,  6) * e2 * (3.0f*z*z - 1.0f);
    S += sampleProbeCoeff(samplingCoords,  7) * e2 * (x*z);
    S += sampleProbeCoeff(samplingCoords,  8) * e2 * (x*x-y*y);
    
    S += sampleProbeCoeff(samplingCoords,  9) * e3 * y * (3.0f * x*x - y*y);
    S += sampleProbeCoeff(samplingCoords, 10) * e3 * (x*y*z);
    S += sampleProbeCoeff(samplingCoords, 11) * e3 * y * (5.0f*z*z - 1.0f);
    S += sampleProbeCoeff(samplingCoords, 12) * e3 * z * (5.0f*z*z - 3.0f);
    S += sampleProbeCoeff(samplingCoords, 13) * e3 * x * (5.0f*z*z - 1.0f);
    S += sampleProbeCoeff(samplingCoords, 14) * e3 * z * (x*x - y*y);
    S += sampleProbeCoeff(samplingCoords, 15) * e3 * x * (x*x - 3.0f*y*y);

	S = max(S, vec3(0.0f));
}

vec3 PBR(
	const vec3 coord,       // coordinates in the voxel grid
	const vec3 N, 			// normal ray
	const vec3 I, 			// incident ray
	const vec3 albedo,
	const float roughness, 
	const float metallic,
	const float emission_strength)
{
	if(emission_strength > 0.0f){
		return albedo * emission_strength * 50.0f;
	}
	
	const float cosTheta = max(-dot(N, I), 0.0f);

	//reflectance at normal incidence
	const vec3 F0 = mix(vec3(0.04f), albedo, metallic);

	const vec3 R = 2.0f * cosTheta * N + I; // Reflected ray

	const vec3 F = fresnelSchlickRoughness(cosTheta, F0, roughness);
	const vec3 kD = (1.0f - F) * (1.0f - metallic);
	
	const vec2 brdf = vec2(1, 0); // todo
	//const vec2 brdf = texture(brdfLUT, vec2(cosTheta, roughness)).rg;
	
	const vec3 kS = F * brdf.x + brdf.y;
	
	vec3 diffuse, specular;
	evalLightProbes(coord, N, R, diffuse, specular, roughness);

	//return diffuse;
	return kD * diffuse * albedo + kS * specular;
}
