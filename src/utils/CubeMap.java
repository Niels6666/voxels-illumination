package utils;
import static org.lwjgl.opengl.GL46C.*;
import static org.lwjgl.opengl.ARBBindlessTexture.*;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;

import org.lwjgl.system.MemoryStack;

public class CubeMap {
	public int ID;
	public int width;
    public int internalFormat;
    public long tex_handle;
    public long img_handle;

	public CubeMap(int internalFormat, int format, int type, 
            int width) {
        this(internalFormat, format, type, width, GL_NEAREST, GL_NEAREST, GL_REPEAT);
    }
	public CubeMap(int internalFormat, int format, int type, 
            int width, int minFilter, int magFilter, int wrapMode) {
		this.width = width;
        this.internalFormat = internalFormat;

        try(MemoryStack s = MemoryStack.stackPush()){
            IntBuffer idbuff = s.callocInt(1);
		    glCreateTextures(GL_TEXTURE_CUBE_MAP, idbuff);
            ID = idbuff.get(0);
        }
        glTextureStorage2D(ID, 1, internalFormat, width, width);

        glTextureParameteri(ID, GL_TEXTURE_MIN_FILTER, minFilter);
		glTextureParameteri(ID, GL_TEXTURE_MAG_FILTER, magFilter);
		glTextureParameteri(ID, GL_TEXTURE_WRAP_R, wrapMode);
		glTextureParameteri(ID, GL_TEXTURE_WRAP_S, wrapMode);
		glTextureParameteri(ID, GL_TEXTURE_WRAP_T, wrapMode);

        glClearTexImage(ID, 0, format, type, (ByteBuffer)null);
        tex_handle = glGetTextureHandleARB(ID);
		img_handle = glGetImageHandleARB(ID, 0, true, 0, internalFormat);

        glMakeTextureHandleResidentARB(tex_handle);
        glMakeImageHandleResidentARB(img_handle, GL_READ_WRITE);
	}

    public void delete(){
        glDeleteTextures(ID);
    }
    
    public void writeHandle(ByteBuffer dest) {
		assert dest.position()%(4*4) == 0;
		dest.putLong(tex_handle);
		dest.putLong(img_handle);
	}

}
