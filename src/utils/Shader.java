package utils;

import static org.lwjgl.opengl.ARBShadingLanguageInclude.*;
import static org.lwjgl.opengl.GL11C.GL_FALSE;

import static org.lwjgl.opengl.GL20C.GL_COMPILE_STATUS;
import static org.lwjgl.opengl.GL20C.GL_FRAGMENT_SHADER;
import static org.lwjgl.opengl.GL20C.GL_INFO_LOG_LENGTH;
import static org.lwjgl.opengl.GL20C.GL_LINK_STATUS;
import static org.lwjgl.opengl.GL20C.GL_VERTEX_SHADER;
import static org.lwjgl.opengl.GL20C.glAttachShader;
import static org.lwjgl.opengl.GL20C.glBindAttribLocation;
import static org.lwjgl.opengl.GL20C.glCompileShader;
import static org.lwjgl.opengl.GL20C.glCreateProgram;
import static org.lwjgl.opengl.GL20C.glCreateShader;
import static org.lwjgl.opengl.GL20C.glDeleteProgram;
import static org.lwjgl.opengl.GL20C.glDeleteShader;
import static org.lwjgl.opengl.GL20C.glDetachShader;
import static org.lwjgl.opengl.GL20C.glGetProgramInfoLog;
import static org.lwjgl.opengl.GL20C.glGetProgramiv;
import static org.lwjgl.opengl.GL20C.glGetShaderInfoLog;
import static org.lwjgl.opengl.GL20C.glGetShaderiv;
import static org.lwjgl.opengl.GL20C.glGetUniformLocation;
import static org.lwjgl.opengl.GL20C.glLinkProgram;
import static org.lwjgl.opengl.GL20C.glShaderSource;
import static org.lwjgl.opengl.GL20C.glUniform1f;
import static org.lwjgl.opengl.GL20C.glUniform1i;
import static org.lwjgl.opengl.GL20C.glUniform2f;
import static org.lwjgl.opengl.GL20C.glUniform2i;
import static org.lwjgl.opengl.GL20C.glUniform3f;
import static org.lwjgl.opengl.GL20C.glUniform4f;
import static org.lwjgl.opengl.GL20C.glUniformMatrix4fv;
import static org.lwjgl.opengl.GL20C.glUseProgram;
import static org.lwjgl.opengl.GL20C.glValidateProgram;
import static org.lwjgl.opengl.GL30C.glBindFragDataLocation;
import static org.lwjgl.opengl.GL30C.glUniform1ui;
import static org.lwjgl.opengl.GL32C.GL_GEOMETRY_SHADER;
import static org.lwjgl.opengl.GL40C.GL_TESS_CONTROL_SHADER;
import static org.lwjgl.opengl.GL40C.GL_TESS_EVALUATION_SHADER;
import static org.lwjgl.opengl.GL43C.GL_COMPUTE_SHADER;
import static org.lwjgl.system.MemoryStack.stackPush;

import java.io.File;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.FloatBuffer;
import java.nio.IntBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileSystem;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardWatchEventKinds;
import java.nio.file.WatchEvent;
import java.nio.file.WatchKey;
import java.nio.file.WatchService;
import java.nio.file.WatchEvent.Kind;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.joml.Matrix4fc;
import org.joml.Vector2fc;
import org.joml.Vector2ic;
import org.joml.Vector3fc;
import org.joml.Vector4fc;
import org.lwjgl.PointerBuffer;
import org.lwjgl.opengl.ARBGPUShaderInt64;
import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;

public class Shader {
	
	static List<String> headers = List.of("/definitions.glsl", "/generation.glsl", "/render_common.glsl", "/PBR.glsl");
	static PointerBuffer headers_names_pointers;
	static List<ByteBuffer> headers_names_ASCII_strings;
	
	static WatchService shaders_watch;
	static HashMap<String, Shader> loadedShaders = new HashMap<>();

	public static void loadIncludes(){
		File folder = new File("shaders/");
		Path path = folder.toPath();
		FileSystem fs = path.getFileSystem();
		try {
			shaders_watch = fs.newWatchService();
			path.register(shaders_watch, StandardWatchEventKinds.ENTRY_MODIFY);
		} catch (IOException e) {
			e.printStackTrace();
		}
		

		for(var header : headers){
			ArrayList<String> lines = null;
			try {
				lines = (ArrayList<String>) Files.readAllLines(new File("shaders"+header).toPath());
			} catch (IOException e) {
				throw new IllegalArgumentException(e);
			}
			String source = "";
			for (String s : lines) {
				source += s + "\n";
			}
			glNamedStringARB(GL_SHADER_INCLUDE_ARB, header, source);
		}

		headers_names_pointers = MemoryUtil.memAllocPointer(headers.size());
		headers_names_ASCII_strings = new ArrayList<ByteBuffer>();

		for(var header : headers){
			// Allocate null-terminated '\0' strings
			ByteBuffer buff = MemoryUtil.memASCII(header, true);
			headers_names_pointers.put(buff);
			headers_names_ASCII_strings.add(buff);
		}

	}
	
	public static void updateFolderWatch() {
		WatchKey key = shaders_watch.poll();
		if(key == null) {
			return;
		}

		for (WatchEvent<?> watchEvent : key.pollEvents()) {
			Kind<?> kind = watchEvent.kind();
			if (kind == StandardWatchEventKinds.ENTRY_MODIFY) {
				@SuppressWarnings("unchecked")
				Path newPath = ((WatchEvent<Path>) watchEvent).context();
				String s = newPath.toString();
				System.out.println("New path modified: " + s);
				Shader shader = loadedShaders.get("shaders/" + s);
				if(shader != null)shader.reload();
			}
		}

		if (!key.reset()) {
			throw new IllegalStateException("Watch key on shaders folder is invalid");
		}

	}

	int programID;
	int computeShaderID = -1;
	int vertexShaderID = -1;
	int tessControlShaderID = -1;
	int tessEvaluationShaderID = -1;
	int geometryShaderID = -1;
	int fragmentShaderID = -1;
	
	String computeShaderPath;
	String vertexShaderPath;
	String tessControlShaderPath;
	String tessEvalShaderPath;
	String geomShaderPath;
	String fragShaderPath;
	
	Map<String, Integer> uniforms = new HashMap<>();
	
	public Shader(String computeFilePath) {
		computeShaderID = loadFromFile(computeFilePath, GL_COMPUTE_SHADER);
		programID = glCreateProgram();

		glAttachShader(programID, computeShaderID);
	}

	public Shader(ArrayList<String> vertexShader, ArrayList<String> fragmentShader) {
		vertexShaderID = loadFromFile(vertexShader, GL_VERTEX_SHADER, "*no file path*");
		geometryShaderID = -1;
		fragmentShaderID = loadFromFile(fragmentShader, GL_FRAGMENT_SHADER, "*no file path*");

		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
		glAttachShader(programID, fragmentShaderID);
	}

	/**
	 * Construit un nouveau shader. <br>
	 * Ne pas oublier d'appeler:<br>
	 * -Shader::bindVertexAttribute ***<br>
	 * -Shader::bindFragDataLocation ***<br>
	 * -Shader::finishInit<br>
	 * -Shader::getUniformLocation ***<br>
	 * -Shader::start<br>
	 * -Shader::connectTextureUnit ***<br>
	 * -Shader::stop<br>
	 * de façon à finaliser l'initialisation du shader.<br>
	 * les fonctions notées *** sont optionnelles.
	 * 
	 * @param vertexFilePath
	 * @param fragmentFilePath
	 */
	public Shader(String vertexFilePath, String fragmentFilePath) {
		vertexShaderID = loadFromFile(vertexFilePath, GL_VERTEX_SHADER);
		geometryShaderID = -1;
		fragmentShaderID = loadFromFile(fragmentFilePath, GL_FRAGMENT_SHADER);

		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
		glAttachShader(programID, fragmentShaderID);
	}

	public Shader(String vertexFilePath, String geometryFilePath, String fragmentFilePath) {
		vertexShaderID = loadFromFile(vertexFilePath, GL_VERTEX_SHADER);
		geometryShaderID = loadFromFile(geometryFilePath, GL_GEOMETRY_SHADER);
		fragmentShaderID = loadFromFile(fragmentFilePath, GL_FRAGMENT_SHADER);

		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
		glAttachShader(programID, geometryShaderID);
		glAttachShader(programID, fragmentShaderID);
	}

	public Shader(String computeFile, int dummy) {
		vertexShaderID = loadFromSource(computeFile, GL_COMPUTE_SHADER);
		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
	}

	public Shader(String vertexFile, String fragmentFile, int dummy) {
		vertexShaderID = loadFromSource(vertexFile, GL_VERTEX_SHADER);
		geometryShaderID = -1;
		fragmentShaderID = loadFromSource(fragmentFile, GL_FRAGMENT_SHADER);

		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
		glAttachShader(programID, fragmentShaderID);
	}

	public Shader(String vertexFile, String geometryFile, String fragmentFile, int dummy) {
		vertexShaderID = loadFromSource(vertexFile, GL_VERTEX_SHADER);
		geometryShaderID = loadFromSource(geometryFile, GL_GEOMETRY_SHADER);
		fragmentShaderID = loadFromSource(fragmentFile, GL_FRAGMENT_SHADER);

		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
		glAttachShader(programID, geometryShaderID);
		glAttachShader(programID, fragmentShaderID);
	}

	public Shader(String vertexFile, String tessellationControlFile, String tessellationEvaluationFile,
			String geometryFile, String fragmentFile) {
		vertexShaderID = loadFromSource(vertexFile, GL_VERTEX_SHADER);
		tessControlShaderID = loadFromSource(tessellationControlFile, GL_TESS_CONTROL_SHADER);
		tessEvaluationShaderID = loadFromSource(tessellationEvaluationFile, GL_TESS_EVALUATION_SHADER);
		geometryShaderID = loadFromSource(geometryFile, GL_GEOMETRY_SHADER);
		fragmentShaderID = loadFromSource(fragmentFile, GL_FRAGMENT_SHADER);

		programID = glCreateProgram();

		glAttachShader(programID, vertexShaderID);
		glAttachShader(programID, tessControlShaderID);
		glAttachShader(programID, tessEvaluationShaderID);
		glAttachShader(programID, geometryShaderID);
		glAttachShader(programID, fragmentShaderID);
	}
	
	public void reload() {
		Shader copy = null; 
		try {
			if(computeShaderID != -1) {
				copy = new Shader(computeShaderPath);
			}else if(tessControlShaderID != -1) {
				copy = new Shader(vertexShaderPath, tessControlShaderPath, tessEvalShaderPath, geomShaderPath, fragShaderPath);
			}else if(geometryShaderID != -1) {
				copy = new Shader(vertexShaderPath, geomShaderPath, fragShaderPath);
			}else {
				copy = new Shader(vertexShaderPath, fragShaderPath);
			}
			copy.finishInit();
			String[] unifNames = uniforms.keySet().toArray(new String[uniforms.size()]); 
			uniforms.clear();
			copy.init_uniforms(unifNames);

			delete();
			
			programID = copy.programID;
			computeShaderID = copy.computeShaderID;
			vertexShaderID = copy.vertexShaderID;
			tessControlShaderID = copy.tessControlShaderID;
			tessEvaluationShaderID = copy.tessEvaluationShaderID;
			geometryShaderID = copy.geometryShaderID;
			fragmentShaderID = copy.fragmentShaderID;
			
			uniforms = new HashMap<>(copy.uniforms);
			
			
		}catch(IllegalArgumentException e) {
			copy.delete();
			System.out.println(e.getMessage());
		}
		
		if(vertexShaderPath != null)loadedShaders.put(vertexShaderPath, this);
		if(tessControlShaderPath != null)loadedShaders.put(tessControlShaderPath, this);
		if(tessEvalShaderPath != null)loadedShaders.put(tessEvalShaderPath, this);
		if(geomShaderPath != null)loadedShaders.put(geomShaderPath, this);
		if(fragShaderPath != null)loadedShaders.put(fragShaderPath, this);
		if(computeShaderPath != null)loadedShaders.put(computeShaderPath, this);
	}
	
	public void delete() {
		glUseProgram(0);
		if (computeShaderID != -1)
			glDetachShader(programID, computeShaderID);
		if (vertexShaderID != -1)
			glDetachShader(programID, vertexShaderID);
		if (tessControlShaderID != -1)
			glDetachShader(programID, tessControlShaderID);
		if (tessEvaluationShaderID != -1)
			glDetachShader(programID, tessEvaluationShaderID);
		if (geometryShaderID != -1)
			glDetachShader(programID, geometryShaderID);
		if (fragmentShaderID != -1)
			glDetachShader(programID, fragmentShaderID);

		if (computeShaderID != -1)
			glDeleteShader(computeShaderID);
		if (vertexShaderID != -1)
			glDeleteShader(vertexShaderID);
		if (tessControlShaderID != -1)
			glDeleteShader(tessControlShaderID);
		if (tessEvaluationShaderID != -1)
			glDeleteShader(tessEvaluationShaderID);
		if (geometryShaderID != -1)
			glDeleteShader(geometryShaderID);
		if (fragmentShaderID != -1)
			glDeleteShader(fragmentShaderID);

		glDeleteProgram(programID);
	}

	public void start() {
		glUseProgram(programID);
	}

	public void stop() {
		glUseProgram(0);
	}

	public void finishInit() {
		glLinkProgram(programID);
		int linkRes = 0;
		try (MemoryStack stack = stackPush()) {
			IntBuffer pLinkRes = stack.mallocInt(1);
			glGetProgramiv(programID, GL_LINK_STATUS, pLinkRes);
			linkRes = pLinkRes.get(0);
		}

		if (linkRes == GL_FALSE) {
			System.err.println("Error while linking shader:");
			int sizeNeeded = 0;
			try (MemoryStack stack = stackPush()) {
				IntBuffer pSizeNeeded = stack.mallocInt(1);
				glGetProgramiv(programID, GL_INFO_LOG_LENGTH, pSizeNeeded);
				sizeNeeded = pSizeNeeded.get(0);

				ByteBuffer strBuff = stack.calloc(sizeNeeded);
				glGetProgramInfoLog(programID, pSizeNeeded, strBuff);

				String errMsg = StandardCharsets.UTF_8.decode(strBuff).toString();
				System.err.println(errMsg);
			}

			throw new IllegalArgumentException("Shader compile error");
		} else {
			System.out.println("GLSL program linked successfully: " + getShaderName());
		}
		glValidateProgram(programID);
		
		if(vertexShaderPath != null)loadedShaders.put(vertexShaderPath, this);
		if(tessControlShaderPath != null)loadedShaders.put(tessControlShaderPath, this);
		if(tessEvalShaderPath != null)loadedShaders.put(tessEvalShaderPath, this);
		if(geomShaderPath != null)loadedShaders.put(geomShaderPath, this);
		if(fragShaderPath != null)loadedShaders.put(fragShaderPath, this);
		if(computeShaderPath != null)loadedShaders.put(computeShaderPath, this);
	}

	public void bindVertexAttribute(int attribute, String variableName) {
		glBindAttribLocation(programID, attribute, variableName);
	}

	public void bindFragDataLocation(int colorAttachment, String variableName) {
		glBindFragDataLocation(programID, colorAttachment, variableName);
	}

	public void connectTextureUnit(String sampler_name, int value) {
		loadInt(sampler_name, value);
	}

	public void loadInt(String name, int value) {
		glUniform1i(findUniformLoc(name), value);
	}

	public void loadUInt(String name, int value) {
		glUniform1ui(findUniformLoc(name), value);
	}
	
	public void loadUInt64(String name, long value) {
		ARBGPUShaderInt64.glUniform1ui64ARB(findUniformLoc(name), value);
	}

	public void loadFloat(String name, float value) {
		glUniform1f(findUniformLoc(name), value);
	}

	public void loadVec2(String name, Vector2fc v) {
		glUniform2f(findUniformLoc(name), v.x(), v.y());
	}

	public void loadiVec2(String name, Vector2ic v) {
		glUniform2i(findUniformLoc(name), v.x(), v.y());
	}

	public void loadVec3(String name, Vector3fc v) {
		glUniform3f(findUniformLoc(name), v.x(), v.y(), v.z());
	}

	public void loadVec4(String name, Vector4fc v) {
		glUniform4f(findUniformLoc(name), v.x(), v.y(), v.z(), v.w());
	}

	public void loadMat4(String name, Matrix4fc mat) {
		try (MemoryStack stack = stackPush()) {
			FloatBuffer buffer = stack.mallocFloat(16);
			mat.get(buffer);
			glUniformMatrix4fv(findUniformLoc(name), false, buffer);
		}
	}

	public int get(String name) {
		return uniforms.get(name);
	}
	
	public String getShaderName() {
		List<String> names = new ArrayList<>();
		if(vertexShaderPath != null)		names.add(vertexShaderPath);
		if(tessControlShaderPath != null)	names.add(tessControlShaderPath);
		if(tessEvalShaderPath != null)		names.add(tessEvalShaderPath);
		if(geomShaderPath != null)			names.add(geomShaderPath);
		if(fragShaderPath != null)			names.add(fragShaderPath);
		if(computeShaderPath != null)		names.add(computeShaderPath);
		names.removeIf((s) -> s == null);
		return Arrays.deepToString(names.toArray());
	}

	public void init_uniforms(String... names) {
		String shaderName = getShaderName();
		
		start();
		for (String name : names) {
			int loc = getUniformLocation(name);

			if (loc == -1) {
				System.out.println("Uniform location of " + name + " = " + loc + " " + shaderName);
				System.out.println("\t-->The uniform variable name is either incorrect or the uniform variable is not used");
			}
			uniforms.put(name, loc);

		}
		stop();
	}

	private int loadFromFile(String filePath, int programType) {
		if(headers_names_ASCII_strings == null){
			Shader.loadIncludes();
		}

		ArrayList<String> lines = null;
		try {
			Path p = new File(filePath).toPath();
			lines = (ArrayList<String>) Files.readAllLines(p);
		} catch (IOException e) {
			throw new IllegalArgumentException(e);
		}
		
		switch(programType) {
			case GL_COMPUTE_SHADER: computeShaderPath = filePath; break;
			case GL_TESS_CONTROL_SHADER: tessControlShaderPath = filePath; break;
			case GL_TESS_EVALUATION_SHADER: tessEvalShaderPath = filePath; break;
			case GL_GEOMETRY_SHADER: geomShaderPath = filePath; break;
			case GL_VERTEX_SHADER: vertexShaderPath = filePath; break;
			case GL_FRAGMENT_SHADER: fragShaderPath = filePath; break;
		}
		
		return loadFromFile(lines, programType, filePath);
	}

	private int loadFromFile(ArrayList<String> lines, int programType, String filePath) {

		String source = "";
		for (String s : lines) {
			source += s + "\n";
		}

		int shaderID = glCreateShader(programType);
		glShaderSource(shaderID, source);

		//glCompileShader(shaderID);
		glCompileShaderIncludeARB(shaderID, headers_names_pointers.flip(), (IntBuffer)null);

		try (MemoryStack stack = stackPush()) {

			IntBuffer pStatus = stack.mallocInt(1);
			glGetShaderiv(shaderID, GL_COMPILE_STATUS, pStatus);
			int status = pStatus.get(0);

			if (status == GL_FALSE) {
				IntBuffer pSizeNeeded = stack.mallocInt(1);
				glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, pSizeNeeded);
				ByteBuffer strBuff = stack.calloc(pSizeNeeded.get(0));
				glGetShaderInfoLog(shaderID, pSizeNeeded, strBuff);
				String errMsg = StandardCharsets.UTF_8.decode(strBuff).toString();

				System.err.println("Erreur lors de la compilation de " + filePath + " :");
				System.err.println(errMsg);
				throw new IllegalArgumentException("Shader compile error");
			}
		}

		return shaderID;
	}

	private int loadFromSource(String file, int programType) {
		int shaderID = glCreateShader(programType);
		glShaderSource(shaderID, file);
		glCompileShader(shaderID);

		try (MemoryStack stack = stackPush()) {
			IntBuffer pStatus = stack.mallocInt(1);
			glGetShaderiv(shaderID, GL_COMPILE_STATUS, pStatus);
			int status = pStatus.get(0);

			if (status == GL_FALSE) {
				IntBuffer pSizeNeeded = stack.mallocInt(1);
				ByteBuffer strBuff = stack.calloc(pSizeNeeded.get(0));
				glGetShaderiv(shaderID, GL_INFO_LOG_LENGTH, pSizeNeeded);
				glGetShaderInfoLog(shaderID, pSizeNeeded, strBuff);
				String errMsg = StandardCharsets.UTF_8.decode(strBuff).toString();

				System.err.println("Erreur lors de la compilation d'un shader:");
				System.err.println(errMsg);
				throw new IllegalArgumentException("Shader compile error");
			}
		}

		return shaderID;
	}

	private int getUniformLocation(String variableName) {
		return glGetUniformLocation(programID, variableName);
	}

	private int findUniformLoc(String name) {
		Integer loc = uniforms.get(name);
		if (loc == null) {
			throw new IllegalArgumentException("Error, unknown uniform variable name: " + name);
		}
		return loc;
	}
}
