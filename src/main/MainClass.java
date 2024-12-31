package main;

import static org.lwjgl.glfw.GLFW.*;
import static org.lwjgl.system.MemoryUtil.*;

import java.io.File;
import java.io.IOException;
import java.nio.DoubleBuffer;
import java.nio.IntBuffer;
import java.nio.file.FileSystem;
import java.nio.file.FileSystems;
import java.nio.file.Path;
import java.nio.file.StandardWatchEventKinds;
import java.nio.file.WatchEvent;
import java.nio.file.WatchEvent.Kind;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;

import org.joml.Vector2d;
import org.joml.Vector3d;
import org.joml.Vector3f;
import org.joml.Vector3fc;
import org.joml.Vector4f;
import org.lwjgl.glfw.GLFWErrorCallback;
import org.lwjgl.system.MemoryStack;

import static org.lwjgl.opengl.GL.*;
import static org.lwjgl.opengl.GL46C.*;

import imgui.ImGui;
import imgui.app.Application;
import imgui.app.Configuration;
import utils.Camera;
import utils.Shader;
import voxels.Bloom;
import voxels.World;

public class MainClass extends Application {
	boolean renderBoxesDebug = false;
	boolean renderProbesDebug = false;
	boolean renderRaysDebug = false;
	int debugLevels[] = new int[1];
	boolean events = true;

	World world;
	Bloom bloom;
	Camera camera;

	boolean vsync = true;

	private int frameWidth;
	private int frameHeight;
	
	private int MAX_TILES = 1<<19;

	public static void main(String args[]) {
		launch(new MainClass());
	}

	@Override
	protected void configure(Configuration config) {
		config.setTitle("voxels !");
	}

	@Override
	protected void initWindow(Configuration config) {
		GLFWErrorCallback.createPrint(System.err).set();

		if (!glfwInit())
			throw new IllegalStateException("Failed to initialize GLFW");

		glfwDefaultWindowHints();
		glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
		glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
		glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
		glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
		glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
		glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE);
		glfwWindowHint(GLFW_DECORATED, GLFW_TRUE);
		glfwWindowHint(GLFW_SCALE_TO_MONITOR, GLFW_TRUE);
		glfwWindowHint(GLFW_SAMPLES, 8);

		handle = glfwCreateWindow(640, 300, "voxels !", NULL, NULL);

		if (handle == NULL) {
			glfwTerminate();
			throw new NullPointerException("Window pointer is NULL");
		}

		glfwMakeContextCurrent(handle);
		createCapabilities();

		glfwShowWindow(handle);
		glfwSwapInterval(vsync ? 1 : 0);

		if (config.isFullScreen()) {
			glfwMaximizeWindow(handle);
		} else {
			glfwShowWindow(handle);
		}

		glClearColor(colorBg.getRed(), colorBg.getGreen(), colorBg.getBlue(), colorBg.getAlpha());
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	}

	@Override
	protected void preRun() {
		int major = glGetInteger(GL_MAJOR_VERSION);
		int minor = glGetInteger(GL_MINOR_VERSION);
		String renderer = glGetString(GL_RENDERER);

		System.out.println("Renderer: " + renderer);
		System.out.println("OpenGL version: " + major + "." + minor);

		world = new World(new Vector3f(-4 * 4, -4 * 4, -4 * 4), 2f / 64f, 4 * 64, 4 * 64, 4 * 64, MAX_TILES);
		world.generate();
		bloom = new Bloom();
		camera = new Camera(handle);
	}

	@Override
	public void process() {
		Shader.updateFolderWatch();
		layoutGUI();
		MemoryStack stack = MemoryStack.stackPush();
		IntBuffer width = stack.mallocInt(1);
		IntBuffer height = stack.mallocInt(1);
		glfwGetFramebufferSize(handle, width, height);
		frameWidth = width.get(0);
		frameHeight = height.get(0);
		stack.pop();

		glViewport(0, 0, frameWidth, frameHeight);
		camera.updateView(frameWidth, frameHeight, events);
		world.render(camera);
//		bloom.applyBloom(world.renderReflectionTexture);
		world.onscreenDraw();
		
		if (renderBoxesDebug) {
			world.renderBoxesDebug(camera, debugLevels[0]);
		}
		if(renderProbesDebug) {
			world.renderProbesDebug(camera);
		}
		if(renderRaysDebug) {
			world.renderRaysDebug(camera);
		}
		
	}

	private void layoutGUI() {
		Vector3fc pos = camera.getCameraPos();
		if (ImGui.checkbox("Vsync", vsync)) {
			vsync = !vsync;
			glfwSwapInterval(vsync ? 1 : 0);
		}
		ImGui.text("camera pos: (" + pos.x() + ";" + pos.y() + ";" + pos.z() + ")");
		if (ImGui.checkbox("free camera", camera.freeCam)) {
			camera.freeCam = !camera.freeCam;
		}
		if(ImGui.button("reset camera")) {
			camera.reset();
		}
		if (ImGui.checkbox("render boxes", renderBoxesDebug)) {
			renderBoxesDebug = !renderBoxesDebug;
		}
		if (renderBoxesDebug) {
			ImGui.sliderInt("debug level", debugLevels, 0, 2);
		}
		if (ImGui.checkbox("render probes", renderProbesDebug)) {
			renderProbesDebug = !renderProbesDebug;
		}
		if (ImGui.checkbox("render rays", renderRaysDebug)) {
			renderRaysDebug = !renderRaysDebug;
		}
		
		world.layout();
//		bloom.layout();
		events = !ImGui.isWindowHovered() && !ImGui.isWindowFocused();
		
		ImGui.separator();
		
		if(ImGui.button("!!! REGENERATE WORLD !!!")) {
			world.delete();
			world = new World(new Vector3f(-4 * 2, -4 * 2, -4 * 2), 2f / 64f, 2 * 64, 2 * 64, 2 * 64, MAX_TILES);
			world.generate();
		}
	}

	@Override
	protected void postRun() {
		world.delete();
	}
}
