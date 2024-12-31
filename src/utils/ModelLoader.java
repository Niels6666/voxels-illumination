package utils;

import org.joml.Vector3f;
import org.joml.Vector3fc;
import org.lwjgl.PointerBuffer;
import org.lwjgl.assimp.AIFace;
import org.lwjgl.assimp.AIMesh;
import org.lwjgl.assimp.AIScene;
import org.lwjgl.assimp.AIVector3D;
import org.lwjgl.assimp.Assimp;
import static org.lwjgl.opengl.GL15C.GL_STATIC_DRAW;

public class ModelLoader {
	public static VAO load(String path, int flags, boolean scaleToUnit) {
		AIScene scene = Assimp.aiImportFile(path, (int) (0x800048 | flags));
		if (scene == null) {
			throw new IllegalArgumentException("Couldn't open file " + path);
		}
		PointerBuffer aiMeshes = scene.mMeshes();
		AIMesh mesh = AIMesh.create((long) aiMeshes.get(0));
		System.out.println("Loading mesh " + path);
		VAO vao = new VAO();
		vao.bind();
		if (mesh.mNumFaces() != 0) {
			System.out.println(String.valueOf(mesh.mNumFaces() * 3) + " indices detected.");
			int[] indices = buildIndices(mesh);
			vao.createIndexBuffer(indices);
		}
		if (mesh.mNumVertices() != 0) {
			System.out.println(String.valueOf(mesh.mNumVertices()) + " vertices detected, put to binding 0.");
			float[] vertices = buildPositions(mesh, scaleToUnit);
			vao.createFloatAttribute(0, vertices, 3, 0, GL_STATIC_DRAW);
		}
		if (mesh.mNormals() != null) {
			System.out.println("Normals detected, put to binding 1.");
			float[] normals = buildNormals(mesh);
			vao.createFloatAttribute(1, normals, 3, 0, GL_STATIC_DRAW);
		}
		if (mesh.mTextureCoords(0) != null) {
			System.out.println("Texture coords detected, put to binding 2.");
			float[] uvs = buildTexCoords(mesh);
			vao.createFloatAttribute(2, uvs, 2, 0, GL_STATIC_DRAW);
		}
		vao.unbind();
		return vao;
	}

	private static int[] buildIndices(AIMesh mesh) {
		int numIndices = mesh.mNumFaces() * 3;
		int[] indices = new int[numIndices];
		for (int f = 0; f < mesh.mNumFaces(); ++f) {
			AIFace face = (AIFace) mesh.mFaces().get(f);
			indices[3 * f + 0] = face.mIndices().get(0);
			indices[3 * f + 1] = face.mIndices().get(1);
			indices[3 * f + 2] = face.mIndices().get(2);
		}
		return indices;
	}

	private static float[] buildPositions(AIMesh mesh, boolean scaleToUnit) {
		int numVertices = mesh.mNumVertices();
		float[] vertices = new float[numVertices * 3];
		Vector3f Vmin = new Vector3f(Float.POSITIVE_INFINITY);
		Vector3f Vmax = new Vector3f(Float.NEGATIVE_INFINITY);
		for (int v = 0; v < numVertices; ++v) {
			AIVector3D vertex = (AIVector3D) mesh.mVertices().get(v);
			vertices[3 * v + 0] = vertex.x();
			vertices[3 * v + 1] = vertex.y();
			vertices[3 * v + 2] = vertex.z();
			Vector3f u = new Vector3f(vertex.x(), vertex.y(), vertex.z());
			Vmax.max((Vector3fc) u);
			Vmin.min((Vector3fc) u);
		}
		if (scaleToUnit) {
			Vector3f size = Vmax.sub((Vector3fc) Vmin, new Vector3f());
			float extent = Math.max(Math.max(size.x, size.y), size.z);
			for (int v = 0; v < numVertices; ++v) {
				vertices[3 * v + 0] = (vertices[3 * v + 0] - Vmin.x - 0.5f * size.x) / extent * 2.0f;
				vertices[3 * v + 1] = (vertices[3 * v + 1] - Vmin.y - 0.5f * size.y) / extent * 2.0f;
				vertices[3 * v + 2] = (vertices[3 * v + 2] - Vmin.z - 0.5f * size.z) / extent * 2.0f;
			}
		}
		return vertices;
	}

	private static float[] buildNormals(AIMesh mesh) {
		int numNormals = mesh.mNumVertices();
		float[] normals = new float[numNormals * 3];
		for (int v = 0; v < numNormals; ++v) {
			AIVector3D normal = (AIVector3D) mesh.mNormals().get(v);
			normals[3 * v + 0] = normal.x();
			normals[3 * v + 1] = normal.y();
			normals[3 * v + 2] = normal.z();
		}
		return normals;
	}

	private static float[] buildTexCoords(AIMesh mesh) {
		int numTexture = mesh.mNumVertices();
		float[] uvs = new float[numTexture * 2];
		AIVector3D.Buffer tex = mesh.mTextureCoords(0);
		for (int i = 0; i < numTexture; ++i) {
			AIVector3D uv = (AIVector3D) tex.get(i);
			uvs[2 * i + 0] = uv.x();
			uvs[2 * i + 1] = uv.y();
		}
		return uvs;
	}
}
