/*
 * TrashManager — safe file deletion via GVfs trash://
 *
 * Uses GIO's g_file_trash(), g_file_move() and trash:// URI scheme
 * to provide trash/restore functionality independent of any GUI.
 */

namespace TileFm {

public class TrashInfo : Object {
    public uint item_count { get; set; }
    public int64 total_size { get; set; }
}

public class TrashManager : Object {
    /**
     * Move a file to the trash.
     *
     * @param path Absolute local path of the file/directory.
     * @return true on success.
     */
    public static async bool trash_file(string path) throws Error {
        var file = File.new_for_path(path);
        if (!file.query_exists()) {
            throw new IOError.NOT_FOUND("File '%s' does not exist".printf(path));
        }
        return yield file.trash_async(Priority.DEFAULT, null);
    }

    /**
     * Restore a file from the trash to its original location.
     *
     * GVfs stores the original path in the Trash Info file; here we simply
     * move from trash:// URI back to the provided original_path.
     *
     * @param trash_uri  trash:// URI of the trashed item (e.g. trash:///foo.txt).
     * @param original_path Destination path where the file should be restored.
     * @return true on success.
     */
    public static async bool restore_file(string trash_uri, string original_path) throws Error {
        var trash_file = File.new_for_uri(trash_uri);
        var dest_file = File.new_for_path(original_path);

        if (!trash_file.query_exists()) {
            throw new IOError.NOT_FOUND("Trashed file '%s' not found".printf(trash_uri));
        }

        // If a file already exists at the destination, refuse to overwrite
        if (dest_file.query_exists()) {
            throw new IOError.EXISTS(
                "Cannot restore: destination '%s' already exists".printf(original_path));
        }

        return yield trash_file.move_async(
            dest_file,
            FileCopyFlags.NOFOLLOW_SYMLINKS,
            Priority.DEFAULT,
            null,
            null
        );
    }

    /**
     * Empty the trash entirely.
     *
     * Iterates over trash:/// children and deletes each item.
     * @return true if all items were removed successfully.
     */
    public static async bool empty_trash() throws Error {
        var trash = File.new_for_uri("trash:///");
        if (!trash.query_exists()) {
            // Nothing to empty
            return true;
        }

        var enumerator = yield trash.enumerate_children_async(
            FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_TYPE,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
            Priority.DEFAULT,
            null
        );

        bool all_ok = true;
        FileInfo? info = null;

        while ((info = enumerator.next_file(null)) != null) {
            var child = trash.get_child(info.get_name());
            try {
                yield child.delete_async(Priority.DEFAULT, null);
            } catch (Error e) {
                warning("Failed to delete '%s' from trash: %s", child.get_uri(), e.message);
                all_ok = false;
            }
        }

        return all_ok;
    }

    /**
     * Retrieve statistics about the trash contents.
     *
     * @return TrashInfo with item_count and total_size (in bytes).
     */
    public static async TrashInfo get_trash_info() throws Error {
        var info = new TrashInfo();
        info.item_count = 0;
        info.total_size = 0;

        var trash = File.new_for_uri("trash:///");
        if (!trash.query_exists()) {
            return info;
        }

        var enumerator = yield trash.enumerate_children_async(
            FileAttribute.STANDARD_NAME + "," +
            FileAttribute.STANDARD_TYPE + "," +
            FileAttribute.STANDARD_SIZE,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
            Priority.DEFAULT,
            null
        );

        FileInfo? child_info = null;
        while ((child_info = enumerator.next_file(null)) != null) {
            info.item_count++;
            info.total_size += child_info.get_size();

            // Recurse into directories for a more accurate total size
            if (child_info.get_file_type() == FileType.DIRECTORY) {
                var child = trash.get_child(child_info.get_name());
                info.total_size += yield calculate_dir_size(child);
            }
        }

        return info;
    }

    /* ------------------------------------------------------------------ */
    /* Private helpers                                                    */
    /* ------------------------------------------------------------------ */

    /**
     * Recursively calculate the total size of a directory.
     */
    private static async int64 calculate_dir_size(File dir) throws Error {
        int64 total = 0;

        var enumerator = yield dir.enumerate_children_async(
            FileAttribute.STANDARD_NAME + "," +
            FileAttribute.STANDARD_TYPE + "," +
            FileAttribute.STANDARD_SIZE,
            FileQueryInfoFlags.NOFOLLOW_SYMLINKS,
            Priority.DEFAULT,
            null
        );

        FileInfo? info = null;
        while ((info = enumerator.next_file(null)) != null) {
            total += info.get_size();
            if (info.get_file_type() == FileType.DIRECTORY) {
                total += yield calculate_dir_size(dir.get_child(info.get_name()));
            }
        }

        return total;
    }
}

}
