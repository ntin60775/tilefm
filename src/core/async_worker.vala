/* TileFM — AsyncWorker
 * Thread pool for background file operations
 */

namespace TileFm {
    public class AsyncWorker : Object {
        private ThreadPool<WorkerTask> pool;
        
        public AsyncWorker() {
            try {
                pool = new ThreadPool<WorkerTask>.with_owned_data(
                    (task) => task.execute(),
                    4,  // max threads
                    false  // don't exclusive
                );
            } catch (Error e) {
                warning("Failed to create thread pool: %s", e.message);
            }
        }
        
        public void submit(WorkerTask task) {
            try {
                pool.add(task);
            } catch (Error e) {
                warning("Failed to submit task: %s", e.message);
            }
        }
    }
    
    public abstract class WorkerTask : Object {
        public signal void completed();
        public signal void failed(string error);
        
        public abstract void execute();
    }
    
    public class DirectoryListTask : WorkerTask {
        private FileManager fm;
        private string path;
        
        public FileInfo[]? result { get; private set; }
        
        public DirectoryListTask(FileManager fm, string path) {
            this.fm = fm;
            this.path = path;
        }
        
        public override void execute() {
            try {
                var loop = new MainLoop();
                FileInfo[]? infos = null;
                
                Idle.add(() => {
                    fm.list_directory.begin(path, (obj, res) => {
                        try {
                            infos = fm.list_directory.end(res);
                        } catch (Error e) {
                            failed(e.message);
                        }
                        loop.quit();
                    });
                    return false;
                });
                
                loop.run();
                result = infos;
                completed();
            } catch (Error e) {
                failed(e.message);
            }
        }
    }
}
