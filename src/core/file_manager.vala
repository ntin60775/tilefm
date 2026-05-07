/* TileFM — FileManager
 * Async file operations using GIO
 */

namespace TileFm {
    public class FileManager : Object {
        public signal void error_occurred(string message);
        public signal void operation_progress(string operation, double fraction);
        
        private Cancellable cancellable;
        
        public FileManager() {
            cancellable = new Cancellable();
        }
        
        // List directory contents asynchronously
        public async FileInfo[] list_directory(string path) throws Error {
            var dir = File.new_for_path(path);
            var infos = new FileInfo[0];
            
            if (!dir.query_exists()) {
                throw new IOError.NOT_FOUND("Directory not found: %s", path);
            }
            
            var enumerator = yield dir.enumerate_children_async(
                FileAttribute.STANDARD_NAME + "," +
                FileAttribute.STANDARD_DISPLAY_NAME + "," +
                FileAttribute.STANDARD_TYPE + "," +
                FileAttribute.STANDARD_SIZE + "," +
                FileAttribute.STANDARD_CONTENT_TYPE + "," +
                FileAttribute.STANDARD_ICON + "," +
                FileAttribute.STANDARD_IS_HIDDEN + "," +
                FileAttribute.STANDARD_IS_SYMLINK + "," +
                FileAttribute.STANDARD_SYMLINK_TARGET + "," +
                FileAttribute.TIME_MODIFIED,
                FileQueryFlags.NOFOLLOW_SYMLINKS,
                Priority.DEFAULT,
                cancellable
            );
            
            while (true) {
                var files = yield enumerator.next_files_async(
                    100, Priority.DEFAULT, cancellable
                );
                
                if (files == null || files.length() == 0) {
                    break;
                }
                
                foreach (var info in files) {
                    infos += info;
                }
            }
            
            // Sort: directories first, then alphabetically
            GLib.qsort_with_data(
                infos, sizeof(FileInfo),
                (a, b) => {
                    var info_a = (FileInfo) a;
                    var info_b = (FileInfo) b;
                    
                    bool is_dir_a = info_a.get_file_type() == FileType.DIRECTORY;
                    bool is_dir_b = info_b.get_file_type() == FileType.DIRECTORY;
                    
                    if (is_dir_a && !is_dir_b) return -1;
                    if (!is_dir_a && is_dir_b) return 1;
                    
                    return info_a.get_display_name().collate(info_b.get_display_name());
                }
            );
            
            return infos;
        }
        
        // Get file info
        public FileInfo? get_file_info(string path) {
            try {
                var file = File.new_for_path(path);
                return file.query_info(
                    FileAttribute.STANDARD_NAME + "," +
                    FileAttribute.STANDARD_TYPE + "," +
                    FileAttribute.STANDARD_SIZE + "," +
                    FileAttribute.STANDARD_CONTENT_TYPE + "," +
                    FileAttribute.STANDARD_ICON + "," +
                    FileAttribute.TIME_MODIFIED,
                    FileQueryFlags.NOFOLLOW_SYMLINKS
                );
            } catch (Error e) {
                warning("Failed to get file info: %s", e.message);
                return null;
            }
        }
        
        // Get MIME type
        public string get_mime_type(string path) {
            var info = get_file_info(path);
            if (info != null) {
                return info.get_content_type() ?? "application/octet-stream";
            }
            return "application/octet-stream";
        }
        
        // Get icon name for file
        public string get_icon_name(string path) {
            var info = get_file_info(path);
            if (info != null) {
                var icon = info.get_icon();
                if (icon != null) {
                    return icon.to_string();
                }
            }
            return "text-x-generic";
        }
        
        // Open file with default app
        public bool open_file(string path) {
            try {
                var file = File.new_for_path(path);
                var app_info = file.query_default_handler();
                if (app_info != null) {
                    var files = new List<File>();
                    files.append(file);
                    app_info.launch(files, null);
                    return true;
                }
            } catch (Error e) {
                warning("Failed to open file: %s", e.message);
                try {
                    AppInfo.launch_default_for_uri(
                        File.new_for_path(path).get_uri(), null
                    );
                    return true;
                } catch (Error e2) {
                    error_occurred(e2.message);
                }
            }
            return false;
        }
        
        // Copy file/directory
        public async bool copy(string src_path, string dst_path) throws Error {
            var src = File.new_for_path(src_path);
            var dst = File.new_for_path(dst_path);
            
            return yield src.copy_async(
                dst,
                FileCopyFlags.ALL_METADATA | FileCopyFlags.OVERWRITE,
                Priority.DEFAULT,
                cancellable,
                (current, total) => {
                    if (total > 0) {
                        operation_progress("copy", (double) current / total);
                    }
                }
            );
        }
        
        // Move file/directory
        public async bool move(string src_path, string dst_path) throws Error {
            var src = File.new_for_path(src_path);
            var dst = File.new_for_path(dst_path);
            
            return yield src.move_async(
                dst,
                FileCopyFlags.ALL_METADATA,
                Priority.DEFAULT,
                cancellable,
                (current, total) => {
                    if (total > 0) {
                        operation_progress("move", (double) current / total);
                    }
                }
            );
        }
        
        // Delete file/directory
        public async bool delete_file(string path) throws Error {
            var file = File.new_for_path(path);
            return yield file.delete_async(Priority.DEFAULT, cancellable);
        }
        
        // Rename file/directory
        public async bool rename(string old_path, string new_name) throws Error {
            var file = File.new_for_path(old_path);
            var parent = file.get_parent();
            if (parent == null) {
                throw new IOError.INVALID_FILENAME("No parent directory");
            }
            var new_file = parent.get_child(new_name);
            return yield file.set_display_name_async(
                new_name, Priority.DEFAULT, cancellable
            ) != null;
        }
        
        // Get parent directory
        public string? get_parent(string path) {
            var file = File.new_for_path(path);
            var parent = file.get_parent();
            return parent?.get_path();
        }
        
        // Cancel current operation
        public void cancel() {
            cancellable.cancel();
            cancellable = new Cancellable();
        }
    }
}
