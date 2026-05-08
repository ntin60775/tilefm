/* quick_look.vala - Quick Look popup for TileFM
 * A Space-key triggered preview window supporting images, text, PDF,
 * directories, and other file types with keyboard navigation.
 */

using Gtk;
using Gdk;
using GLib;

namespace TileFm {
    public class QuickLook : Gtk.Window {
    private string current_path;
    private FileManager file_manager;
    private Gtk.Stack content_stack;
    private Gtk.Label info_label;
    private Gtk.ScrolledWindow text_scroll;
    private Gtk.ScrolledWindow dir_scroll;
    private Gtk.Image image_view;
    private Gtk.TextView text_view;
    private Gtk.ListStore dir_list;
    private Gtk.TreeView dir_tree;
    private Gtk.Box info_box;
    private Gtk.Box main_box;
    private Gtk.Spinner spinner;
    private Gtk.Label loading_label;
    private Gtk.Box loading_box;

    // Cache for pixbufs: path -> Pixbuf
    private HashTable<string, Gdk.Pixbuf> pixbuf_cache;
    private const int CACHE_MAX_SIZE = 20;

    // Directory listing for navigation
    private string[] sibling_files;
    private int current_index;

    // Async loading state
    private Cancellable load_cancellable;

    // Supported image mime type prefixes
    private const string[] IMAGE_MIME_TYPES = {
        "image/png", "image/jpeg", "image/jpg", "image/gif",
        "image/bmp", "image/x-bmp", "image/svg+xml",
        "image/webp", "image/tiff", "image/x-icon"
    };

    // Supported text extensions (fallback when mime is generic)
    private const string[] TEXT_EXTENSIONS = {
        ".txt", ".md", ".markdown", ".vala", ".vapi",
        ".c", ".h", ".cpp", ".hpp", ".cc",
        ".py", ".js", ".ts", ".sh", ".bash", ".zsh",
        ".json", ".xml", ".yaml", ".yml", ".toml",
        ".ini", ".conf", ".cfg", ".log", ".css",
        ".html", ".htm", ".go", ".rs", ".java",
        ".rb", ".php", ".lua", ".pl"
    };

    // Syntax highlight colors (basic)
    private const string COMMENT_COLOR = "#7F7F7F";
    private const string KEYWORD_COLOR = "#0000FF";
    private const string STRING_COLOR = "#008000";

    public QuickLook (FileManager fm) {
        Object (
            type: Gtk.WindowType.TOPLEVEL,
            window_position: Gtk.WindowPosition.CENTER,
            decorated: false,
            skip_taskbar_hint: true,
            skip_pager_hint: true,
            modal: false,
            type_hint: Gdk.WindowTypeHint.DIALOG
        );

        this.file_manager = fm;
        this.current_path = "";
        this.sibling_files = new string[0];
        this.current_index = 0;

        // Cache init
        pixbuf_cache = new HashTable<string, Gdk.Pixbuf> (str_hash, str_equal);

        // Setup UI
        setup_ui ();
        setup_styles ();
        connect_events ();
    }

    private void setup_ui () {
        // Set size to 70% of screen
        Gdk.Screen screen = Gdk.Screen.get_default ();
        int sw = screen.get_width ();
        int sh = screen.get_height ();
        set_default_size ((int) (sw * 0.7), (int) (sh * 0.7));

        main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        add (main_box);

        // Loading indicator
        loading_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        loading_box.halign = Gtk.Align.CENTER;
        loading_box.valign = Gtk.Align.CENTER;
        loading_box.vexpand = true;
        spinner = new Gtk.Spinner ();
        spinner.set_size_request (48, 48);
        loading_label = new Gtk.Label ("Loading...");
        loading_label.get_style_context ().add_class ("quicklook-loading");
        loading_box.pack_start (spinner, false, false, 0);
        loading_box.pack_start (loading_label, false, false, 0);

        // Content stack - switches between content types
        content_stack = new Gtk.Stack ();
        content_stack.set_transition_type (Gtk.StackTransitionType.CROSSFADE);
        content_stack.set_transition_duration (200);

        // -- Image view
        image_view = new Gtk.Image ();
        image_view.halign = Gtk.Align.CENTER;
        image_view.valign = Gtk.Align.CENTER;

        Gtk.ScrolledWindow image_scroll = new Gtk.ScrolledWindow (null, null);
        image_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        Gtk.Viewport image_vp = new Gtk.Viewport (null, null);
        image_vp.halign = Gtk.Align.CENTER;
        image_vp.valign = Gtk.Align.CENTER;
        Gtk.Box image_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        image_box.halign = Gtk.Align.CENTER;
        image_box.valign = Gtk.Align.CENTER;
        image_box.pack_start (image_view, true, true, 0);
        image_vp.add (image_box);
        image_scroll.add (image_vp);
        content_stack.add_named (image_scroll, "image");

        // -- Text view
        text_view = new Gtk.TextView ();
        text_view.editable = false;
        text_view.cursor_visible = false;
        text_view.monospace = true;
        text_view.wrap_mode = Gtk.WrapMode.NONE;
        text_view.left_margin = 12;
        text_view.right_margin = 12;
        text_view.top_margin = 12;
        text_view.bottom_margin = 12;
        text_view.get_style_context ().add_class ("quicklook-text");

        text_scroll = new Gtk.ScrolledWindow (null, null);
        text_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        text_scroll.add (text_view);
        content_stack.add_named (text_scroll, "text");

        // -- Directory listing
        dir_list = new Gtk.ListStore (2, typeof (string), typeof (string));
        dir_tree = new Gtk.TreeView.with_model (dir_list);
        dir_tree.headers_visible = true;

        Gtk.CellRendererText name_cell = new Gtk.CellRendererText ();
        Gtk.TreeViewColumn name_col = new Gtk.TreeViewColumn ();
        name_col.title = "Name";
        name_col.pack_start (name_cell, true);
        name_col.add_attribute (name_cell, "text", 0);
        name_col.set_resizable (true);
        name_col.set_min_width (300);
        dir_tree.append_column (name_col);

        Gtk.CellRendererText type_cell = new Gtk.CellRendererText ();
        type_cell.ellipsize = Pango.EllipsizeMode.END;
        Gtk.TreeViewColumn type_col = new Gtk.TreeViewColumn ();
        type_col.title = "Type";
        type_col.pack_start (type_cell, true);
        type_col.add_attribute (type_cell, "text", 1);
        type_col.set_resizable (true);
        type_col.set_min_width (200);
        dir_tree.append_column (type_col);

        dir_scroll = new Gtk.ScrolledWindow (null, null);
        dir_scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        dir_scroll.add (dir_tree);
        content_stack.add_named (dir_scroll, "directory");

        // -- Info / fallback view
        info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        info_box.halign = Gtk.Align.CENTER;
        info_box.valign = Gtk.Align.CENTER;
        info_box.margin = 48;

        Gtk.Image icon_view = new Gtk.Image.from_icon_name (
            "dialog-information", Gtk.IconSize.DIALOG
        );
        icon_view.set_pixel_size (96);
        icon_view.valign = Gtk.Align.CENTER;
        info_box.pack_start (icon_view, false, false, 0);

        info_label = new Gtk.Label ("");
        info_label.use_markup = true;
        info_label.halign = Gtk.Align.CENTER;
        info_label.valign = Gtk.Align.START;
        info_label.wrap = true;
        info_label.max_width_chars = 80;
        info_label.get_style_context ().add_class ("quicklook-info");
        info_box.pack_start (info_label, false, false, 0);

        content_stack.add_named (info_box, "info");

        // Add loading and content to main stack area
        Gtk.Overlay overlay = new Gtk.Overlay ();
        overlay.add (content_stack);

        Gtk.Box loading_container = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        loading_container.halign = Gtk.Align.CENTER;
        loading_container.valign = Gtk.Align.CENTER;
        loading_container.vexpand = true;
        loading_container.hexpand = true;
        loading_container.pack_start (loading_box, false, false, 0);
        overlay.add_overlay (loading_container);

        main_box.pack_start (overlay, true, true, 0);
    }

    private void setup_styles () {
        // Apply dark background to the window
        string css = """
            .quicklook-text {
                font-family: "Monospace";
                font-size: 10pt;
                background-color: #1e1e1e;
                color: #d4d4d4;
            }
            .quicklook-info {
                font-size: 12pt;
                color: #cccccc;
            }
            .quicklook-loading {
                font-size: 14pt;
                color: #aaaaaa;
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
            warning ("Failed to load QuickLook CSS: %s", e.message);
        }
    }

    private void connect_events () {
        // Key events
        key_press_event.connect ((event) => {
            if (event.keyval == Gdk.Key.Escape || event.keyval == Gdk.Key.space) {
                close_preview ();
                return true;
            }
            if (event.keyval == Gdk.Key.Right || event.keyval == Gdk.Key.Down) {
                next_file ();
                return true;
            }
            if (event.keyval == Gdk.Key.Left || event.keyval == Gdk.Key.Up) {
                prev_file ();
                return true;
            }
            return false;
        });

        // Close on button press
        button_press_event.connect ((event) => {
            close_preview ();
            return true;
        });

        // Close on destroy
        destroy.connect (() => {
            cleanup_cache ();
        });
    }

    public void show_file (string path) {
        if (path == null || path == "") return;

        // Cancel any previous load
        if (load_cancellable != null) {
            load_cancellable.cancel ();
        }
        load_cancellable = new Cancellable ();

        current_path = path;

        // Build sibling file list for navigation
        build_sibling_list (path);

        // Start loading
        show_loading (true);
        present ();

        // Detect content type and load async
        load_file_async.begin (path, load_cancellable, (obj, res) => {
            try {
                load_file_async.end (res);
            } catch (Error e) {
                if (!(e is IOError.CANCELLED)) {
                    show_info_fallback (path, e.message);
                }
            }
            show_loading (false);
        });
    }

    private void build_sibling_list (string path) {
        File file = File.new_for_path (path);
        File parent = file.get_parent ();
        if (parent == null) {
            sibling_files = new string[] { path };
            current_index = 0;
            return;
        }

        try {
            FileEnumerator enumerator = parent.enumerate_children (
                "standard::name,standard::type",
                FileQueryInfoFlags.NONE,
                null
            );

            string[] files = {};
            int idx = 0;
            FileInfo? child_info;
            while ((child_info = enumerator.next_file (null)) != null) {
                string child_name = child_info.get_name ();
                string child_path = parent.get_path () + "/" + child_name;
                files += child_path;
                if (child_path == path) {
                    current_index = idx;
                }
                idx++;
            }

            if (files.length == 0) {
                sibling_files = new string[] { path };
                current_index = 0;
            } else {
                sibling_files = files;
            }
        } catch (Error e) {
            sibling_files = new string[] { path };
            current_index = 0;
        }
    }

    public void next_file () {
        if (sibling_files.length == 0) return;
        current_index = (current_index + 1) % sibling_files.length;
        show_file (sibling_files[current_index]);
    }

    public void prev_file () {
        if (sibling_files.length == 0) return;
        current_index--;
        if (current_index < 0) {
            current_index = sibling_files.length - 1;
        }
        show_file (sibling_files[current_index]);
    }

    public void close_preview () {
        hide ();
        if (load_cancellable != null) {
            load_cancellable.cancel ();
        }
    }

    private void show_loading (bool show) {
        if (show) {
            spinner.start ();
            loading_box.show_all ();
            content_stack.set_sensitive (false);
        } else {
            spinner.stop ();
            loading_box.hide ();
            content_stack.set_sensitive (true);
        }
    }

    private async void load_file_async (string path, Cancellable? cancellable) throws Error {
        File file = File.new_for_path (path);
        FileInfo? info = null;

        try {
            info = yield file.query_info_async (
                "standard::content-type,standard::size,standard::display-name," +
                "time::modified,standard::icon,standard::type",
                FileQueryInfoFlags.NONE,
                Priority.DEFAULT,
                cancellable
            );
        } catch (Error e) {
            // Fallback: try to detect by extension
        }

        // Check if cancelled
        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Loading cancelled");
        }

        string mime_type = "application/octet-stream";
        if (info != null) {
            mime_type = info.get_content_type () ?? mime_type;
        } else {
            mime_type = detect_mime_from_extension (path);
        }

        // Check if directory
        if (info != null && info.get_file_type () == FileType.DIRECTORY) {
            show_directory (path);
            return;
        }

        // Route by mime type
        if (is_image_mime (mime_type)) {
            yield load_image_async (path, mime_type, cancellable);
        } else if (is_text_mime (mime_type) || is_text_extension (path)) {
            yield load_text_async (path, cancellable);
        } else if (mime_type == "application/pdf") {
            show_pdf_info (path, info);
        } else if (mime_type.has_prefix ("video/") || mime_type.has_prefix ("audio/")) {
            show_media_info (path, info, mime_type);
        } else {
            show_info_fallback (path, null, info);
        }
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
        if (lower.has_suffix (".mp4") || lower.has_suffix (".avi") || lower.has_suffix (".mkv")) return "video/mp4";
        if (lower.has_suffix (".mp3") || lower.has_suffix (".ogg") || lower.has_suffix (".wav")) return "audio/mpeg";
        return "application/octet-stream";
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

    private async void load_image_async (string path, string mime_type, Cancellable? cancellable) throws Error {
        // Check cache first
        if (pixbuf_cache.contains (path)) {
            Gdk.Pixbuf cached = pixbuf_cache.lookup (path);
            show_image (cached);
            return;
        }

        Gdk.Pixbuf pixbuf = null;

        if (mime_type == "image/svg+xml") {
            // For SVG: load at a reasonable size
            try {
                int target_w = (int) (Gdk.Screen.get_default ().get_width () * 0.65);
                int target_h = (int) (Gdk.Screen.get_default ().get_height () * 0.65);
                pixbuf = new Gdk.Pixbuf.from_file_at_size (path, target_w, target_h);
            } catch (Error e) {
                throw e;
            }
        } else {
            // Load image async through stream
            try {
                File file = File.new_for_path (path);
                FileInputStream stream = yield file.read_async (Priority.DEFAULT, cancellable);

                // Load pixbuf from stream
                var loader = new Gdk.PixbufLoader ();
                loader.set_size ((int)(Gdk.Screen.get_default ().get_width () * 0.65),
                                 (int)(Gdk.Screen.get_default ().get_height () * 0.65));

                uint8[] buffer = new uint8[65536];
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
                // Fallback to synchronous load
                try {
                    int target_w = (int) (Gdk.Screen.get_default ().get_width () * 0.65);
                    int target_h = (int) (Gdk.Screen.get_default ().get_height () * 0.65);
                    pixbuf = new Gdk.Pixbuf.from_file_at_size (path, target_w, target_h);
                } catch (Error e2) {
                    throw e2;
                }
            }
        }

        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Loading cancelled");
        }

        if (pixbuf != null) {
            // Scale to fit if needed
            Gdk.Pixbuf scaled = scale_pixbuf_to_fit (pixbuf);
            cache_pixbuf (path, scaled);
            show_image (scaled);
        } else {
            show_info_fallback (path, "Could not load image");
        }
    }

    private Gdk.Pixbuf scale_pixbuf_to_fit (Gdk.Pixbuf pixbuf) {
        Gdk.Screen screen = Gdk.Screen.get_default ();
        int max_w = (int) (screen.get_width () * 0.65);
        int max_h = (int) (screen.get_height () * 0.65);

        int w = pixbuf.get_width ();
        int h = pixbuf.get_height ();

        if (w <= max_w && h <= max_h) {
            return pixbuf;
        }

        double ratio = double.min ((double) max_w / w, (double) max_h / h);
        int new_w = (int) (w * ratio);
        int new_h = (int) (h * ratio);

        Gdk.Pixbuf scaled = pixbuf.scale_simple (new_w, new_h, Gdk.InterpType.BILINEAR);
        return scaled ?? pixbuf;
    }

    private void show_image (Gdk.Pixbuf pixbuf) {
        image_view.set_from_pixbuf (pixbuf);
        content_stack.set_visible_child_name ("image");
    }

    private async void load_text_async (string path, Cancellable? cancellable) throws Error {
        string contents;
        try {
            File file = File.new_for_path (path);
            uint8[] raw_contents;
            yield file.load_contents_async (cancellable, out raw_contents, null);

            // Convert to string (limited to ~100KB for quick preview)
            const int MAX_TEXT_SIZE = 100 * 1024;
            if (raw_contents.length > MAX_TEXT_SIZE) {
                contents = (string) raw_contents[0:MAX_TEXT_SIZE];
                contents += "\n\n[... File truncated (too large for preview) ...]";
            } else {
                contents = (string) raw_contents;
            }
        } catch (Error e) {
            throw e;
        }

        if (cancellable != null && cancellable.is_cancelled ()) {
            throw new IOError.CANCELLED ("Loading cancelled");
        }

        // Apply basic syntax highlighting
        Gtk.TextBuffer buffer;
        if (should_highlight (path)) {
            buffer = create_highlighted_buffer (contents, path);
        } else {
            buffer = new Gtk.TextBuffer (null);
            buffer.text = contents;
        }

        // Add line numbers as margin
        add_line_numbers (buffer);

        text_view.set_buffer (buffer);
        content_stack.set_visible_child_name ("text");
    }

    private bool should_highlight (string path) {
        string lower = path.ascii_down ();
        return lower.has_suffix (".vala") || lower.has_suffix (".vapi") ||
               lower.has_suffix (".c") || lower.has_suffix (".h") ||
               lower.has_suffix (".js") || lower.has_suffix (".py") ||
               lower.has_suffix (".json") || lower.has_suffix (".xml");
    }

    private Gtk.TextBuffer create_highlighted_buffer (string contents, string path) {
        Gtk.TextBuffer buffer = new Gtk.TextBuffer (null);

        // Create tags
        Gtk.TextTagTable tags = buffer.get_tag_table ();

        Gtk.TextTag comment_tag = new Gtk.TextTag ("comment");
        comment_tag.foreground = COMMENT_COLOR;
        tags.add (comment_tag);

        Gtk.TextTag keyword_tag = new Gtk.TextTag ("keyword");
        keyword_tag.foreground = KEYWORD_COLOR;
        tags.add (keyword_tag);

        Gtk.TextTag string_tag = new Gtk.TextTag ("string");
        string_tag.foreground = STRING_COLOR;
        tags.add (string_tag);

        // For now, insert text and apply basic highlighting
        buffer.text = contents;

        // Apply very basic syntax highlighting
        apply_basic_highlighting (buffer, contents, path);

        return buffer;
    }

    private void apply_basic_highlighting (Gtk.TextBuffer buffer, string contents, string path) {
        // Simple line-by-line comment detection

        string[] lines = contents.split ("\n");
        int pos = 0;

        foreach (string line in lines) {
            // Highlight comments (// and #)
            int comment_pos = line.index_of ("//");
            if (comment_pos < 0) {
                comment_pos = line.index_of ("#");
            }

            if (comment_pos >= 0) {
                Gtk.TextIter cs, ce;
                buffer.get_iter_at_offset (out cs, pos + comment_pos);
                buffer.get_iter_at_offset (out ce, pos + line.length);
                buffer.apply_tag_by_name ("comment", cs, ce);
            }

            // Highlight strings (simplified)
            int str_start = -1;
            for (int i = 0; i < line.length; i++) {
                if (line[i] == '"' && (i == 0 || line[i-1] != '\\')) {
                    if (str_start < 0) {
                        str_start = i;
                    } else {
                        Gtk.TextIter ss, se;
                        buffer.get_iter_at_offset (out ss, pos + str_start);
                        buffer.get_iter_at_offset (out se, pos + i + 1);
                        buffer.apply_tag_by_name ("string", ss, se);
                        str_start = -1;
                    }
                }
            }

            pos += line.length + 1; // +1 for newline
        }
    }

    private void add_line_numbers (Gtk.TextBuffer buffer) {
        // Store line count for display
        string text = buffer.text;
        int line_count = 1;
        for (int i = 0; i < text.length; i++) {
            if (text[i] == '\n') line_count++;
        }

        // Add line number info as tooltip on text view
        text_view.set_tooltip_text ("%d lines".printf (line_count));
    }

    private void show_directory (string path) {
        dir_list.clear ();

        File dir = File.new_for_path (path);
        int count = 0;

        try {
            FileEnumerator enumerator = dir.enumerate_children (
                "standard::name,standard::content-type,standard::display-name," +
                "standard::icon,standard::type,standard::size",
                FileQueryInfoFlags.NONE,
                null
            );

            FileInfo? child_info;
            while ((child_info = enumerator.next_file (null)) != null) {
                string display_name = child_info.get_display_name ();
                string child_mime = child_info.get_content_type () ?? "unknown";
                string file_type = child_info.get_file_type () == FileType.DIRECTORY ? "Directory" : child_mime;

                TreeIter iter;
                dir_list.append (out iter);
                dir_list.set (iter, 0, display_name, 1, file_type);
                count++;
            }
        } catch (Error e) {
            warning ("Failed to enumerate directory: %s", e.message);
        }

        // Update info label with directory count
        show_info_fallback (path, "%d items".printf (count));

        // But also show directory listing
        content_stack.set_visible_child_name ("directory");
    }

    private void show_pdf_info (string path, FileInfo? info) {
        string name = info != null ? info.get_display_name () : Path.get_basename (path);
        int64 size = info != null ? info.get_size () : 0;

        // Try to load first page via pixbuf (fallback to poppler message)
        try {
            Gdk.Pixbuf pdf_pixbuf = new Gdk.Pixbuf.from_file_at_size (path, 800, 1000);
            if (pdf_pixbuf != null) {
                Gdk.Pixbuf scaled = scale_pixbuf_to_fit (pdf_pixbuf);
                cache_pixbuf (path, scaled);
                show_image (scaled);
                return;
            }
        } catch (Error e) {
            // Poppler not available or loading failed
        }

        string markup = """
            <b>%s</b>
            \n<span size="small">PDF Document</span>
            \n<span size="small">Size: %s</span>
            \n<span size="small" color="#888888">(PDF preview requires Poppler)</span>
        """.printf (
            Markup.escape_text (name),
            Markup.escape_text (format_size (size))
        );

        info_label.set_markup (markup);

        // Update icon for PDF
        foreach (var child in info_box.get_children ()) {
            if (child is Gtk.Image) {
                ((Gtk.Image) child).set_from_icon_name ("x-office-document", Gtk.IconSize.DIALOG);
                ((Gtk.Image) child).set_pixel_size (96);
                break;
            }
        }

        content_stack.set_visible_child_name ("info");
    }

    private void show_media_info (string path, FileInfo? info, string mime_type) {
        string name = info != null ? info.get_display_name () : Path.get_basename (path);
        int64 size = info != null ? info.get_size () : 0;

        string media_type = mime_type.has_prefix ("video/") ? "Video" : "Audio";
        string icon_name = mime_type.has_prefix ("video/") ? "video-x-generic" : "audio-x-generic";

        string markup = """
            <b>%s</b>
            \n<span size="large">%s File</span>
            \n<span size="small">MIME: %s</span>
            \n<span size="small">Size: %s</span>
        """.printf (
            Markup.escape_text (name),
            media_type,
            Markup.escape_text (mime_type),
            Markup.escape_text (format_size (size))
        );

        info_label.set_markup (markup);

        // Update icon
        foreach (var child in info_box.get_children ()) {
            if (child is Gtk.Image) {
                ((Gtk.Image) child).set_from_icon_name (icon_name, Gtk.IconSize.DIALOG);
                ((Gtk.Image) child).set_pixel_size (96);
                break;
            }
        }

        content_stack.set_visible_child_name ("info");
    }

    private void show_info_fallback (string path, string? error_msg, FileInfo? info = null) {
        string name;
        int64 size = 0;
        string mime = "unknown";
        DateTime? mtime = null;

        if (info != null) {
            name = info.get_display_name ();
            size = info.get_size ();
            mime = info.get_content_type () ?? "unknown";
            try {
                var mod_time = info.get_modification_date_time();
                if (mod_time != null) {
                    mtime = mod_time;
                }
            } catch (Error e) {}
        } else {
            name = Path.get_basename (path);
            File file = File.new_for_path (path);
            try {
                FileInfo fi = file.query_info (
                    "standard::size,standard::content-type,time::modified",
                    FileQueryInfoFlags.NONE, null
                );
                size = fi.get_size ();
                mime = fi.get_content_type () ?? "unknown";

            } catch (Error e) {
                // Use defaults
            }
        }

        string mtime_str = mtime != null ? mtime.format ("%Y-%m-%d %H:%M:%S") : "unknown";

        string markup = """
            <b>%s</b>
            \n<span size="small">MIME: %s</span>
            \n<span size="small">Size: %s</span>
            \n<span size="small">Modified: %s</span>
        """.printf (
            Markup.escape_text (name),
            Markup.escape_text (mime),
            Markup.escape_text (format_size (size)),
            Markup.escape_text (mtime_str)
        );

        if (error_msg != null) {
            markup += "\n<span size='small' color='#cc4444'>%s</span>".printf (
                Markup.escape_text (error_msg)
            );
        }

        info_label.set_markup (markup);

        // Reset icon
        foreach (var child in info_box.get_children ()) {
            if (child is Gtk.Image) {
                ((Gtk.Image) child).set_from_icon_name ("dialog-information", Gtk.IconSize.DIALOG);
                ((Gtk.Image) child).set_pixel_size (96);
                break;
            }
        }

        content_stack.set_visible_child_name ("info");
    }

    private void cache_pixbuf (string path, Gdk.Pixbuf pixbuf) {
        // Enforce cache size limit
        if (pixbuf_cache.size () >= CACHE_MAX_SIZE) {
            // Remove oldest entries (simple approach: clear half the cache)
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

    private void cleanup_cache () {
        pixbuf_cache.remove_all ();
    }

    private string format_size (int64 size) {
        if (size < 1024) return "%lld B".printf (size);
        if (size < 1024 * 1024) return "%.1f KB".printf (size / 1024.0);
        if (size < 1024 * 1024 * 1024) return "%.1f MB".printf (size / (1024.0 * 1024.0));
        return "%.1f GB".printf (size / (1024.0 * 1024.0 * 1024.0));
    }
}
}
