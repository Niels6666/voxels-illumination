package utils;
import static org.lwjgl.opengl.GL46C.*;

public class Query {

	int ID;
	int type;
	long s = 0;

	public Query(int type){
		this.type = type;
        int[] getter = new int[1];
		glGenQueries(getter);
        ID = getter[0];
	}

	public void delete(){
		glDeleteQueries(ID);
		glDeleteSync(s);
	}

	public void begin(){
		glBeginQuery(type, ID);
	}

	public void end(){
		glEndQuery(type);
		s = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
	}

	/**
	 * Only if the query is GL_TIMESTAMP
	 */
	public void queryCounter(){
		glQueryCounter(ID, type);
		s = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
	}

	public boolean resultAvailable(){
		return glClientWaitSync(s, GL_SYNC_FLUSH_COMMANDS_BIT, 0) == GL_ALREADY_SIGNALED;
	}

	public boolean getResultNoWait(long[] res){
		if(!resultAvailable()){
			return false;
		}

		int[] status = new int[]{GL_FALSE};
		glGetQueryObjectiv(ID, GL_QUERY_RESULT_AVAILABLE, status);

		if(status[0] == GL_TRUE){
		}
		glGetQueryObjecti64v(ID, GL_QUERY_RESULT, res);
		return true;
	}

	public void getResult(long[] res){
		glGetQueryObjecti64v(ID, GL_QUERY_RESULT, res);
	}

	public long getResult(){
		long[] res = new long[1];
		glGetQueryObjecti64v(ID, GL_QUERY_RESULT, res);
		return res[0];
	}

}
