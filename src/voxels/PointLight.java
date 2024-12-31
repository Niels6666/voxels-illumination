package voxels;

import org.joml.Vector3f;
import static org.lwjgl.opengl.GL46C.*;

import utils.CubeMap;

public class PointLight {
	public CubeMap cubeMap;
	public Vector3f position;
	public Vector3f color;
	public final int width = 256;
	
	public PointLight(Vector3f position, Vector3f color) {
		this.position = position;
		this.color = color;
		cubeMap = new CubeMap(GL_RG32F, GL_RG, GL_FLOAT, width, GL_LINEAR, GL_LINEAR, GL_CLAMP_TO_EDGE);
	}
}
