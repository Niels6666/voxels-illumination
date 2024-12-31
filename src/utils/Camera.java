package utils;

import static org.lwjgl.glfw.GLFW.*;
import org.joml.Matrix4f;
import org.joml.Matrix4fc;
import org.joml.Vector2f;
import org.joml.Vector2fc;
import org.joml.Vector3f;
import org.joml.Vector3fc;
import org.joml.Vector4f;
import org.lwjgl.glfw.GLFW;

public class Camera {
	private static final float NEAR_PLANE = 0.1f;
	private static final float FAR_PLANE = 10000f;
	private static final float camSpeed = 1f / 60f;
	private static final float FOV_Y = (float) Math.toRadians(60);
	private static final float EPSILON = 1.0E-6f;

	float d = 3.0f;
	float theta = 0.0f;
	float phi = 0.0f;

	public int window_width;
	public int window_height;

	Matrix4f viewMat = new Matrix4f();
	Matrix4f invViewMat = new Matrix4f();
	Matrix4f projMat = new Matrix4f();
	Vector3f camPos = new Vector3f();
	Vector3f camDir = new Vector3f();
	Vector2f mousePrev = new Vector2f();
	Vector2f mouseNDC = new Vector2f();
	public boolean freeCam = true;

	private float scroll = 0;
	private long window;

	public Camera(long window) {
		camPos.set(0, 1, 0);
		this.window = window;
		GLFW.glfwSetScrollCallback(window, (w, scrollX, scrollY) -> {
			scroll = (float) scrollY;
		});
	}

	public void reset() {
		camPos.set(0, 1, 0);
		d = 3.0f;
		theta = 0.0f;
		phi = 0.0f;
		freeCam = true;
	}

	private boolean forward() {
		return glfwGetKey(window, GLFW_KEY_W) == GLFW_PRESS;
	}

	private boolean backward() {
		return glfwGetKey(window, GLFW_KEY_S) == GLFW_PRESS;
	}

	private boolean left() {
		return glfwGetKey(window, GLFW_KEY_A) == GLFW_PRESS;
	}

	private boolean right() {
		return glfwGetKey(window, GLFW_KEY_D) == GLFW_PRESS;
	}

	private boolean up() {
		return glfwGetKey(window, GLFW_KEY_SPACE) == GLFW_PRESS;
	}

	private boolean down() {
		return glfwGetKey(window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS;
	};

	private boolean lmb() {
		return glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_1) == GLFW_PRESS;
	}

	private Vector2f mousePos() {
		double[] xpos = new double[1], ypos = new double[1];
		glfwGetCursorPos(window, xpos, ypos);
		return new Vector2f().set(xpos[0], ypos[0]);
	}

	public void updateView(float width, float height, boolean events) {
		Vector2f mousePos = mousePos();
		mouseNDC.set(2.0f * mousePos.x / width - 1.0f, 1.0f - 2.0f * mousePos.y / height);
		float dx = mousePrev.x - mousePos.x;
		float dy = mousePrev.y - mousePos.y;

		window_width = (int) width;
		window_height = (int) height;

		mousePrev.set(mousePos);
		if (lmb() && events) {
			theta += dx * 0.005f;
			phi -= dy * 0.005f;
			if (phi < -1.4137167f) {
				phi = -1.4137167f;
			}
			if (phi > 1.4137167f) {
				phi = 1.4137167f;
			}
		}
		if (!freeCam) {
			d *= 1.0f - scroll * 0.1f;
			scroll = 0;
			if (d > FAR_PLANE / 2.0f) {
				d = FAR_PLANE / 2.0f;
			}
			camDir.set(Math.sin(theta) * Math.cos(phi), Math.sin(phi), Math.cos(theta) * Math.cos(phi));
			camDir.negate();
			camPos.set(camDir);
			camPos.mul(-d);
			viewMat.setLookAt(camPos, new Vector3f(0), new Vector3f(0, 1, 0));
		} else {
			if (forward()) {
				camPos.add((float) Math.sin(theta) * -camSpeed, 0.0f, (float) Math.cos(theta) * -camSpeed);
			} else if (backward()) {
				camPos.add((float) Math.sin(theta) * camSpeed, 0.0f, (float) Math.cos(theta) * camSpeed);
			}
			if (left()) {
				camPos.add((float) Math.cos(theta) * -camSpeed, 0.0f, -((float) Math.sin(theta)) * -camSpeed);
			} else if (right()) {
				camPos.add((float) Math.cos(theta) * camSpeed, 0.0f, -((float) Math.sin(theta)) * camSpeed);
			}
			if (up()) {
				camPos.y += camSpeed;
			} else if (down()) {
				camPos.y -= camSpeed;
			}
			camDir.set(Math.sin(theta) * Math.cos(phi), Math.sin(phi), Math.cos(theta) * Math.cos(phi));
			camDir.negate();
			viewMat.setLookAt(camPos, new Vector3f(camPos).add(camDir), new Vector3f(0, 1, 0));
		}
		camDir.normalize();
		invViewMat.set((Matrix4fc) viewMat);
		invViewMat.invert();
		if (width != 0.0f && height != 0.0f) {
			if (Float.isFinite(FAR_PLANE)) {
				projMat.setPerspective(FOV_Y, width / height, NEAR_PLANE, FAR_PLANE);
			} else {
				float aspect = width / height;
				float tanHalfFOV_Y = (float) Math.tan(FOV_Y / 2.0f);
				projMat.zero();
				projMat.m00(1.0f / (aspect * tanHalfFOV_Y));
				projMat.m11(1.0f / tanHalfFOV_Y);
				projMat.m22(EPSILON - 1.0f);
				projMat.m23(-1.0f);
				projMat.m32((EPSILON - 2.0f) * NEAR_PLANE);
			}
		}

	}

	public Matrix4fc getProjectionMatrix() {
		return projMat;
	}

	public Matrix4fc getViewMatrix() {
		return viewMat;
	}

	public Matrix4fc getInvViewMatrix() {
		return invViewMat;
	}

	public Vector3fc getCameraPos() {
		return camPos;
	}

	public Vector3fc getCameraDir() {
		return camDir;
	}

	public Vector2fc getMouseNDC() {
		return mouseNDC;
	}
}
