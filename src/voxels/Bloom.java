package voxels;

import java.util.ArrayList;

import java.util.List;
import imgui.flag.*;
import imgui.ImGui;
import utils.Shader;
import utils.Texture2D;

import static org.lwjgl.opengl.GL46C.*;

public class Bloom {
	boolean bloomEffect = false;

	Shader downScale;
	Shader upScale;
	Shader toneMapping;

	public List<Texture2D> bloomTextures = new ArrayList<>();
	float[] exposure = new float[] { 1f };
	int renderWidth;
	int renderHeight;

	float[] weight = new float[] { 0.1f };

	public Bloom() {
		downScale = new Shader("shaders/downScale.glsl");
		downScale.finishInit();
		downScale.init_uniforms("input_TextureHandle", "output_ImageHandle");
		upScale = new Shader("shaders/upScale.glsl");
		upScale.finishInit();
		upScale.init_uniforms("input_TextureHandle", "output_ImageHandle", "weight", "num_cascades", "cascade_index");
		toneMapping = new Shader("shaders/tone_mapping.glsl");
		toneMapping.finishInit();
		toneMapping.init_uniforms("input_ImageHandle", "output_ImageHandle", "exposure");
	}

	public void applyBloom(Texture2D renderTexture) {
		if (!bloomEffect) {
			return;
		}

		if (bloomTextures.isEmpty() || renderTexture.width != renderWidth || renderTexture.height != renderHeight) {
			renderWidth = renderTexture.width;
			renderHeight = renderTexture.height;
			bloomTextures.forEach(Texture2D::delete);
			bloomTextures.clear();
			int width = renderTexture.width;
			int height = renderTexture.height;
			while (true) {
				width /= 2;
				height /= 2;
				bloomTextures.add(new Texture2D(GL_RGBA16F, GL_RGBA, GL_FLOAT, width, height, GL_LINEAR, GL_LINEAR,
						GL_CLAMP_TO_EDGE));
				if (width < 8 || height < 8) {
					break;
				}
			}
		}

		downScale.start();
		for (int i = 0; i < bloomTextures.size() - 1; i++) {
			Texture2D input = i == 0 ? renderTexture : bloomTextures.get(i - 1);
			Texture2D output = bloomTextures.get(i);
			downScale.loadUInt64("input_TextureHandle", input.tex_handle);
			downScale.loadUInt64("output_ImageHandle", output.img_handle);
			glDispatchCompute((output.width + 15) / 16, (output.height + 15) / 16, 1);
			glMemoryBarrier(GL_ALL_BARRIER_BITS);
		}
		downScale.stop();

		int N = bloomTextures.size();
		upScale.start();
		upScale.loadInt("num_cascades", N);
		for (int i = bloomTextures.size() - 1; i >= 0; i--) {
			upScale.loadFloat("weight", i == 0 ? weight[0] : 1.0f);
			upScale.loadInt("cascade_index", i);
			Texture2D input = bloomTextures.get(i);
			Texture2D output = i == 0 ? renderTexture : bloomTextures.get(i - 1);
			upScale.loadUInt64("input_TextureHandle", input.tex_handle);
			upScale.loadUInt64("output_ImageHandle", output.img_handle);
			glDispatchCompute((output.width + 15) / 16, (output.height + 15) / 16, 1);
			glMemoryBarrier(GL_ALL_BARRIER_BITS);
		}
		upScale.stop();

		toneMapping.start();
		toneMapping.loadUInt64("input_ImageHandle", renderTexture.img_handle);
		toneMapping.loadUInt64("output_ImageHandle", renderTexture.img_handle);
		toneMapping.loadFloat("exposure", exposure[0]);
		glDispatchCompute((renderTexture.width + 15) / 16, (renderTexture.height + 15) / 16, 1);
		glMemoryBarrier(GL_ALL_BARRIER_BITS);
		toneMapping.stop();
	}

	public void layout() {
		ImGui.separator();
		if (ImGui.checkbox("bloom effect", bloomEffect)) {
			bloomEffect = !bloomEffect;
		}
		if (bloomEffect) {
			ImGui.sliderFloat("weight", weight, 0, 1, "%.3f", ImGuiSliderFlags.Logarithmic);
			ImGui.sliderFloat("exposure", exposure, 0.1f, 10.0f, "%.3f", ImGuiSliderFlags.Logarithmic);
		}
	}
}
