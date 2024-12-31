package utils;

import static org.lwjgl.opengl.GL46C.*;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import static org.lwjgl.opengl.ARBBindlessTexture.*;
import static org.lwjgl.opengl.GL11C.GL_INT;
import static org.lwjgl.opengl.GL30C.GL_RED_INTEGER;
import static org.lwjgl.opengl.GL44C.glClearTexImage;

import org.lwjgl.system.MemoryStack;
import org.lwjgl.system.MemoryUtil;

public class Texture3D {
	public int ID;
	public int width;
	public int height;
	public int depth;
    public int internalFormat;
    public long tex_handle;
    public long img_handle;

	public Texture3D(int internalFormat, int format, int type, 
            int width, int height, int depth) {
        this(internalFormat, format, type, width, height, depth, GL_NEAREST, GL_NEAREST, GL_REPEAT);
    }
	public Texture3D(int internalFormat, int format, int type, 
            int width, int height, int depth, int minFilter, int magFilter, int wrapMode) {
		this.width = width;
		this.height = height;
        this.depth = depth;
        this.internalFormat = internalFormat;

        try(MemoryStack s = MemoryStack.stackPush()){
            IntBuffer idbuff = s.callocInt(1);
		    glCreateTextures(GL_TEXTURE_3D, idbuff);
            ID = idbuff.get(0);
        }
        glTextureStorage3D(ID, 1, internalFormat, width, height, depth);

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
    
    /**
     * increments the position by 16
     */
    public void writeHandle(ByteBuffer dest) {
		assert dest.position()%(4*4) == 0;
		dest.putLong(tex_handle);
		dest.putLong(img_handle);
	}

    public void uploadData(ByteBuffer data, int format, int type){
        glTextureSubImage3D(ID, 0, 0, 0, 0, width, height, depth, format, type, data);
    }
    
	public void clear(int value) {
		ByteBuffer buff = MemoryUtil.memAlloc(4);
		buff.putInt(value);
		glClearTexImage(ID, 0, GL_RED_INTEGER, GL_INT, buff.flip());
		MemoryUtil.memFree(buff);
	}
}
