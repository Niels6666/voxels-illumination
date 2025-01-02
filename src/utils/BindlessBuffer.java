package utils;

import static org.lwjgl.opengl.GL46C.*;
import static org.lwjgl.opengl.NVShaderBufferLoad.*;

import org.lwjgl.system.MemoryStack;

import java.nio.ByteBuffer;
import java.nio.IntBuffer;
import java.nio.LongBuffer;

public class BindlessBuffer {
    public int ID;
    public long ptr;
    public long size_bytes;


    public BindlessBuffer(long size_bytes, int flags){
        this(size_bytes, flags, null);
    }

    public BindlessBuffer(long size_bytes, int flags, ByteBuffer data){
        this.size_bytes = size_bytes;

        try(MemoryStack s = MemoryStack.stackPush()){
            IntBuffer idbuff = s.callocInt(1);
	        glCreateBuffers(idbuff);
            ID = idbuff.get(0);
        }

        if(data == null){
            glNamedBufferStorage(ID, size_bytes, flags);
        }else{
        	glNamedBufferStorage(ID, data, flags);
        }
        

        try(MemoryStack s = MemoryStack.stackPush()){
            LongBuffer idbuff = s.callocLong(1);
            glGetNamedBufferParameterui64vNV(ID, GL_BUFFER_GPU_ADDRESS_NV, idbuff);
            ptr = idbuff.get(0);
        }

        glMakeNamedBufferResidentNV(ID, GL_READ_WRITE);

        if(data == null){
            try(MemoryStack s = MemoryStack.stackPush()){
                glClearNamedBufferData(ID, GL_R32I, GL_RED_INTEGER, GL_INT, (ByteBuffer)null);
            }
        }
            
    }

    public void delete(){
        glDeleteBuffers(ID);
    }

    /**
     * increments the position by 8
     */
    public void writePointer(ByteBuffer buff){
        assert buff.position() % 8 == 0;
        buff.putLong(ptr);
    }

    /**
     * increments the position by 16
     */
    public void writeHandle(ByteBuffer dest, int elementSize) {
		assert dest.position()%16 == 0;
		assert size_bytes%elementSize == 0;
		dest.putLong(ptr);
		dest.putLong(size_bytes / elementSize);
	}
}
