/*
 * archive_plugin.vala - TileFM Archive Plugin
 *
 * Archive operations via command-line tools:
 *   .zip    -> unzip / zip
 *   .tar.gz / .tgz  -> tar -xzf / tar -czf
 *   .tar.bz2        -> tar -xjf / tar -cjf
 *   .tar.xz         -> tar -xJf / tar -cJf
 *   .7z             -> 7z x / 7z a
 *
 * Integration with ContextMenu:
 *   - Right-click on archive  -> "Extract Here", "Extract to..."
 *   - Right-click on files    -> "Compress..." (submenu)
 */

namespace TileFm {

public class ArchivePlugin : Object {

    /* Archive format descriptor */
    public class ArchiveFormat : Object {
        public string extension { get; construct set; }
        public string description { get; construct set; }
        public string[] extract_cmd { get; construct set; }
        public string[] create_cmd { get; construct set; }

        public ArchiveFormat (string ext, string desc,
                              string[] extract, string[] create) {
            Object (
                extension: ext,
                description: desc,
                extract_cmd: extract,
                create_cmd: create
            );
        }
    }

    /* Supported formats registry */
    private static Gee.HashMap<string, ArchiveFormat> formats;

    private static void init_formats () {
        if (formats != null) return;

        formats = new Gee.HashMap<string, ArchiveFormat> ();

        formats[".zip"] = new ArchiveFormat (
            ".zip", "ZIP Archive",
            { "unzip", "$ARCHIVE", "-d", "$DEST" },
            { "zip", "-r", "$ARCHIVE", "$FILES" }
        );

        formats[".tar.gz"] = new ArchiveFormat (
            ".tar.gz", "Gzipped Tar Archive",
            { "tar", "-xzf", "$ARCHIVE", "-C", "$DEST" },
            { "tar", "-czf", "$ARCHIVE", "$FILES" }
        );

        formats[".tgz"] = new ArchiveFormat (
            ".tgz", "Gzipped Tar Archive",
            { "tar", "-xzf", "$ARCHIVE", "-C", "$DEST" },
            { "tar", "-czf", "$ARCHIVE", "$FILES" }
        );

        formats[".tar.bz2"] = new ArchiveFormat (
            ".tar.bz2", "Bzipped Tar Archive",
            { "tar", "-xjf", "$ARCHIVE", "-C", "$DEST" },
            { "tar", "-cjf", "$ARCHIVE", "$FILES" }
        );

        formats[".tar.xz"] = new ArchiveFormat (
            ".tar.xz", "XZ Tar Archive",
            { "tar", "-xJf", "$ARCHIVE", "-C", "$DEST" },
            { "tar", "-cJf", "$ARCHIVE", "$FILES" }
        );

        formats[".7z"] = new ArchiveFormat (
            ".7z", "7-Zip Archive",
            { "7z", "x", "$ARCHIVE", "-o$DEST" },
            { "7z", "a", "$ARCHIVE", "$FILES" }
        );
    }

    /* Detect format by filename */
    private static ArchiveFormat? detect_format (string filename) {
        init_formats ();

        string lower = filename.ascii_down ();

        /* Check longest extensions first (.tar.gz before .gz) */
        string[] ordered_exts = { ".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".zip", ".7z" };
        foreach (var ext in ordered_exts) {
            if (lower.has_suffix (ext)) {
                return formats[ext];
            }
        }
        return null;
    }

    /* Build argv by substituting template variables */
    private static string[] build_argv (string[] template,
                                         string archive_path,
                                         string? dest_dir,
                                         string[]? source_paths) {
        string[] result = {};

        foreach (var token in template) {
            if (token == "$ARCHIVE") {
                result += archive_path;
            } else if (token == "$DEST") {
                result += dest_dir ?? ".";
            } else if (token == "$FILES") {
                if (source_paths != null) {
                    foreach (var path in source_paths) {
                        result += path;
                    }
                }
            } else if (token == "-o$DEST") {
                /* 7z uses -oDEST (no space) */
                result += "-o" + (dest_dir ?? ".");
            } else {
                result += token;
            }
        }
        return result;
    }

    /**
     * Check if a file is an archive by extension.
     */
    public static bool is_archive (string filename) {
        return detect_format (filename) != null;
    }

    /**
     * Get list of supported archive format extensions.
     */
    public static string[] get_supported_formats () {
        init_formats ();
        return formats.keys.to_array ();
    }

    /**
     * Get human-readable description for a format.
     */
    public static string? get_format_description (string ext) {
        init_formats ();
        var fmt = formats[ext];
        return fmt != null ? fmt.description : null;
    }

    /**
     * Extract an archive to a destination directory.
     *
     * @param archive_path Full path to the archive file.
     * @param dest_dir     Destination directory (created if needed).
     * @return true on success.
     */
    public static async bool extract (string archive_path, string dest_dir) {
        var fmt = detect_format (archive_path);
        if (fmt == null) {
            warning ("Unknown archive format: %s", archive_path);
            return false;
        }

        /* Create destination directory */
        var dest = File.new_for_path (dest_dir);
        try {
            if (!dest.query_exists ()) {
                yield dest.make_directory_async (Priority.DEFAULT, null);
            }
        } catch (Error e) {
            warning ("Failed to create dest dir '%s': %s", dest_dir, e.message);
            return false;
        }

        string[] argv = build_argv (fmt.extract_cmd, archive_path, dest_dir, null);

        int exit_status;
        string stdout_str;
        string stderr_str;

        try {
            bool ok = yield execute_command_async (argv);
            if (!ok) {
                warning ("Extract failed");
                return false;
            }
            return true;
        } catch (Error e) {
            warning ("Extract failed: %s", e.message);
            return false;
        }
    }

    /**
     * Extract an archive to a directory chosen by the user via a
     * Gtk.FileChooserDialog.  The dialog is parented on @parent.
     */
    public static async bool extract_with_dialog (string archive_path,
                                                   Gtk.Window parent) {
        var chooser = new Gtk.FileChooserDialog (
            "Extract to...",
            parent,
            Gtk.FileChooserAction.SELECT_FOLDER,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_Extract", Gtk.ResponseType.ACCEPT,
            null
        );

        /* Suggest the archive's parent directory */
        var archive_file = File.new_for_path (archive_path);
        var parent_dir = archive_file.get_parent ();
        if (parent_dir != null) {
            try {
                chooser.set_current_folder (parent_dir.get_path ());
            } catch (Error e) {
                /* ignore */
            }
        }

        int response = chooser.run ();
        string? chosen_dir = chooser.get_filename ();
        chooser.destroy ();

        if (response != Gtk.ResponseType.ACCEPT || chosen_dir == null) {
            return false;
        }

        return yield extract (archive_path, chosen_dir);
    }

    /**
     * Create an archive from a list of source paths.
     *
     * @param archive_path Output archive path (extension determines format).
     * @param source_paths Files/directories to include.
     * @return true on success.
     */
    public static async bool create (string archive_path, string[] source_paths) {
        if (source_paths.length == 0) {
            warning ("No source paths given for archive creation.");
            return false;
        }

        var fmt = detect_format (archive_path);
        if (fmt == null) {
            warning ("Cannot determine archive format from path: %s", archive_path);
            return false;
        }

        /* For tar formats, change to parent directory so entries are relative */
        string? work_dir = null;
        string lower = archive_path.ascii_down ();
        if (lower.has_suffix (".tar.gz") || lower.has_suffix (".tgz") ||
            lower.has_suffix (".tar.bz2") || lower.has_suffix (".tar.xz")) {
            /* Use the parent of the first source path as working dir */
            var first_file = File.new_for_path (source_paths[0]);
            var first_parent = first_file.get_parent ();
            if (first_parent != null) {
                work_dir = first_parent.get_path ();
            }
        }

        /* For tar: convert absolute paths to basenames when using work_dir */
        string[] effective_paths;
        if (work_dir != null) {
            effective_paths = new string[source_paths.length];
            for (int i = 0; i < source_paths.length; i++) {
                effective_paths[i] = Path.get_basename (source_paths[i]);
            }
        } else {
            effective_paths = source_paths;
        }

        string[] argv = build_argv (fmt.create_cmd, archive_path, null, effective_paths);

        int exit_status;
        string stdout_str;
        string stderr_str;

        try {
            bool ok = yield execute_command_async (argv, work_dir);
            if (!ok) {
                warning ("Create archive failed");
                return false;
            }
            return true;
        } catch (Error e) {
            warning ("Create archive failed: %s", e.message);
            return false;
        }
    }

    /**
     * Create an archive with a user-chosen path via Gtk.FileChooserDialog.
     * @param format_ext One of the supported extensions (e.g. ".zip").
     */
    public static async bool create_with_dialog (string[] source_paths,
                                                  string format_ext,
                                                  Gtk.Window? parent) {
        if (source_paths.length == 0) return false;

        /* Pick a default name from the first source */
        string default_name = Path.get_basename (source_paths[0]) + format_ext;

        var chooser = new Gtk.FileChooserDialog (
            "Create Archive",
            parent,
            Gtk.FileChooserAction.SAVE,
            "_Cancel", Gtk.ResponseType.CANCEL,
            "_Create", Gtk.ResponseType.ACCEPT,
            null
        );

        chooser.set_current_name (default_name);

        /* Start in the parent directory of the first source */
        var first_file = File.new_for_path (source_paths[0]);
        var first_parent = first_file.get_parent ();
        if (first_parent != null) {
            try {
                chooser.set_current_folder (first_parent.get_path ());
            } catch (Error e) {
                /* ignore */
            }
        }

        int response = chooser.run ();
        string? chosen_path = chooser.get_filename ();
        chooser.destroy ();

        if (response != Gtk.ResponseType.ACCEPT || chosen_path == null) {
            return false;
        }

        /* Auto-append extension if missing */
        string lower = chosen_path.ascii_down ();
        if (!lower.has_suffix (format_ext)) {
            chosen_path += format_ext;
        }

        return yield create (chosen_path, source_paths);
    }

    /**
     * Extract an archive to the same directory it resides in.
     */
    public static async bool extract_here (string archive_path) {
        var file = File.new_for_path (archive_path);
        var parent = file.get_parent ();
        if (parent == null) {
            return yield extract (archive_path, ".");
        }
        return yield extract (archive_path, parent.get_path ());
    }

    /* ── Command execution ─────────────────────────────────────── */

    /**
     * Execute an external command asynchronously.
     *
     * @param argv       Command line arguments.
     * @param exit_status Output: process exit code.
     * @param stdout_str  Output: captured stdout.
     * @param stderr_str  Output: captured stderr.
     * @param working_dir Optional working directory, or null.
     * @return true if the process started successfully.
     */
    private static async bool execute_command_async (string[] argv,
                                                       string? working_dir = null)
                                                       throws Error {
        string stdout_str = "";
        string stderr_str = "";
        int exit_status = -1;

        string cmd = string.joinv (" ", argv);
        debug ("Archive command: %s", cmd);

        /* Build launcher */
        var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE
                                                | SubprocessFlags.STDERR_PIPE);
        if (working_dir != null) {
            launcher.set_cwd (working_dir);
        }

        var subprocess = launcher.spawnv (argv);

        /* Read stdout */
        var stdout_pipe = subprocess.get_stdout_pipe ();
        if (stdout_pipe != null) {
            var dis = new DataInputStream (stdout_pipe);
            var sb = new StringBuilder ();
            string? line;
            while ((line = yield dis.read_line_async (Priority.DEFAULT, null)) != null) {
                sb.append (line);
                sb.append_c ('\n');
            }
            stdout_str = sb.str;
        }

        /* Read stderr */
        var stderr_pipe = subprocess.get_stderr_pipe ();
        if (stderr_pipe != null) {
            var dis = new DataInputStream (stderr_pipe);
            var sb = new StringBuilder ();
            string? line;
            while ((line = yield dis.read_line_async (Priority.DEFAULT, null)) != null) {
                sb.append (line);
                sb.append_c ('\n');
            }
            stderr_str = sb.str;
        }

        yield subprocess.wait_async (null);
        exit_status = subprocess.get_exit_status ();

        return exit_status == 0;
    }
}

}
