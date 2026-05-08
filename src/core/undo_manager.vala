/*
 * UndoManager — Command-pattern undo/redo stack for TileFM.
 *
 * Every file operation (copy, move, delete, rename, create_dir) is recorded
 * as an UndoAction.  The manager maintains a bounded stack (max 100 entries)
 * and can undo/redo individual actions or whole batches.
 *
 * For DELETE actions the file is moved to GVfs trash; the trash URI is kept
 * in UndoAction.trash_uri so that undo can restore it.
 */

namespace TileFm {

/**
 * Supported operation types that can be undone / redone.
 */
public enum UndoActionType {
    COPY,
    MOVE,
    DELETE,
    RENAME,
    CREATE_DIR,
    BATCH
}

/**
 * Immutable-ish command object describing one file operation.
 *
 * For a BATCH action `sub_actions` holds the nested commands; they are
 * executed / reversed as a single atomic unit.
 */
public class UndoAction : Object {
    public UndoActionType action_type { get; construct set; }
    public string src_path { get; construct set; default = ""; }
    public string dst_path { get; construct set; default = ""; }
    public string original_name { get; construct set; default = ""; }
    public string trash_uri { get; construct set; default = ""; }
    public int64 timestamp { get; construct set; }
    public string description { get; construct set; default = ""; }

    /* Nested commands for BATCH type */
    public Gee.ArrayList<UndoAction> sub_actions { get; set; }

    public UndoAction(UndoActionType type) {
        Object(action_type: type);
        this.timestamp = GLib.get_real_time() / 1000000;
        this.sub_actions = new Gee.ArrayList<UndoAction>();
    }
}

/**
 * Central undo / redo manager.
 */
public class UndoManager : Object {
    /* Signals */
    public signal void can_undo_changed(bool can_undo);
    public signal void can_redo_changed(bool can_redo);
    public signal void action_performed(string description);

    private FileManager fm;
    private Gee.ArrayList<UndoAction> history;
    private int current_index;       // points to last executed action, -1 = empty
    private const int MAX_HISTORY = 100;

    public UndoManager(FileManager file_manager) {
        this.fm = file_manager;
        this.history = new Gee.ArrayList<UndoAction>();
        this.current_index = -1;
    }

    /* ================================================================ */
    /*  Recording API                                                   */
    /* ================================================================ */

    /**
     * Record a successful copy operation.
     *
     * Undo: delete the copied file at dst.
     */
    public void record_copy(string src, string dst) {
        truncate_redo_branch();

        var action = new UndoAction(UndoActionType.COPY);
        action.src_path = src;
        action.dst_path = dst;
        action.description = "Copy: %s → %s".printf(
            Path.get_basename(src), Path.get_basename(dst));

        push_action(action);
    }

    /**
     * Record a successful move operation.
     *
     * Undo: move dst back to src.
     */
    public void record_move(string src, string dst) {
        truncate_redo_branch();

        var action = new UndoAction(UndoActionType.MOVE);
        action.src_path = src;
        action.dst_path = dst;
        action.description = "Move: %s → %s".printf(
            Path.get_basename(src), Path.get_basename(dst));

        push_action(action);
    }

    /**
     * Record a successful delete operation.
     *
     * The file is already expected to be in trash; trash_uri is the
     * trash:// URI returned by the deletion helper.
     *
     * Undo: restore from trash to src_path.
     */
    public void record_delete(string path, string trash_uri) {
        truncate_redo_branch();

        var action = new UndoAction(UndoActionType.DELETE);
        action.src_path = path;
        action.trash_uri = trash_uri;
        action.description = "Delete: %s".printf(Path.get_basename(path));

        push_action(action);
    }

    /**
     * Record a successful rename operation.
     *
     * Undo: rename dst_path back to original_name (full path).
     */
    public void record_rename(string old_path, string new_path) {
        truncate_redo_branch();

        var action = new UndoAction(UndoActionType.RENAME);
        action.src_path = old_path;
        action.dst_path = new_path;
        action.description = "Rename: %s → %s".printf(
            Path.get_basename(old_path), Path.get_basename(new_path));

        push_action(action);
    }

    /**
     * Record a successful directory creation.
     *
     * Undo: delete the created directory.
     */
    public void record_create_dir(string path) {
        truncate_redo_branch();

        var action = new UndoAction(UndoActionType.CREATE_DIR);
        action.dst_path = path;
        action.description = "Create directory: %s".printf(Path.get_basename(path));

        push_action(action);
    }

    /**
     * Start recording a batch of actions.
     *
     * Call begin_batch() before a series of record_*() calls, then
     * commit_batch() when the whole group is recorded.  Until the batch
     * is committed nothing is pushed onto the undo stack.
     */
    public void begin_batch(string description) {
        truncate_redo_branch();

        active_batch = new UndoAction(UndoActionType.BATCH);
        active_batch.description = description;
        batch_depth++;
    }

    /**
     * Commit the currently open batch.
     *
     * The collected sub-actions are pushed as a single BATCH entry.
     */
    public void commit_batch() {
        if (active_batch == null || batch_depth == 0)
            return;

        batch_depth--;
        if (batch_depth == 0) {
            push_action(active_batch);
            active_batch = null;
        }
    }

    /**
     * Cancel the current batch without recording anything.
     */
    public void cancel_batch() {
        active_batch = null;
        batch_depth = 0;
    }

    /**
     * Record an action inside an open batch.
     * If no batch is active the action is recorded directly.
     */
    public void record_batch_copy(string src, string dst) {
        if (active_batch != null) {
            var action = new UndoAction(UndoActionType.COPY);
            action.src_path = src;
            action.dst_path = dst;
            action.description = "Copy: %s".printf(Path.get_basename(src));
            active_batch.sub_actions.add(action);
        } else {
            record_copy(src, dst);
        }
    }

    public void record_batch_move(string src, string dst) {
        if (active_batch != null) {
            var action = new UndoAction(UndoActionType.MOVE);
            action.src_path = src;
            action.dst_path = dst;
            action.description = "Move: %s".printf(Path.get_basename(src));
            active_batch.sub_actions.add(action);
        } else {
            record_move(src, dst);
        }
    }

    public void record_batch_delete(string path, string trash_uri) {
        if (active_batch != null) {
            var action = new UndoAction(UndoActionType.DELETE);
            action.src_path = path;
            action.trash_uri = trash_uri;
            action.description = "Delete: %s".printf(Path.get_basename(path));
            active_batch.sub_actions.add(action);
        } else {
            record_delete(path, trash_uri);
        }
    }

    public void record_batch_rename(string old_path, string new_path) {
        if (active_batch != null) {
            var action = new UndoAction(UndoActionType.RENAME);
            action.src_path = old_path;
            action.dst_path = new_path;
            action.description = "Rename: %s".printf(Path.get_basename(old_path));
            active_batch.sub_actions.add(action);
        } else {
            record_rename(old_path, new_path);
        }
    }

    public void record_batch_create_dir(string path) {
        if (active_batch != null) {
            var action = new UndoAction(UndoActionType.CREATE_DIR);
            action.dst_path = path;
            action.description = "Create dir: %s".printf(Path.get_basename(path));
            active_batch.sub_actions.add(action);
        } else {
            record_create_dir(path);
        }
    }

    /* ================================================================ */
    /*  Undo / Redo                                                     */
    /* ================================================================ */

    /**
     * Undo the last action (or batch).
     *
     * Returns true on success.  If the undo fails half-way through a
     * BATCH the already-reversed sub-actions stay reversed (no rollback
     * of rollback is attempted).
     */
    public async bool undo() throws Error {
        if (!can_undo())
            return false;

        var action = history.get(current_index);
        bool success = false;

        try {
            switch (action.action_type) {
                case UndoActionType.COPY:
                    success = yield undo_copy(action);
                    break;
                case UndoActionType.MOVE:
                    success = yield undo_move(action);
                    break;
                case UndoActionType.DELETE:
                    success = yield undo_delete(action);
                    break;
                case UndoActionType.RENAME:
                    success = yield undo_rename(action);
                    break;
                case UndoActionType.CREATE_DIR:
                    success = yield undo_create_dir(action);
                    break;
                case UndoActionType.BATCH:
                    success = yield undo_batch(action);
                    break;
            }
        } catch (Error e) {
            warning("Undo failed for '%s': %s", action.description, e.message);
            throw e;
        }

        if (success) {
            current_index--;
            emit_state_changed();
            action_performed("Undo: %s".printf(action.description));
        }

        return success;
    }

    /**
     * Redo the previously undone action (or batch).
     */
    public async bool redo() throws Error {
        if (!can_redo())
            return false;

        var action = history.get(current_index + 1);
        bool success = false;

        try {
            switch (action.action_type) {
                case UndoActionType.COPY:
                    success = yield redo_copy(action);
                    break;
                case UndoActionType.MOVE:
                    success = yield redo_move(action);
                    break;
                case UndoActionType.DELETE:
                    success = yield redo_delete(action);
                    break;
                case UndoActionType.RENAME:
                    success = yield redo_rename(action);
                    break;
                case UndoActionType.CREATE_DIR:
                    success = yield redo_create_dir(action);
                    break;
                case UndoActionType.BATCH:
                    success = yield redo_batch(action);
                    break;
            }
        } catch (Error e) {
            warning("Redo failed for '%s': %s", action.description, e.message);
            throw e;
        }

        if (success) {
            current_index++;
            emit_state_changed();
            action_performed("Redo: %s".printf(action.description));
        }

        return success;
    }

    public bool can_undo() {
        return current_index >= 0;
    }

    public bool can_redo() {
        return current_index + 1 < (int)history.size;
    }

    /* ================================================================ */
    /*  Query                                                           */
    /* ================================================================ */

    public string? get_undo_description() {
        if (!can_undo())
            return null;
        return history.get(current_index).description;
    }

    public string? get_redo_description() {
        if (!can_redo())
            return null;
        return history.get(current_index + 1).description;
    }

    /**
     * Clear the entire history and free memory.
     */
    public void clear_history() {
        history.clear();
        current_index = -1;
        active_batch = null;
        batch_depth = 0;
        emit_state_changed();
    }

    /* ================================================================ */
    /*  Undo implementations                                            */
    /* ================================================================ */

    /* COPY: undo → delete the copied file at dst_path */
    private async bool undo_copy(UndoAction action) throws Error {
        var file = File.new_for_path(action.dst_path);
        if (!file.query_exists())
            return true; // nothing to delete
        return yield file.trash_async(Priority.DEFAULT, null);
    }

    /* MOVE: undo → move dst back to src */
    private async bool undo_move(UndoAction action) throws Error {
        return yield fm.move(action.dst_path, action.src_path);
    }

    /* DELETE: undo → restore from trash */
    private async bool undo_delete(UndoAction action) throws Error {
        if (action.trash_uri == "")
            throw new IOError.FAILED("No trash URI stored for deleted file");
        return yield TrashManager.restore_file(action.trash_uri, action.src_path);
    }

    /* RENAME: undo → rename dst back to src */
    private async bool undo_rename(UndoAction action) throws Error {
        var src_file = File.new_for_path(action.src_path);
        var dst_file = File.new_for_path(action.dst_path);
        var info = yield dst_file.set_display_name_async(
            src_file.get_basename(), Priority.DEFAULT, null);
        return info != null;
    }

    /* CREATE_DIR: undo → delete the created directory */
    private async bool undo_create_dir(UndoAction action) throws Error {
        var file = File.new_for_path(action.dst_path);
        if (!file.query_exists())
            return true;

        // GVfs trash for directories is safer than recursive delete
        return yield file.trash_async(Priority.DEFAULT, null);
    }

    /* BATCH: undo each sub-action in reverse order */
    private async bool undo_batch(UndoAction action) throws Error {
        bool all_ok = true;
        Error? first_error = null;

        for (int i = (int)action.sub_actions.size - 1; i >= 0; i--) {
            var sub = action.sub_actions.get(i);
            try {
                bool sub_ok = false;
                switch (sub.action_type) {
                    case UndoActionType.COPY:
                        sub_ok = yield undo_copy(sub);
                        break;
                    case UndoActionType.MOVE:
                        sub_ok = yield undo_move(sub);
                        break;
                    case UndoActionType.DELETE:
                        sub_ok = yield undo_delete(sub);
                        break;
                    case UndoActionType.RENAME:
                        sub_ok = yield undo_rename(sub);
                        break;
                    case UndoActionType.CREATE_DIR:
                        sub_ok = yield undo_create_dir(sub);
                        break;
                    default:
                        warning("Unknown sub-action type in batch undo");
                        break;
                }
                if (!sub_ok) {
                    all_ok = false;
                }
            } catch (Error e) {
                warning("Batch undo sub-action failed: %s", e.message);
                if (first_error == null)
                    first_error = e;
                all_ok = false;
            }
        }

        if (first_error != null)
            throw first_error;

        return all_ok;
    }

    /* ================================================================ */
    /*  Redo implementations                                            */
    /* ================================================================ */

    /* COPY redo → copy src to dst again */
    private async bool redo_copy(UndoAction action) throws Error {
        return yield fm.copy(action.src_path, action.dst_path);
    }

    /* MOVE redo → move src to dst again */
    private async bool redo_move(UndoAction action) throws Error {
        return yield fm.move(action.src_path, action.dst_path);
    }

    /* DELETE redo → delete the file again */
    private async bool redo_delete(UndoAction action) throws Error {
        bool ok = yield TrashManager.trash_file(action.src_path);
        if (ok) {
            // Refresh the trash URI in case it changed
            var trashed_file = File.new_for_path(action.src_path);
            action.trash_uri = "trash:///" + trashed_file.get_basename();
        }
        return ok;
    }

    /* RENAME redo → rename src to dst again */
    private async bool redo_rename(UndoAction action) throws Error {
        var src_file = File.new_for_path(action.src_path);
        var dst_file = File.new_for_path(action.dst_path);
        var info = yield src_file.set_display_name_async(
            dst_file.get_basename(), Priority.DEFAULT, null);
        return info != null;
    }

    /* CREATE_DIR redo → recreate the directory */
    private async bool redo_create_dir(UndoAction action) throws Error {
        var file = File.new_for_path(action.dst_path);
        return yield file.make_directory_async(Priority.DEFAULT, null);
    }

    /* BATCH redo → redo each sub-action in forward order */
    private async bool redo_batch(UndoAction action) throws Error {
        bool all_ok = true;
        Error? first_error = null;

        for (int i = 0; i < (int)action.sub_actions.size; i++) {
            var sub = action.sub_actions.get(i);
            try {
                bool sub_ok = false;
                switch (sub.action_type) {
                    case UndoActionType.COPY:
                        sub_ok = yield redo_copy(sub);
                        break;
                    case UndoActionType.MOVE:
                        sub_ok = yield redo_move(sub);
                        break;
                    case UndoActionType.DELETE:
                        sub_ok = yield redo_delete(sub);
                        break;
                    case UndoActionType.RENAME:
                        sub_ok = yield redo_rename(sub);
                        break;
                    case UndoActionType.CREATE_DIR:
                        sub_ok = yield redo_create_dir(sub);
                        break;
                    default:
                        warning("Unknown sub-action type in batch redo");
                        break;
                }
                if (!sub_ok) {
                    all_ok = false;
                }
            } catch (Error e) {
                warning("Batch redo sub-action failed: %s", e.message);
                if (first_error == null)
                    first_error = e;
                all_ok = false;
            }
        }

        if (first_error != null)
            throw first_error;

        return all_ok;
    }

    /* ================================================================ */
    /*  Internal helpers                                                */
    /* ================================================================ */

    private UndoAction? active_batch = null;
    private int batch_depth = 0;

    /**
     * Remove any "redo" entries that exist beyond current_index.
     * Must be called before recording a new action.
     */
    private void truncate_redo_branch() {
        if (current_index + 1 < (int)history.size) {
            // Remove everything after current_index
            while ((int)history.size > current_index + 1) {
                history.remove_at((int)history.size - 1);
            }
        }
    }

    /**
     * Push an action onto the history stack, enforcing the MAX_HISTORY limit.
     */
    private void push_action(UndoAction action) {
        // Enforce limit: drop oldest entry if we're at capacity
        if ((int)history.size >= MAX_HISTORY) {
            history.remove_at(0);
            current_index--;
        }

        history.add(action);
        current_index++;
        emit_state_changed();
    }

    /**
     * Emit state-change signals when can_undo / can_redo status changes.
     */
    private void emit_state_changed() {
        can_undo_changed(can_undo());
        can_redo_changed(can_redo());
    }
}

}
