package utils;

import java.util.List;
import java.util.ArrayList;

public class QueryBuffer {
	int type;
	List<Query> buffer = new ArrayList<Query>();
	long lastResult[] = new long[1];
	int max_size;

	public QueryBuffer(int type, int max_size) {
		this.type = type;
		this.max_size = max_size;
	};

	public void delete() {
		for (var q : buffer) {
			q.delete();
		}
	}

	public Query push_back() {
		if (size() > max_size) {
			buffer.remove(0).delete();
		}
		var q = new Query(type);
		buffer.add(q);
		return q;
	}

	public int size() {
		return buffer.size();
	}

	public boolean resultAvailable() {
		if (size() > 0) {
			return buffer.get(0).resultAvailable();
		}
		return false;
	}

	public long getLastResult(boolean update) {
		if (update) {
			while (getResultAndPopFrontIfAvailable(lastResult))
				;
		}
		return lastResult[0];
	}

	public boolean getResultAndPopFrontIfAvailable(long[] res) {
		if (buffer.size() == 0) {
			return false;
		}
		if (buffer.get(0).getResultNoWait(res)) {
			buffer.remove(0).delete();
			lastResult = res;
			return true;
		}
		return false;
	}
}
