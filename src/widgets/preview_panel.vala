/* preview_panel.vala - Preview Panel for TileFM
 * A Dolphin-style F11 preview panel showing file info, icons,
 * image previews, and text snippets in a sidebar.
 */

using Gtk;
using Gdk;
using GLib;

namespace TileFm {

public class PreviewPanel : Gtk.Box {
    // Widgets
    private Gtk.Stack preview_stack;
    private Gtk.Label file_name_label;
    private Gtk.Label file_info_label;
    private Gtk.Image preview_image;
    private Gtk.Image file_icon_image;
    private Gtk.TextView text_preview;
    private Gtk.ScrolledWindow text_scroll;
    private Gtk.Spinner spinner;
    private Gtk.Label dir_count_label;

    // Pixbuf cache for repeated previews
    private HashTable<string, Gdk.Pixbuf> pixbuf_cache;
    private const int CACHE_MAX_SIZE = 10;

    // Current loading cancellable
    private Cancellable load_cancellable;

    // Supported image mime types
    private const string[] IMAGE_MIME_TYPES = {
        "image/png", "image/jpeg", "image/jpg", "image/gif",
        "image/bmp", "image/x-bmp", "image/svg+xml",
        "image/webp", "image/tiff", "image/x-icon"
    };

    // Text extensions for snippet preview
    private const string[] TEXT_EXTENSIONS = {
        ".txt", ".md", ".markdown", ".vala", ".vapi",
        ".c", ".h", ".cpp", ".hpp", ".cc",
        ".py", ".js", ".ts", ".sh", ".bash", ".zsh",
        ".json", ".xml", ".yaml", ".yml", ".toml",
        ".ini", ".conf", ".cfg", ".log", ".css",
        ".html", ".htm", ".go", ".rs", ".java",
        ".rb", ".php", ".lua", ".pl"
    };

    public PreviewPanel () {
        Object (
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 0
        );

        // Cache init
        pixbuf_cache = new HashTable<string, Gdk.Pixbuf> (str_hash, str_equal);

        setup_ui ();
        setup_styles ();
    }

    private void setup_ui () {
        // Left separator border
        get_style_context ().add_class ("preview-panel");

        // Main vertical layout
        width_request = 280;
        margin = 12;

        // -- File name (top, prominent)
        file_name_label = new Gtk.Label ("");
        file_name_label.use_markup = true;
        file_name_label.halign = Gtk.Align.CENTER;
        file_name_label.valign = Gtk.Align.START;
        file_name_label.wrap = true;
        file_name_label.max_width_chars = 24;
        file_name_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        file_name_label.get_style_context ().add_class ("preview-filename");
        file_name_label.margin_bottom = 8;
        pack_start (file_name_label, false, false, 0);

        // -- Separator
        Gtk.Separator sep_top = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        sep_top.margin_bottom = 8;
        pack_start (sep_top, false, false, 0);

        // -- Icon + Info area
        Gtk.Box icon_info_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
        icon_info_box.halign = Gtk.Align.CENTER;
        icon_info_box.margin_bottom = 8;

        file_icon_image = new Gtk.Image ();
        file_icon_image.set_size_request (128, 128);
        file_icon_image.pixel_size = 128;
        icon_info_box.pack_start (file_icon_image, false, false, 0);

        pack_start (icon_info_box, false, false, 0);

        // -- File info label (MIME, size, date)
        file_info_label = new Gtk.Label ("");
        file_info_label.use_markup = true;
        file_info_label.halign = Gtk.Align.START;
        file_info_label.valign = Gtk.Align.START;
        file_info_label.xalign = 0;
        file_info_label.wrap = true;
        file_info_label.margin_bottom = 8;
        file_info_label.get_style_context ().add_class ("preview-info");
        pack_start (file_info_label, false, false, 0);

        // -- Separator
        Gtk.Separator sep_mid = new Gtk.Separator (Gtk.Orientation.HORIZONTAL);
        sep_mid.margin_bottom = 8;
        pack_start (sep_mid, false, false, 0);

        // -- Preview stack (image / text / directory count / empty)
        preview_stack = new Gtk.Stack ();
        preview_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
        preview_stack.set_transition_duration (150);
        preview_stack.vexpand = true;

        // Image preview
        preview_image = new Gtk.Image ();
        preview_image.halign = Gtk.Align.CENTER;
        preview_image.valign = Gtk.Align.CENTER;

        Gtk.ScrolledWindow image_scroll = new Gtk.ScrolledWindow (null, null);
        image_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        image_scroll.add (preview_image);
        preview_stack.add_named (image_scroll, "image");

        // Text preview
        text_preview = new Gtk.TextView ();
        text_preview.editable = false;
        text_preview.cursor_visible = false;
        text_preview.monospace = true;
        text_preview.wrap_mode = Gtk.WrapMode.WORD;
        text_preview.left_margin = 8;
        text_preview.right_margin = 8;
        text_preview.top_margin = 8;
        text_preview.bottom_margin = 8;
        text_preview.get_style_context ().add_class ("preview-text");

        text_scroll = new Gtk.ScrolledWindow (null, null);
        text_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        text_scroll.add (text_preview);
        preview_stack.add_named (text_scroll, "text");

        // Directory count
        dir_count_label = new Gtk.Label ("");
        dir_count_label.use_markup = true;
        dir_count_label.halign = Gtk.Align.CENTER;
        dir_count_label.valign = Gtk.Align.CENTER;
        dir_count_label.get_style_context ().add_class ("preview-dirinfo");

        Gtk.ScrolledWindow dir_scroll = new Gtk.ScrolledWindow (null, null);
        dir_scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        Gtk.Box dir_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        dir_box.halign = Gtk.Align.CENTER;
        dir_box.valign = Gtk.Align.CENTER;
        dir_box.vexpand = true;
        dir_box.pack_start (dir_count_label, false, false, 0);
        dir_scroll.add (dir_box);
        preview_stack.add_named (dir_scroll, "directory");

        // Empty state
        Gtk.Box empty_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
        empty_box.halign = Gtk.Align.CENTER;
        empty_box.valign = Gtk.Align.CENTER;
        empty_box.vexpand = true;

        Gtk.Image empty_icon = new Gtk.Image.from_icon_name (
            "document-open-symbolic", Gtk.IconSize.DIALOG
        );
        empty_icon.set_pixel_size (64);
        empty_icon.get_style_context ().add_class ("preview-empty-icon");

        Gtk.Label empty_label = new Gtk.Label ("No file selected");
        empty_label.get_style_context ().add_class ("preview-empty-label");

        empty_box.pack_start (empty_icon, false, false, 0);
        empty_box.pack_start (empty_label, false, false, 0);
        preview_stack.add_named (empty_box, "empty");

        // Loading state
        Gtk.Box loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
        loading_box.halign = Gtk.Align.CENTER;
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.vexpand = true;

        spinner = new Gtk.Spinner ();
        spinner.set_size_request (32, 32);
        Gtk.Label loading_label = new Gtk.Label ("Loading...");
        loading_label.get_style_context ().add_class ("preview-loading");

        loading_box.pack_start (spinner, false, false, 0);
        loading_box.pack_start (loading_label, false, false, 0);
        preview_stack.add_named (loading_box, "loading");

        pack_start (preview_stack, true, true, 0);

        // Show empty state initially
        preview_stack.set_visible_child_name ("empty");
    }

    private void setup_styles () {
        string css = """
            .preview-panel {
                border-left: 2px solid alpha(@theme_fg_color, 0.15);
                background-color: alpha(@theme_bg_color, 0.97);
            }
            .preview-filename {
                font-weight: bold;
                font-size: 11pt;
            }
            .preview-info {
                font-size: 9pt;
                color: alpha(@theme_fg_color, 0.75);
            }
            .preview-text {
                font-family: "Monospace";
                font-size: 9pt;
                background-color: alpha(@theme_base_color, 0.95);
                color: @theme_text_color;
            }
            .preview-dirinfo {
                font-size: 11pt;
                font-weight: bold;
                color: alpha(@theme_fg_color, 0.8);
            }
            .preview-empty-icon {
                opacity: 0.35;
            }
            .preview-empty-label {
                font-size: 10pt;
                color: alpha(@theme_fg_color, 0.45);
            }
            .preview-loading {
                font-size: 9pt;
                color: alpha(@theme_fg_color, 0.6);
            }
        """;

        Gtk.CssProvider provider = new Gtk.CssProvider ();
        try {
            provider.load_from_data (css, css.length);
            Gtk.StyleContext.add_provider_for_screen (
                Gdk.Screen.get_default (),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        } catch (Error e) {
            warning ("Failed to load PreviewPanel CSS: %s", e.message);
        }
    }

    /**
     * Update the preview panel for the given file path.
     * @param path Full path to the file, or null to clear.
     * @param fm FileManager instance for additional queries.
     */
    public void update_preview (string? path, FileManager fm) {
        if (path == null || path == "") {
            clear ();
            return;
        }

        // Cancel previous load
        if (load_cancellable != null) {
            load_cancellable.cancel ();
        }
        load_cancellable = new Cancellable ();

        Cancellable cancellable = load_cancellable;

        // Show loading state
        spinner.start ();
        preview_stack.set_visible_child_name ("loading");

        // Start async load
        load_preview_async.begin (path, fm, cancellable, (obj, res) => {
            try {
                load_preview_async.end (res);
            } catch (Error e) {
                if (!(e is IOError.CANCELLED)) {
                    show_fallback (path, e.message);
                }
            }
        });
    }

    /**
     * Clear the preview panel to empty state.
     */
    public void clear () {
        if (load_cancellable != null) {
            load_cancellable.cancel ();
        }

        file_name_label.set_markup ("");
        file_info_label.set_markup ("");
        file_icon_image.clear ();
        preview_image.clear ();
        text_preview.buffer.text = "";
        dir_count_label.set_markup ("");

        preview_stack.set_visible_child_name ("empty");
        spinner.stop ();
    }

    private async void load_preview_async (string path, FileManager fm, Cancellable? cancellable) throws Error {
        File file = File.new_for_path (path);
        FileInfo? info = null;

        // Query file info
        try {
            info = yield file.query_info_async (
                "standard::content-type,standard::size,standard::display-name," +
                "time::modified,standard::icon,standard::type,standard::symbolic-icon",
                FileQueryInfoFlags.NONE,
                Priority.DEFAULT,
                cancellable
            );
        } catch (Error e) {
            if (cancellable != null && cancellable.is_cancelled ()) {
                throw new IOError.CANCELLED ("Loading cancelled");
            }
        }

        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Loading cancelled");
        }

        // Determine mime type
        string mime_type = "application/octet-stream";
        if (info != null) {
            mime_type = info.get_content_type () ?? mime_type;
        } else {
            mime_type = detect_mime_from_extension (path);
        }

        // Extract basic info
        string display_name = info != null ? info.get_display_name () : Path.get_basename (path);
        int64 file_size = info != null ? info.get_size () : 0;
        DateTime? mtime = null;
        if (info != null) {
            try {
                var mod_time = info.get_modification_date_time ();
                if (mod_time != null) {
                    mtime = mod_time;
                }
            } catch (Error e) {}
        }

        // Update basic info (name + icon + details) on UI thread via idle
        Idle.add (() => {
            update_file_info_ui (display_name, mime_type, file_size, mtime, info);
            return Source.REMOVE;
        });

        // Route by file type
        if (info != null && info.get_file_type () == FileType.DIRECTORY) {
            Idle.add (() => {
                if (cancellable != null && cancellable.is_cancelled ()) return Source.REMOVE;
                show_directory_preview (path);
                return Source.REMOVE;
            });
        } else if (is_image_mime (mime_type)) {
            Gdk.Pixbuf? img = yield load_image_preview_async (path, mime_type, cancellable);
            Idle.add (() => {
                if (cancellable != null && cancellable.is_cancelled ()) return Source.REMOVE;
                if (img != null) {
                    show_image_preview (img);
                } else {
                    show_fallback (path, "Could not load image");
                }
                return Source.REMOVE;
            });
        } else if (is_text_mime (mime_type) || is_text_extension (path)) {
            string? snippet = yield load_text_snippet_async (path, cancellable);
            Idle.add (() => {
                if (cancellable != null && cancellable.is_cancelled ()) return Source.REMOVE;
                if (snippet != null) {
                    show_text_preview (snippet);
                } else {
                    show_fallback (path, "Could not read text");
                }
                return Source.REMOVE;
            });
        } else {
            Idle.add (() => {
                if (cancellable != null && cancellable.is_cancelled ()) return Source.REMOVE;
                show_fallback (path, null);
                return Source.REMOVE;
            });
        }
    }

    private void update_file_info_ui (string name, string mime, int64 size,
                                       DateTime? mtime, FileInfo? info) {
        // File name
        string escaped_name = Markup.escape_text (name);
        file_name_label.set_markup ("<b>%s</b>".printf (escaped_name));

        // File icon
        Icon? icon = null;
        if (info != null) {
            icon = info.get_symbolic_icon () ?? info.get_icon ();
        }

        if (icon != null) {
            Gtk.IconTheme theme = Gtk.IconTheme.get_default ();
            Gdk.Pixbuf? icon_pixbuf = null;
            try {
                string? icon_name = icon.to_string();
                if (icon_name != null) {
                    icon_pixbuf = theme.load_icon(icon_name, 128, Gtk.IconLookupFlags.FORCE_SIZE);
                }
            } catch (Error e) {
                // fallback
            }

            if (icon_pixbuf != null) {
                file_icon_image.set_from_pixbuf (icon_pixbuf);
            } else {
                file_icon_image.set_from_gicon (icon, Gtk.IconSize.DIALOG);
                file_icon_image.set_pixel_size (128);
            }
        } else {
            file_icon_image.set_from_icon_name ("text-x-generic", Gtk.IconSize.DIALOG);
            file_icon_image.set_pixel_size (128);
        }

        // File info details
        string size_str = format_size (size);
        string mime_str = mime;
        string time_str = mtime != null ? mtime.format ("%Y-%m-%d %H:%M") : "unknown";

        string info_markup = """
            <span size='small'>%s</span>
            <span size='small'>%s</span>
            <span size='small'>%s</span>
        """.printf (
            Markup.escape_text (mime_str),
            Markup.escape_text (size_str),
            Markup.escape_text (time_str)
        );

        file_info_label.set_markup (info_markup);
    }

    private void show_image_preview (Gdk.Pixbuf pixbuf) {
        preview_image.set_from_pixbuf (pixbuf);
        preview_stack.set_visible_child_name ("image");
        spinner.stop ();
    }

    private void show_text_preview (string snippet) {
        text_preview.buffer.text = snippet;
        preview_stack.set_visible_child_name ("text");
        spinner.stop ();
    }

    private void show_directory_preview (string path) {
        // Count items in directory
        File dir = File.new_for_path (path);
        int count = 0;
        int file_count = 0;
        int dir_count = 0;

        try {
            FileEnumerator enumerator = dir.enumerate_children (
                "standard::type",
                FileQueryInfoFlags.NONE,
                null
            );

            FileInfo? child_info;
            while ((child_info = enumerator.next_file (null)) != null) {
                count++;
                if (child_info.get_file_type () == FileType.DIRECTORY) {
                    dir_count++;
                } else {
                    file_count++;
                }
            }
        } catch (Error e) {
            warning ("Failed to count directory items: %s", e.message);
        }

        string markup = """<b>%d items</b>
<span size='small'>%d files, %d directories</span>""".printf (count, file_count, dir_count);

        dir_count_label.set_markup (markup);
        preview_stack.set_visible_child_name ("directory");
        spinner.stop ();
    }

    private void show_fallback (string path, string? error_msg) {
        preview_image.clear ();
        text_preview.buffer.text = "";

        if (error_msg != null) {
            string markup = """<span size='small' color='#cc4444'>%s</span>""".printf (
                Markup.escape_text (error_msg)
            );
            dir_count_label.set_markup (markup);
            preview_stack.set_visible_child_name ("directory");
        } else {
            // Just show the icon and info we already have, hide preview area
            preview_stack.set_visible_child_name ("empty");
        }

        spinner.stop ();
    }

    private async Gdk.Pixbuf? load_image_preview_async (string path, string mime_type,
                                                         Cancellable? cancellable) throws Error {
        // Check cache
        if (pixbuf_cache.contains (path)) {
            return pixbuf_cache.lookup (path);
        }

        Gdk.Pixbuf? pixbuf = null;

        if (mime_type == "image/svg+xml") {
            try {
                pixbuf = new Gdk.Pixbuf.from_file_at_size (path, 240, 240);
            } catch (Error e) {
                warning ("SVG load failed: %s", e.message);
            }
        } else {
            try {
                File file = File.new_for_path (path);
                FileInputStream stream = yield file.read_async (Priority.DEFAULT, cancellable);

                var loader = new Gdk.PixbufLoader ();
                loader.set_size (240, 240);

                uint8[] buffer = new uint8[32768];
                ssize_t bytes_read;
                while ((bytes_read = yield stream.read_async (buffer, Priority.DEFAULT, cancellable)) > 0) {
                    if (cancellable != null && cancellable.is_cancelled ()) {
                        loader.close ();
                        throw new IOError.CANCELLED ("Loading cancelled");
                    }
                    loader.write (buffer[0:bytes_read]);
                }
                loader.close ();
                pixbuf = loader.get_pixbuf ();
            } catch (Error e) {
                // Fallback to sync load
                try {
                    pixbuf = new Gdk.Pixbuf.from_file_at_size (path, 240, 240);
                } catch (Error e2) {
                    throw e2;
                }
            }
        }

        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Loading cancelled");
        }

        if (pixbuf != null) {
            cache_pixbuf (path, pixbuf);
        }

        return pixbuf;
    }

    private async string? load_text_snippet_async (string path, Cancellable? cancellable) throws Error {
        try {
            File file = File.new_for_path (path);
            uint8[] raw_contents;
            yield file.load_contents_async (cancellable, out raw_contents, null);

            if (cancellable != null && cancellable.is_cancelled ()) {
                throw new IOError.CANCELLED ("Loading cancelled");
            }

            string contents = (string) raw_contents;

            // Limit to 500 chars for preview panel
            const int MAX_SNIPPET = 500;
            if (contents.length > MAX_SNIPPET) {
                // Try to end at a newline
                int cut = MAX_SNIPPET;
                int nl_pos = contents.index_of ("\n", MAX_SNIPPET - 100);
                if (nl_pos > 0 && nl_pos < MAX_SNIPPET + 200) {
                    cut = nl_pos;
                }
                return contents.substring (0, cut) + "\n\n[...]";
            }

            return contents;
        } catch (Error e) {
            if (e is IOError.CANCELLED) throw e;
            warning ("Text load failed: %s", e.message);
            return null;
        }
    }

    private void cache_pixbuf (string path, Gdk.Pixbuf pixbuf) {
        if (pixbuf_cache.size () >= CACHE_MAX_SIZE) {
            var keys = pixbuf_cache.get_keys ();
            int to_remove = CACHE_MAX_SIZE / 2;
            int removed = 0;
            foreach (string key in keys) {
                if (removed >= to_remove) break;
                pixbuf_cache.remove (key);
                removed++;
            }
        }

        pixbuf_cache.insert (path, pixbuf);
    }

    private bool is_image_mime (string mime) {
        foreach (string img_mime in IMAGE_MIME_TYPES) {
            if (mime == img_mime) return true;
        }
        return mime.has_prefix ("image/");
    }

    private bool is_text_mime (string mime) {
        return mime.has_prefix ("text/") ||
               mime == "application/json" ||
               mime == "application/xml" ||
               mime == "application/javascript" ||
               mime == "application/x-shellscript";
    }

    private bool is_text_extension (string path) {
        string lower = path.ascii_down ();
        foreach (string ext in TEXT_EXTENSIONS) {
            if (lower.has_suffix (ext)) return true;
        }
        return false;
    }

    private string detect_mime_from_extension (string path) {
        string lower = path.ascii_down ();
        if (lower.has_suffix (".png")) return "image/png";
        if (lower.has_suffix (".jpg") || lower.has_suffix (".jpeg")) return "image/jpeg";
        if (lower.has_suffix (".gif")) return "image/gif";
        if (lower.has_suffix (".bmp")) return "image/bmp";
        if (lower.has_suffix (".svg")) return "image/svg+xml";
        if (lower.has_suffix (".webp")) return "image/webp";
        if (lower.has_suffix (".txt")) return "text/plain";
        if (lower.has_suffix (".md")) return "text/markdown";
        if (lower.has_suffix (".vala")) return "text/x-vala";
        if (lower.has_suffix (".c")) return "text/x-c";
        if (lower.has_suffix (".h")) return "text/x-c";
        if (lower.has_suffix (".py")) return "text/x-python";
        if (lower.has_suffix (".json")) return "application/json";
        if (lower.has_suffix (".xml")) return "application/xml";
        if (lower.has_suffix (".html") || lower.has_suffix (".htm")) return "text/html";
        if (lower.has_suffix (".css")) return "text/css";
        if (lower.has_suffix (".log")) return "text/plain";
        if (lower.has_suffix (".pdf")) return "application/pdf";
        return "application/octet-stream";
    }

    private string format_size (int64 size) {
        if (size < 1024) return "%lld B".printf (size);
        if (size < 1024 * 1024) return "%.1f KB".printf (size / 1024.0);
        if (size < 1024 * 1024 * 1024) return "%.1f MB".printf (size / (1024.0 * 1024.0));
        return "%.1f GB".printf (size / (1024.0 * 1024.0 * 1024.0));
    }
}

}
