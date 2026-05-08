/*
 * clipboard_manager.vala
 * TileFM — Clipboard Manager for Cut/Copy/Paste operations
 */

public enum ClipboardAction {
    NONE,
    CUT,
    COPY
}

public class ClipboardManager : Object {
    public signal void changed();

    public bool has_files { get; private set; default = false; }
    public ClipboardAction action { get; private set; default = ClipboardAction.NONE; }

    private string[] stored_files = {};

    public void cut_files(string[] paths) {
        stored_files = {};
        foreach (var path in paths) {
            stored_files += path;
        }
        action = ClipboardAction.CUT;
        has_files = true;
        changed();
    }

    public void copy_files(string[] paths) {
        stored_files = {};
        foreach (var path in paths) {
            stored_files += path;
        }
        action = ClipboardAction.COPY;
        has_files = true;
        changed();
    }

    public string[] get_files() {
        return stored_files;
    }

    public void clear() {
        stored_files = {};
        action = ClipboardAction.NONE;
        has_files = false;
        changed();
    }

    public bool is_empty() {
        return !has_files || stored_files.length == 0;
    }
}
