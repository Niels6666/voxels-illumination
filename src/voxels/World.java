package voxels;

import utils.BindlessBuffer;
import utils.Camera;
import utils.Noise3D;
import utils.QueryBuffer;
import utils.Shader;
import utils.Texture2D;
import utils.Texture3D;
import utils.VAO;

import static org.lwjgl.opengl.GL11C.GL_LINEAR;
import static org.lwjgl.opengl.GL12C.GL_CLAMP_TO_EDGE;
import static org.lwjgl.opengl.GL46C.*;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Random;

import org.joml.Matrix3f;
import org.joml.Matrix4f;
import org.joml.Vector2i;
import org.joml.Vector3f;
import org.joml.Vector3fc;
import org.joml.Vector4f;
import org.joml.Vector4i;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;

import imgui.ImGui;
import imgui.flag.ImGuiSliderFlags;

public class World {
	
	enum Blocks{
		AIR(new Vector3f(0,0,0), 0, 0, false),
		GRASS(new Vector3f(0.3f,0.8f,0.3f), 0, 1.0f, false),
		DIRT(new Vector3f(0.3f,0.2f,0.1f), 0, 0.8f, false),
		STONE(new Vector3f(0.4f,0.4f,0.4f), 0, 0.9f, false),
		GOLD(new Vector3f(1.0f,0.71f,0.29f), 0, 0f, true),
		URANIUM(new Vector3f(0.5f, 1.0f, 0.5f), 1.0f, 0, false);
		
		private Vector3f albedo;
		private float emission_strength;
		private float roughness;
		private boolean metallic;
		
		Blocks(Vector3f albedo, float emission_strength, float roughness, boolean metallic) {
			this.albedo = albedo;
			this.emission_strength = emission_strength;
			this.roughness = roughness;
			this.metallic = metallic;
		}
		
		private byte toUINT8(float f) {
			return (byte)(((int)(f * 255.0f)) & 0xFF);
		}
		
		private void toBuff(ByteBuffer buff) {
			buff.put(toUINT8(albedo.x));
			buff.put(toUINT8(albedo.y));
			buff.put(toUINT8(albedo.z));
			buff.put(toUINT8(emission_strength));
			
			buff.put(toUINT8(roughness));
			buff.put((byte) (metallic ? 0 : 1));
			buff.put((byte)0);
			buff.put((byte)0);
		}
		
		static ByteBuffer pack() {
			ByteBuffer buff = MemoryUtil.memAlloc(8 * Blocks.values().length);
			for(var b : Blocks.values()) {
				b.toBuff(buff);
			}
			return buff;
		}
	}
	
	public boolean ShouldUpdateProbes = false;
	
	public int width; // number of tiles
	public int height;// number of tiles
	public int depth; // number of tiles
	public int maxTiles;

	public Vector3f minCorner;
	public float voxelSize;

	public Texture3D occupancy;
	public Texture3D block_ids;
	
	public Texture3D probes_occupancy;       // indices of the probes
	public Texture3D probes_lerp;            // Texture to interpolate the probes
	public BindlessBuffer probes_values;     // values of the probes
	public BindlessBuffer probes_ray_dirs;   // values of the probes
	public BindlessBuffer free_probes_stack; // stack of free probes indices
	public BindlessBuffer num_free_probes;   // pointer to an int
	public int num_free_probes_cpu;
	public BindlessBuffer probes;   // for each probe: ivec4(coords, status)
	public BindlessBuffer updated_probes_values;
	
	public BindlessBuffer block_types_buffer; // all the block properties

	public Texture3D noiseTexture;
	public Texture3D noiseColorsTexture;

	public BindlessBuffer compressed_occupancy;
	public BindlessBuffer compressed_atlas;
	
	public BindlessBuffer compressed_inside_terrain;

	public BindlessBuffer tiles; // for each tile: ivec4(coords, status)
	public BindlessBuffer free_tiles_stack; // stack of free tile indices
	public BindlessBuffer num_free_tiles; // pointer to an int
	public int num_free_tiles_cpu;
	public BindlessBuffer performanceCounters;

	public BindlessBuffer valid_probes_for_raytracing;
	public BindlessBuffer valid_probes_for_rendering;
	public BindlessBuffer num_valid_probes_for_rendering_and_raytracing;
	public Vector2i num_valid_probes_for_rendering_and_raytracing_cpu = new Vector2i();
	
	public BindlessBuffer worldUBO;

	public Shader generateShader;
	public Shader generateBlocksShader;

	public Shader debugTilesShader;
	public Shader debugProbesShader;
	public Shader debugRaysShader;
	
	public Shader renderShader;
	public Shader renderReflectionShader;
	public Shader quadShader;

	public Vector3f sunDir = new Vector3f(0.8f, 1.0f, -0.8f).normalize(); // unit direction towards the sun
	public Vector3f sunLight = new Vector3f(40.0f); // light intensity of the sun
	public float[] exposure = new float[] {1.0f};
	public float[] learningRate = new float[] {0.1f};
	public float[] smoothnessWeight = new float[] {0.1f};
	
	public Texture2D renderTexture;

//	boolean displayReflectionTexture = false;

	public Texture2D renderReflectionTexture;
	public Texture2D renderReflectionDepthTexture;

	public VAO quad;

	public BindlessBuffer debugBlockBuffer;
	
	final int MAX_PROBES_TO_UPDATE = 2048;
	final int SAMPLES_PER_PROBE = 128;

	public int probe_index_offset_raytracing = 0;
	public int probe_index_offset_smoothing = 0;
	
	public Shader allocate_probes_shader;
	public Shader init_probes_shader;
	public Shader raytrace_probes_shader;
	public Shader smooth_probes_shader;
	public Shader write_probes_lerp_shader;
	public Shader filter_valid_probes_shader;

	enum RenderOperations {
		UpdateProbes(), MainRender();

		final float[] values;

		private RenderOperations() {
			values = new float[100];
		}
	}

	public ArrayList<QueryBuffer> timer = new ArrayList<>(RenderOperations.values().length);

	public World(Vector3f minCorner, float voxelSize, int width, int height, int depth, int maxTiles) {
		this.width = width;
		this.height = height;
		this.depth = depth;

		System.out.println("Creating world with size: " + width + "x" + height + "x" + depth + " tiles.");
		System.out.println("Sparsity: " + maxTiles + " / " + width*height*depth + " = " + maxTiles / (float)(width*height*depth));

		this.minCorner = minCorner;
		this.voxelSize = voxelSize;

		assert width % 4 == 0;
		assert height % 4 == 0;
		assert depth % 4 == 0;

		occupancy = new Texture3D(GL_R32I, GL_RED_INTEGER, GL_INT, width, height, depth);
		occupancy.clear(-1);
		probes_occupancy = new Texture3D(GL_R32I, GL_RED_INTEGER, GL_INT, width+1, height+1, depth+1);
		probes_occupancy.clear(-1);

		int num_compressed_blocks = (width / 4) * (height / 4) * (depth / 4);
		compressed_occupancy = new BindlessBuffer(num_compressed_blocks * Long.BYTES, 0);
		compressed_inside_terrain = new BindlessBuffer(num_compressed_blocks * Long.BYTES, 0);

		int N = (int) Math.ceil(Math.cbrt(maxTiles));
		this.maxTiles = maxTiles = N * N * N;

		block_ids = new Texture3D(GL_R8UI, GL_RED_INTEGER, GL_UNSIGNED_BYTE, N * 4, N * 4, N * 4);
		compressed_atlas = new BindlessBuffer(this.maxTiles * Long.BYTES, 0);
		

		int sizeofIvec4 = 4 * Integer.BYTES;
		tiles = new BindlessBuffer(maxTiles * sizeofIvec4, 0);
		probes = new BindlessBuffer(maxTiles * sizeofIvec4, 0);
		
		updated_probes_values = new BindlessBuffer(MAX_PROBES_TO_UPDATE * 16 * 4 * 2, 0); // 16 coeffs, RGBA16F
		probe_index_offset_raytracing = 0;
		probe_index_offset_smoothing = 0;

		probes_lerp = new Texture3D(GL_RGBA16F, GL_RGBA, GL_FLOAT, 
				(int) (2*Math.ceil(Math.sqrt(maxTiles))), (int) (2*Math.ceil(Math.sqrt(maxTiles))), 32, 
				GL_LINEAR, GL_LINEAR, GL_REPEAT);
		
		probes_values = new BindlessBuffer(this.maxTiles * 16 * 4 * 2, 0); // 16 coeffs, RGBA16F
		{
			ByteBuffer rays = MemoryUtil.memAlloc(SAMPLES_PER_PROBE * 4 * Float.BYTES);
			for(int i=0; i<SAMPLES_PER_PROBE; i++) {
				double phi = Math.PI * (Math.sqrt(5.0) - 1.0); // golden angle in radians

				double y = 1.0 - (i / (double)(SAMPLES_PER_PROBE - 1)) * 2.0; // y goes from 1 to -1
		        double radius = Math.sqrt(1.0 - y * y); // radius at y

		        double theta = phi * i; // golden angle increment
		        double x = Math.cos(theta) * radius;
		        double z = Math.sin(theta) * radius;

		        rays.putFloat((float)x);
		        rays.putFloat((float)y);
		        rays.putFloat((float)z);
		        rays.putFloat(0.0f);
			}
			probes_ray_dirs = new BindlessBuffer(SAMPLES_PER_PROBE * 4 * Float.BYTES, 0, rays.flip()); // 64 directions, vec4s
			MemoryUtil.memFree(rays);
		}

		// 4 free tiles
		// 84 16 6 9 -1 -1 -1 -1 -1 -1 ....
		// init array with all indices in decreasing order
		// M-1, M-2, ..., 0
		ByteBuffer indices = MemoryUtil.memAlloc(maxTiles * Integer.BYTES);
		for (int i = maxTiles - 1; i >= 0; i--) {
			indices.putInt(i);
		}
		free_tiles_stack = new BindlessBuffer(maxTiles * Integer.BYTES, 0, indices.flip());
		free_probes_stack = new BindlessBuffer(maxTiles * Integer.BYTES, 0, indices);
		MemoryUtil.memFree(indices);

		// init as [M]
		ByteBuffer stack_ptr = MemoryUtil.memAlloc(1 * Integer.BYTES);
		stack_ptr.putInt(maxTiles);
		num_free_tiles = new BindlessBuffer(1 * Integer.BYTES, GL_MAP_READ_BIT, stack_ptr.flip());
		num_free_probes = new BindlessBuffer(1 * Integer.BYTES, GL_MAP_READ_BIT, stack_ptr);
		MemoryUtil.memFree(stack_ptr);
		
		ByteBuffer blocks_buff = Blocks.pack();
		block_types_buffer = new BindlessBuffer(blocks_buff.capacity(), 0, blocks_buff.flip());
		MemoryUtil.memFree(blocks_buff);
		
		valid_probes_for_raytracing = new BindlessBuffer(maxTiles * Integer.BYTES, 0);
		valid_probes_for_rendering = new BindlessBuffer(maxTiles * Integer.BYTES, 0);
		num_valid_probes_for_rendering_and_raytracing = new BindlessBuffer(2 * Integer.BYTES, GL_MAP_READ_BIT);
		
		
		prepareWorldUBO();
		loadShaders();
		generateNoiseTextures();

		quad = new VAO();
		quad.bind();
		float positions[] = { -1.0f, 1.0f, -1.0f, -1.0f, 1.0f, 1.0f, 1.0f, -1.0f };
		quad.createFloatAttribute(0, positions, 2, 0, GL_STATIC_DRAW);
		quad.unbind();

		timer.add(new QueryBuffer(GL_TIME_ELAPSED, 10));
		timer.add(new QueryBuffer(GL_TIME_ELAPSED, 10));
		
		prepareDebugBlock();
	}

	private void loadShaders() {
		generateShader = new Shader("shaders/generate.glsl");
		generateShader.finishInit();
		generateShader.init_uniforms("noiseTexHandle");

		generateBlocksShader = new Shader("shaders/generateBlocks.glsl");
		generateBlocksShader.finishInit();
		generateBlocksShader.init_uniforms("noiseTexHandle");

		debugTilesShader = new Shader("shaders/debug_tiles_vertex_shader.glsl", "shaders/debug_tiles_geometry_shader.glsl",
				"shaders/debug_tiles_fragment_shader.glsl");
		debugTilesShader.finishInit();
		debugTilesShader.init_uniforms("projectionView", "level");
		
		debugProbesShader = new Shader(
				"shaders/debug_probes_vertex_shader.glsl", 
				"shaders/debug_probes_geometry_shader.glsl", 
				"shaders/debug_probes_fragment_shader.glsl");
		debugProbesShader.finishInit();
		debugProbesShader.init_uniforms("projectionView");
		
		debugRaysShader = new Shader(
				"shaders/debug_rays_vertex_shader.glsl", 
				"shaders/debug_rays_geometry_shader.glsl", 
				"shaders/debug_rays_fragment_shader.glsl");
		debugRaysShader.finishInit();
		debugRaysShader.init_uniforms("projectionView", "selected_probe");

		renderShader = new Shader("shaders/render.glsl");
		renderShader.finishInit();
		renderShader.init_uniforms("K", "ViewMatrix", "RenderImageHandle", "sunDir", "sunLight", "exposure");

//		renderReflectionShader = new Shader("shaders/render_reflection.glsl");
//		renderReflectionShader.finishInit();
//		renderReflectionShader.init_uniforms("K", "ViewMatrix", "RenderImageHandle", "RenderDepthImageHandle",
//				"RenderNormalImageHandle", "RenderReflectionImageHandle", "RenderReflectionDepthImageHandle",
//				"RenderReflectionNormalImageHandle", "maxCorner", "light_pos", "light_color", "light_cubemap_handle");

		quadShader = new Shader("shaders/quad_vs.glsl", "shaders/quad_fs.glsl");
		quadShader.finishInit();
		quadShader.init_uniforms("ImageHandle");

		allocate_probes_shader = new Shader("shaders/allocate_probes.glsl");
		allocate_probes_shader.finishInit();
		init_probes_shader = new Shader("shaders/init_probes.glsl");
		init_probes_shader.finishInit();
		init_probes_shader.init_uniforms("noiseTexHandle");
		raytrace_probes_shader = new Shader("shaders/raytrace_probes.glsl");
		raytrace_probes_shader.finishInit();
		raytrace_probes_shader.init_uniforms("random_rotation", "probe_index_offset", "sunDir", "sunLight", "LearningRate");
		smooth_probes_shader = new Shader("shaders/smooth_probes.glsl");
		smooth_probes_shader.finishInit();
		smooth_probes_shader.init_uniforms("probe_index_offset", "LearningRate", "SmoothnessWeight");
		write_probes_lerp_shader = new Shader("shaders/write_probes_lerp.glsl");
		write_probes_lerp_shader.finishInit();
		write_probes_lerp_shader.init_uniforms("probe_index_offset", "num_updated_probes", "raytracing_or_smoothing");
		filter_valid_probes_shader = new Shader("shaders/filter_valid_probes.glsl");
		filter_valid_probes_shader.finishInit();
		
	}

	public Vector3f toGridCoords(Vector3fc worldCoords) {
		return new Vector3f(worldCoords).sub(minCorner).div(voxelSize);
	}

	public Vector3f toWorldCoords(Vector3fc voxelCoords) {
		return new Vector3f(voxelCoords).mul(voxelSize).add(minCorner);
	}

	private void generateNoiseTextures() {
		noiseTexture = new Texture3D(GL_R16F, GL_RED, GL_FLOAT, 32, 32, 32, GL_LINEAR, GL_LINEAR, GL_REPEAT);
		noiseColorsTexture = new Texture3D(GL_RGBA16F, GL_RGBA, GL_FLOAT, 16, 16, 16, GL_LINEAR, GL_LINEAR, GL_REPEAT);

		Random random = new Random(System.currentTimeMillis());
		float maxValue = 1f, minValue = -1f;
		float amplitude = maxValue - minValue;
		int length = 32 * 32 * 32 * 4;
		ByteBuffer noiseBuff = MemoryUtil.memAlloc(length);
		for (int i = 0; i < length / 4; i++) {
			noiseBuff.putFloat(amplitude * random.nextFloat() + minValue);
		}
		noiseTexture.uploadData(noiseBuff.flip(), GL_RED, GL_FLOAT);
		MemoryUtil.memFree(noiseBuff);

		ByteBuffer color_noise = MemoryUtil.memAlloc(16 * 16 * 16 * 4 * 4);
		for (int i = 0; i < 16 * 16 * 16 * 4; i++) {
			color_noise.putFloat(random.nextFloat()*1.0f);
		}
		noiseColorsTexture.uploadData(color_noise.flip(), GL_RGBA, GL_FLOAT);

	}

	/**
	 * increments the position by 12
	 */
	private void putVec3(ByteBuffer buf, Vector3f v) {
		buf.putFloat(v.x);
		buf.putFloat(v.y);
		buf.putFloat(v.z);
	}

	public void prepareWorldUBO() {
		MemoryStack stack = MemoryStack.stackPush();
		ByteBuffer bigbuffer = stack.malloc(16, 16 * 16);

		bigbuffer.putInt(width);
		bigbuffer.putInt(height);
		bigbuffer.putInt(depth);
		bigbuffer.putInt(maxTiles);

		putVec3(bigbuffer, minCorner);
		bigbuffer.putFloat(voxelSize);

		occupancy.writeHandle(bigbuffer);
		block_ids.writeHandle(bigbuffer);
		
		probes_occupancy.writeHandle(bigbuffer);
		probes_lerp.writeHandle(bigbuffer);
		probes_values.writePointer(bigbuffer);
		probes_ray_dirs.writePointer(bigbuffer);
		free_probes_stack.writePointer(bigbuffer);
		num_free_probes.writePointer(bigbuffer);
		
		probes.writePointer(bigbuffer);
		updated_probes_values.writePointer(bigbuffer);
		
		block_types_buffer.writePointer(bigbuffer);
		bigbuffer.putInt(Blocks.values().length);
		int probes_lerp_half_size = (int)Math.ceil(Math.sqrt(maxTiles));
		bigbuffer.putInt(probes_lerp_half_size);

		compressed_occupancy.writePointer(bigbuffer);
		compressed_atlas.writePointer(bigbuffer);

		tiles.writePointer(bigbuffer);
		free_tiles_stack.writePointer(bigbuffer);

		num_free_tiles.writePointer(bigbuffer);
		int atlas_tile_size = block_ids.width / 4;
		bigbuffer.putInt(atlas_tile_size);
		bigbuffer.putInt(0);

		if (performanceCounters != null) {
			performanceCounters.delete();
		}
		performanceCounters = new BindlessBuffer(4 * Integer.BYTES, 0, null);
		performanceCounters.writePointer(bigbuffer);
		compressed_inside_terrain.writePointer(bigbuffer);
		
		valid_probes_for_rendering.writePointer(bigbuffer);
		valid_probes_for_raytracing.writePointer(bigbuffer);
		
		bigbuffer.putLong(num_valid_probes_for_rendering_and_raytracing.ptr);
		bigbuffer.putLong(num_valid_probes_for_rendering_and_raytracing.ptr + Integer.BYTES);

		long size = bigbuffer.position();
		if (worldUBO != null) {
			worldUBO.delete();
		}
		worldUBO = new BindlessBuffer(size, 0, bigbuffer.flip());
		glBindBufferBase(GL_UNIFORM_BUFFER, 0, worldUBO.ID);
		stack.pop();
	}

	public void generate() {
		generateShader.start();
		generateShader.loadUInt64("noiseTexHandle", noiseTexture.tex_handle);
		glDispatchCompute(width, height, depth);
		glMemoryBarrier(GL_ALL_BARRIER_BITS);
		generateShader.stop();

		generateBlocksShader.start();
		generateBlocksShader.loadUInt64("noiseTexHandle", noiseColorsTexture.tex_handle);
		glDispatchCompute(maxTiles, 1, 1);
		glMemoryBarrier(GL_ALL_BARRIER_BITS);
		generateBlocksShader.stop();
		
		allocate_probes_shader.start();
		glDispatchCompute((maxTiles+7)/8, 1, 1);
		glMemoryBarrier(GL_ALL_BARRIER_BITS);
		allocate_probes_shader.stop();
		
		filter_valid_probes_shader.start();
		glDispatchCompute((maxTiles+63)/64, 1, 1);
		glMemoryBarrier(GL_ALL_BARRIER_BITS);
		filter_valid_probes_shader.stop();
		
//		init_probes_shader.start();
//		init_probes_shader.loadUInt64("noiseTexHandle", noiseColorsTexture.tex_handle);
//		glDispatchCompute((maxTiles+3)/4, 1, 1);
//		glMemoryBarrier(GL_ALL_BARRIER_BITS);
//		init_probes_shader.stop();

		ByteBuffer buff = glMapNamedBuffer(num_free_tiles.ID, GL_READ_ONLY);
		num_free_tiles_cpu = buff.getInt();
		glUnmapNamedBuffer(num_free_tiles.ID);
		
		buff = glMapNamedBuffer(num_free_probes.ID, GL_READ_ONLY);
		num_free_probes_cpu = buff.getInt();
		glUnmapNamedBuffer(num_free_probes.ID);

		buff = glMapNamedBuffer(num_valid_probes_for_rendering_and_raytracing.ID, GL_READ_ONLY);
		num_valid_probes_for_rendering_and_raytracing_cpu.x = buff.getInt();
		num_valid_probes_for_rendering_and_raytracing_cpu.y = buff.getInt();
		glUnmapNamedBuffer(num_valid_probes_for_rendering_and_raytracing.ID);
		
	}

	public void renderBoxesDebug(Camera camera, int level) {
		debugTilesShader.start();
		Matrix4f projview = camera.getProjectionMatrix().mul(camera.getViewMatrix(), new Matrix4f());
		debugTilesShader.loadMat4("projectionView", projview);
		debugTilesShader.loadInt("level", level);

		int N = 0;
		if (level == 0) {
			// number of super tiles
			N = (width / 4) * (height / 4) * (depth / 4);
		} else if (level == 1) {
			// number of tiles
			N = maxTiles;
		} else {
			// number of voxels
			N = maxTiles * 64;
		}

		VAO vao = new VAO();
		vao.bind();
		glDrawArrays(GL_POINTS, 0, N);
		vao.unbind();
		vao.delete();

		debugTilesShader.stop();
	}

	public void renderProbesDebug(Camera camera) {
		debugProbesShader.start();
		Matrix4f projview = camera.getProjectionMatrix().mul(camera.getViewMatrix(), new Matrix4f());
		debugProbesShader.loadMat4("projectionView", projview);

		VAO vao = new VAO();
		vao.bind();
		glPointSize(3);
		glDrawArrays(GL_POINTS, 0, maxTiles);
		vao.unbind();
		vao.delete();

		debugProbesShader.stop();
	}

	public void renderRaysDebug(Camera camera) {
//		debugRaysShader.start();
//		Matrix4f projview = camera.getProjectionMatrix().mul(camera.getViewMatrix(), new Matrix4f());
//		debugRaysShader.loadMat4("projectionView", projview);
//		debugRaysShader.loadInt("selected_probe", probe_index_offset);
//		
//		VAO vao = new VAO();
//		vao.bind();
//		glLineWidth(1);
//		glDrawArrays(GL_POINTS, 0, SAMPLES_PER_PROBE);
//		vao.unbind();
//		vao.delete();
//
//		debugRaysShader.stop();
//		
	}
	
	private void updatePerformanceCounters() {
		try (MemoryStack stack = MemoryStack.stackPush()) {
			IntBuffer ints = stack.mallocInt((int) (performanceCounters.size_bytes / 4));
			glGetNamedBufferSubData(performanceCounters.ID, 0, ints);

			float mainWindowIterationCount = ints.get(0);
			float mainWindowValidPixels = ints.get(1);
			float mainWindowPixelsInBoundingBox = ints.get(2);

			ImGui.text(String.format("Average iterations: %.1f",
					mainWindowIterationCount / mainWindowPixelsInBoundingBox));
			if (renderTexture != null) {
				ImGui.text(String.format("Valid pixels: %.3f",
						mainWindowValidPixels / (renderTexture.width * renderTexture.height)));
			}

		}
		// clear the buffer
		try (MemoryStack s = MemoryStack.stackPush()) {
			IntBuffer idbuff = s.callocInt(1);
			glClearNamedBufferData(performanceCounters.ID, GL_R32I, GL_RED_INTEGER, GL_INT, idbuff);
		}

	}

	public void render(Camera camera) {
		
		if(ShouldUpdateProbes) {
			updateProbes(true, true);
		}

		var q = timer.get(RenderOperations.MainRender.ordinal()).push_back();
		q.begin();

		int w = camera.window_width;
		int h = camera.window_height;

		if (renderTexture == null || renderTexture.width != w || renderTexture.height != h) {
			if (renderTexture != null) {
				renderTexture.delete();
				renderReflectionTexture.delete();
				renderReflectionDepthTexture.delete();
			}
			renderTexture = new Texture2D(GL_RGBA16F, GL_RGBA, GL_FLOAT, w, h, GL_LINEAR, GL_LINEAR, GL_CLAMP_TO_EDGE);
			renderReflectionTexture = new Texture2D(GL_RGBA16F, GL_RGBA, GL_FLOAT, w, h, GL_LINEAR, GL_LINEAR,
					GL_CLAMP_TO_EDGE);
			renderReflectionDepthTexture = new Texture2D(GL_RGBA32F, GL_RGBA, GL_FLOAT, w, h, GL_LINEAR, GL_LINEAR,
					GL_CLAMP_TO_EDGE);
		}

		var P = camera.getProjectionMatrix();
		var V = new Matrix4f(camera.getViewMatrix());

		float a = P.m00();
		float b = P.m11();
		var K = new Vector4f(a * w / 2f, b * h / 2f, w / 2f, h / 2f);

		renderShader.start();
		renderShader.loadVec4("K", K);
		renderShader.loadMat4("ViewMatrix", V);
		renderShader.loadUInt64("RenderImageHandle", renderTexture.img_handle);

		renderShader.loadVec3("sunDir", sunDir);
		renderShader.loadVec3("sunLight", sunLight);
		renderShader.loadFloat("exposure", exposure[0]);
		glDispatchCompute((w + 7) / 8, (h + 7) / 8, 1);
		renderShader.stop();
		glMemoryBarrier(GL_ALL_BARRIER_BITS);

//		renderReflectionShader.start();
//		renderReflectionShader.loadVec4("K", K);
//		renderReflectionShader.loadMat4("ViewMatrix", V);
//		renderReflectionShader.loadUInt64("RenderImageHandle", renderTexture.img_handle);
//		renderReflectionShader.loadUInt64("RenderDepthImageHandle", renderDepthTexture.img_handle);
//		renderReflectionShader.loadUInt64("RenderNormalImageHandle", renderNormalTexture.img_handle);
//		renderReflectionShader.loadUInt64("RenderReflectionImageHandle", renderReflectionTexture.img_handle);
//		renderReflectionShader.loadUInt64("RenderReflectionDepthImageHandle", renderReflectionDepthTexture.img_handle);
//
//		renderReflectionShader.loadVec3("maxCorner", new Vector3f(width, height, depth).mul(4f));
//		renderReflectionShader.loadVec3("light_pos", sun.position);
//		renderReflectionShader.loadVec3("light_color", sun.color);
//		renderReflectionShader.loadUInt64("light_cubemap_handle", sun.cubeMap.tex_handle);
//		glDispatchCompute((w + 7) / 8, (h + 7) / 8, 1);
//		renderReflectionShader.stop();
//		glMemoryBarrier(GL_ALL_BARRIER_BITS);

		q.end();

	}
	
	private Vector3f randomUnitVec3() {
		double theta = Math.random() * 2.0 * Math.PI; // in [0, 2pi]
		double z = Math.random() * 2.0 - 1.0; // in [-1, 1]
		float zbar = (float)Math.sqrt(1.0 - z*z);
		return new Vector3f(zbar * (float)Math.cos(theta), zbar * (float)Math.sin(theta), (float)z);
	}
	
	private Matrix4f randomRotation() {
		Vector3f v0 = randomUnitVec3();
		Vector3f v1 = randomUnitVec3();
		Vector3f v2 = v0.cross(v1, new Vector3f()).normalize();
		v2.cross(v0, v1).normalize();
		Matrix3f m = new Matrix3f(v0, v1, v2);
		return new Matrix4f(m);
	}
	
	public void updateProbes(boolean raytrace, boolean smooth) {
		var q = timer.get(RenderOperations.UpdateProbes.ordinal()).push_back();
		q.begin();
		
		if(raytrace) {
			raytrace_probes_shader.start();
			raytrace_probes_shader.loadMat4("random_rotation", randomRotation());
			raytrace_probes_shader.loadInt("probe_index_offset", probe_index_offset_raytracing);
			raytrace_probes_shader.loadVec3("sunDir", sunDir);
			raytrace_probes_shader.loadVec3("sunLight", sunLight);
			raytrace_probes_shader.loadFloat("LearningRate", learningRate[0]);
			glDispatchCompute(MAX_PROBES_TO_UPDATE, 1, 1);
			glMemoryBarrier(GL_ALL_BARRIER_BITS);
			raytrace_probes_shader.stop();
			
			write_probes_lerp_shader.start();
			write_probes_lerp_shader.loadInt("probe_index_offset", probe_index_offset_raytracing);
			write_probes_lerp_shader.loadInt("num_updated_probes", MAX_PROBES_TO_UPDATE);
			write_probes_lerp_shader.loadInt("raytracing_or_smoothing", 0);
			glDispatchCompute((MAX_PROBES_TO_UPDATE + 3) / 4, 1, 1);
			glMemoryBarrier(GL_ALL_BARRIER_BITS);
			write_probes_lerp_shader.stop();

			probe_index_offset_raytracing = (probe_index_offset_raytracing + MAX_PROBES_TO_UPDATE) % num_valid_probes_for_rendering_and_raytracing_cpu.y;
		}
		
		if(smooth) {
			smooth_probes_shader.start();
			smooth_probes_shader.loadInt("probe_index_offset", probe_index_offset_smoothing);
			smooth_probes_shader.loadFloat("LearningRate", learningRate[0]);
			smooth_probes_shader.loadFloat("SmoothnessWeight", smoothnessWeight[0]);
			glDispatchCompute((MAX_PROBES_TO_UPDATE + 3) / 4, 1, 1);
			glMemoryBarrier(GL_ALL_BARRIER_BITS);
			smooth_probes_shader.stop();
			
			write_probes_lerp_shader.start();
			write_probes_lerp_shader.loadInt("probe_index_offset", probe_index_offset_smoothing);
			write_probes_lerp_shader.loadInt("num_updated_probes", MAX_PROBES_TO_UPDATE);
			write_probes_lerp_shader.loadInt("raytracing_or_smoothing", 1);
			glDispatchCompute((MAX_PROBES_TO_UPDATE + 3) / 4, 1, 1);
			glMemoryBarrier(GL_ALL_BARRIER_BITS);
			write_probes_lerp_shader.stop();
			
			probe_index_offset_smoothing = (probe_index_offset_smoothing + MAX_PROBES_TO_UPDATE) % num_valid_probes_for_rendering_and_raytracing_cpu.x;
		}
		
		
		q.end();
	}

	public void onscreenDraw() {
		quadShader.start();
		quadShader.loadUInt64("ImageHandle", renderTexture.img_handle);
		quad.bind();
		quad.bindAttribute(0);
		glDisable(GL_DEPTH_TEST);
		glDisable(GL_CULL_FACE);
		glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
		glEnable(GL_CULL_FACE);
		glEnable(GL_DEPTH_TEST);
		quad.unbindAttribute(0);
		quad.unbind();
		quadShader.stop();
	}

	public void prepareDebugBlock() {

		// struct debugStruct{
		// int line; // line of the error
		// int index; // index of the error
		// int size; // size of the buffer
		// int floatData; // 1 if the debug info should be interpreted as ints, 2 if the
		// debug info should be interpreted as floats
		// ivec4 data; // additional debug info
		// };
		int debugStructSize = 8 * 4;

		// struct debugBlockLayout{
		// uint32_t debugStructsCount;
		// uint32_t debugStructsPadding0;
		// uint32_t debugStructsPadding1;
		// uint32_t debugStructsPadding2;
		// ivec4 debugStructsPadding3;
		// debugStruct debugStructsArray[128];
		// };
		int debugBlockSize = 4 + 4 + 4 + 4 + 4 * 4 + 128 * debugStructSize;

		if (debugBlockBuffer != null) {
			debugBlockBuffer.delete();
		}
		debugBlockBuffer = new BindlessBuffer(debugBlockSize, GL_MAP_READ_BIT);
		glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 15, debugBlockBuffer.ID);
	}

	public boolean checkErrors() {
		boolean error = false;
		glMemoryBarrier(GL_ALL_BARRIER_BITS);
		ByteBuffer buff = glMapNamedBuffer(debugBlockBuffer.ID, GL_READ_ONLY);

		int debugStructsCount = buff.getInt();
		buff.getInt();
		buff.getInt();
		buff.getInt();
		buff.position(buff.position() + 4 * 4);

		if (debugStructsCount > 0) {
			System.out.println("Found " + debugStructsCount + " errors in the debug buffer");

			for (int i = 0; i < Math.min(debugStructsCount, 10); i++) {
				int line = buff.getInt();
				int index = buff.getInt();
				int size = buff.getInt();
				int floatData = buff.getInt();

				System.out.println("Line: " + line + " index: " + index + " size: " + size);

				if (floatData == 1) {
					Vector4i data = new Vector4i(buff);
					System.out.println("data: " + data.x + " " + data.y + " " + data.z + " " + data.w);
				} else if (floatData == 2) {
					Vector4f data = new Vector4f(buff);
					System.out.println("data: " + data.x + " " + data.y + " " + data.z + " " + data.w);
				}
				buff.position(buff.position() + 4 * 4);
			}
			error = true;
			System.out.println("");
		}
		glUnmapNamedBuffer(debugBlockBuffer.ID);
		prepareDebugBlock();
		return error;
	}

	public void delete() {
		occupancy.delete();
		probes_occupancy.delete();
		
		probes_lerp.delete();
		probes_values.delete();
		updated_probes_values.delete();
		probes_ray_dirs.delete();
		
		block_ids.delete();
		block_types_buffer.delete();
		noiseTexture.delete();
		noiseColorsTexture.delete();
		renderTexture.delete();
		compressed_occupancy.delete();
		compressed_atlas.delete();
		compressed_inside_terrain.delete();
		tiles.delete();
		probes.delete();
		free_tiles_stack.delete();
		num_free_tiles.delete();
		free_probes_stack.delete();
		num_free_probes.delete();
		
		valid_probes_for_raytracing.delete();
		valid_probes_for_rendering.delete();
		num_valid_probes_for_rendering_and_raytracing.delete();
		
		worldUBO.delete();
		performanceCounters.delete();
		deleteShaders();
	}

	private void deleteShaders() {
		generateShader.delete();
		generateBlocksShader.delete();
		debugTilesShader.delete();
		renderShader.delete();
		quadShader.delete();
		quad.delete();
	}

	public void reloadShaders() {
		deleteShaders();
		System.out.println("reloading shaders");
		loadShaders();
	}

	public void layout() {

		ImGui.separator();
		
		ImGui.textColored(0.0f, 0.8f, 0.2f, 1.0f, "World size: " + width + "x" + height + "x" + depth + " tiles.");
		ImGui.textColored(0.0f, 0.8f, 0.2f, 1.0f, "Tiles usage: " + (maxTiles-num_free_tiles_cpu) + " / " + maxTiles + " tiles.");
		ImGui.textColored(0.0f, 0.8f, 0.2f, 1.0f, "Probes usage: " + (maxTiles-num_free_probes_cpu) + " / " + maxTiles + " probes.");
		
		
		ImGui.sliderFloat("Exposure", exposure, 0.1f, 10.0f, "%.2f", ImGuiSliderFlags.Logarithmic);
		
		ImGui.textColored(0.0f, 0.8f, 0.2f, 1.0f, "Probes raytracing offset: " + probe_index_offset_raytracing + " / " + num_valid_probes_for_rendering_and_raytracing_cpu.y + " probes.");
		ImGui.textColored(0.0f, 0.8f, 0.2f, 1.0f, "Probes smoohting offset: " + probe_index_offset_smoothing + " / " + num_valid_probes_for_rendering_and_raytracing_cpu.x + " probes.");
		
		if(ImGui.checkbox("Update Probes", ShouldUpdateProbes)) {
			ShouldUpdateProbes = !ShouldUpdateProbes;
		}
		
		ImGui.sliderFloat("Learning Rate", learningRate, 0.01f, 0.75f);
		ImGui.sliderFloat("Smoothness Weight", smoothnessWeight, 0.1f, 2f);

		
		for (int q = 0; q < timer.size(); q++) {
			var renderOP = RenderOperations.values()[q];
			float time = (float) (timer.get(q).getLastResult(true) * 1.0E-6);
//			renderOP.max = Math.max(renderOP.max, time);
			int len = renderOP.values.length;
			float[] temp = Arrays.copyOfRange(renderOP.values, 1, len + 1);
			temp[len - 1] = time;
			ImGui.plotLines(String.format(renderOP.name() + " %.3f ms", time), temp, len, 0, "", 0f, 4f, 200, 40);
			System.arraycopy(temp, 0, renderOP.values, 0, len);
		}

//		ImGui.text("sun position :");
//		float[] temp = new float[] { sun.position.x, sun.position.y, sun.position.z };
//		ImGui.sliderFloat3("xyz", temp, minCorner.x, minCorner.x + width * 4f * voxelSize);
//		sun.position.set(temp);
		updatePerformanceCounters();
	}
}
