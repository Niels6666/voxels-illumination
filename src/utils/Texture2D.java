package utils;

import static org.lwjgl.opengl.GL46C.*;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import static org.lwjgl.opengl.ARBBindlessTexture.*;
import org.lwjgl.system.MemoryStack;

public class Texture2D {
    public int ID;
	public int width;
	public int height;
    public int internalFormat;
    public long tex_handle;
    public long img_handle;

	public Texture2D(int internalFormat, int format, int type, 
            int width, int height) {
        this(internalFormat, format, type, width, height, GL_NEAREST, GL_NEAREST, GL_REPEAT);
    }
	public Texture2D(int internalFormat, int format, int type, 
            int width, int height, int minFilter, int magFilter, int wrapMode) {
		this.width = width;
		this.height = height;
        this.internalFormat = internalFormat;

        try(MemoryStack s = MemoryStack.stackPush()){
            IntBuffer idbuff = s.callocInt(1);
		    glCreateTextures(GL_TEXTURE_2D, idbuff);
            ID = idbuff.get(0);
        }
        glTextureStorage2D(ID, 1, internalFormat, width, height);

        glTextureParameteri(ID, GL_TEXTURE_MIN_FILTER, minFilter);
		glTextureParameteri(ID, GL_TEXTURE_MAG_FILTER, magFilter);
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

    public void uploadData(ByteBuffer data, int format, int type){
        glTextureSubImage2D(ID, 0, 0, 0, width, height, format, type, data);
    }
}
