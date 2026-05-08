/*
 * context_menu.vala
 * TileFM -- Context Menu for files, selections, and background
 */

using Gtk;
using Gdk;
using GLib;

namespace TileFm {
    public class ContextMenu : Gtk.Menu {
        public signal void open_file_request(string path);
        public signal void open_with_request(string path, AppInfo app);
        public signal void cut_request(string[] paths);
        public signal void copy_request(string[] paths);
        public signal void paste_request(string target_dir);
        public signal void rename_request(string path);
        public signal void trash_request(string[] paths);
        public signal void delete_request(string[] paths);
        public signal void copy_path_request(string path);
        public signal void open_terminal_request(string dir);
        public signal void properties_request(string path);
        public signal void bulk_rename_request(string[] paths);

        private FileManager file_manager;
        private ClipboardManager clipboard;
        private CustomActionsManager custom_actions_mgr;

        private string? current_single_path = null;
        private string[] current_paths = {};
        private bool is_background = false;

        public ContextMenu(FileManager fm, ClipboardManager cb) {
        file_manager = fm;
        clipboard = cb;
        custom_actions_mgr = new CustomActionsManager();
    }

    // -- Public API -----------------------------------------------

    public void show_for_file(string path, Gdk.EventButton event) {
        is_background = false;
        current_single_path = path;
        current_paths = new string[] { path };
        build_menu();
        popup_at_pointer(event);
    }

    public void show_for_selection(string[] paths, Gdk.EventButton event) {
        is_background = false;
        current_single_path = null;
        current_paths = paths;
        build_menu();
        popup_at_pointer(event);
    }

    public void show_for_background(string dir, Gdk.EventButton event) {
        is_background = true;
        current_single_path = null;
        current_paths = {};
        build_background_menu(dir);
        popup_at_pointer(event);
    }

    // -- Menu Builders --------------------------------------------

    private void build_menu() {
        foreach (var child in get_children()) {
            child.destroy();
        }

        if (current_paths.length == 0)
            return;

        string path = current_paths[0];
        bool single = current_paths.length == 1;
        bool is_dir = FileUtils.test(path, FileTest.IS_DIR);
        bool is_archive_file = single && ArchivePlugin.is_archive(path);

        // -- Open --
        if (single && !is_archive_file) {
            var open_item = new Gtk.MenuItem.with_label("Open");
            open_item.activate.connect(() => {
                open_file_request(path);
            });
            add(open_item);

            // -- Open With submenu --
            add_open_with_submenu(path);
        }

        // -- Extract (if archive) --
        if (is_archive_file) {
            var extract_here_item = new Gtk.MenuItem.with_label("Extract Here");
            extract_here_item.activate.connect(() => {
                ArchivePlugin.extract_here.begin(path, (obj, res) => {
                    ArchivePlugin.extract_here.end(res);
                });
            });
            add(extract_here_item);

            var extract_to_item = new Gtk.MenuItem.with_label("Extract to...");
            extract_to_item.activate.connect(() => {
                // Parent window will be set by the caller
                Gtk.Window? parent = get_toplevel() as Gtk.Window;
                ArchivePlugin.extract_with_dialog.begin(path, parent, (obj, res) => {
                    ArchivePlugin.extract_with_dialog.end(res);
                });
            });
            add(extract_to_item);

            add(new Gtk.SeparatorMenuItem());
        }

        // -- Separator --
        if (single && !is_archive_file) {
            add(new Gtk.SeparatorMenuItem());
        }

        // -- Cut --
        var cut_item = new Gtk.MenuItem.with_mnemonic("Cu_t");
        cut_item.activate.connect(() => {
            cut_request(current_paths);
        });
        add(cut_item);

        // -- Copy --
        var copy_item = new Gtk.MenuItem.with_mnemonic("_Copy");
        copy_item.activate.connect(() => {
            copy_request(current_paths);
        });
        add(copy_item);

        // -- Paste --
        var paste_item = new Gtk.MenuItem.with_mnemonic("_Paste");
        paste_item.sensitive = !clipboard.is_empty();
        paste_item.activate.connect(() => {
            string target_dir = is_dir ? path : (File.new_for_path(path).get_parent()?.get_path() ?? ".");
            paste_request(target_dir);
        });
        add(paste_item);

        add(new Gtk.SeparatorMenuItem());

        // -- Rename -- (single only)
        if (single) {
            var rename_item = new Gtk.MenuItem.with_mnemonic("_Rename...");
            rename_item.activate.connect(() => {
                rename_request(path);
            });
            add(rename_item);
        }

        // -- Bulk Rename -- (multiple files selected)
        if (!single) {
            var bulk_rename_item = new Gtk.MenuItem.with_label("Bulk Rename...");
            bulk_rename_item.activate.connect(() => {
                bulk_rename_request(current_paths);
            });
            add(bulk_rename_item);
            add(new Gtk.SeparatorMenuItem());
        }

        // -- Compress / Create Archive --
        add_compress_submenu(current_paths);

        add(new Gtk.SeparatorMenuItem());

        // -- Move to Trash --
        var trash_item = new Gtk.MenuItem.with_label("Move to Trash");
        trash_item.activate.connect(() => {
            trash_request(current_paths);
        });
        add(trash_item);

        // -- Delete --
        var delete_item = new Gtk.MenuItem.with_label("Delete (Shift+Del)");
        delete_item.activate.connect(() => {
            delete_request(current_paths);
        });
        add(delete_item);

        add(new Gtk.SeparatorMenuItem());

        // -- Copy Path -- (single only)
        if (single) {
            var copy_path_item = new Gtk.MenuItem.with_label("Copy Path");
            copy_path_item.activate.connect(() => {
                copy_path_to_system_clipboard(path);
                copy_path_request(path);
            });
            add(copy_path_item);
        }

        // -- Open in Terminal -- (single only)
        if (single) {
            var term_item = new Gtk.MenuItem.with_label("Open in Terminal");
            term_item.activate.connect(() => {
                string dir = is_dir ? path : (File.new_for_path(path).get_parent()?.get_path() ?? ".");
                open_terminal_request(dir);
                open_terminal(dir);
            });
            add(term_item);
        }

        // -- Custom Actions --
        if (single) {
            CustomAction[] custom_actions;
            if (is_dir) {
                custom_actions = custom_actions_mgr.get_actions_for_directory(path);
            } else {
                custom_actions = custom_actions_mgr.get_actions_for_file(path);
            }
            if (custom_actions.length > 0) {
                add(new Gtk.SeparatorMenuItem());
                var ca_menu = new Gtk.MenuItem.with_label("Custom Actions");
                var ca_submenu = new Gtk.Menu();
                foreach (var action in custom_actions) {
                    var ca_item = new Gtk.MenuItem.with_label(action.name);
                    ca_item.activate.connect((a) => {
                        custom_actions_mgr.execute_action(action, path);
                    });
                    ca_submenu.add(ca_item);
                }
                ca_menu.set_submenu(ca_submenu);
                add(ca_menu);
            }
        }

        add(new Gtk.SeparatorMenuItem());

        // -- Properties -- (single only)
        if (single) {
            var props_item = new Gtk.MenuItem.with_mnemonic("_Properties");
            props_item.activate.connect(() => {
                show_properties_dialog(path);
                properties_request(path);
            });
            add(props_item);
        }

        show_all();
    }

    private void build_background_menu(string dir) {
        foreach (var child in get_children()) {
            child.destroy();
        }

        // -- Create New Folder --
        var new_folder_item = new Gtk.MenuItem.with_label("Create New Folder");
        new_folder_item.activate.connect(() => {
            create_new_folder(dir);
        });
        add(new_folder_item);

        add(new Gtk.SeparatorMenuItem());

        // -- Paste --
        var paste_item = new Gtk.MenuItem.with_mnemonic("_Paste");
        paste_item.sensitive = !clipboard.is_empty();
        paste_item.activate.connect(() => {
            paste_request(dir);
        });
        add(paste_item);

        add(new Gtk.SeparatorMenuItem());

        // -- Open in Terminal --
        var term_item = new Gtk.MenuItem.with_label("Open in Terminal");
        term_item.activate.connect(() => {
            open_terminal_request(dir);
            open_terminal(dir);
        });
        add(term_item);

        // -- Custom Actions for directory --
        CustomAction[] custom_actions = custom_actions_mgr.get_actions_for_directory(dir);
        if (custom_actions.length > 0) {
            add(new Gtk.SeparatorMenuItem());
            var ca_menu = new Gtk.MenuItem.with_label("Custom Actions");
            var ca_submenu = new Gtk.Menu();
            foreach (var action in custom_actions) {
                var ca_item = new Gtk.MenuItem.with_label(action.name);
                ca_item.activate.connect(() => {
                    custom_actions_mgr.execute_action(action, dir);
                });
                ca_submenu.add(ca_item);
            }
            ca_menu.set_submenu(ca_submenu);
            add(ca_menu);
        }

        show_all();
    }

    // -- Compress Submenu ---------------------------------------

    private void add_compress_submenu(string[] paths) {
        var compress_menu = new Gtk.MenuItem.with_label("Compress...");
        var submenu = new Gtk.Menu();

        string[] formats = ArchivePlugin.get_supported_formats();

        foreach (var ext in formats) {
            string? desc = ArchivePlugin.get_format_description(ext);
            string label = desc != null ? "%s (%s)".printf(desc, ext) : ext;

            var fmt_item = new Gtk.MenuItem.with_label(label);
            fmt_item.activate.connect(() => {
                Gtk.Window? parent = get_toplevel() as Gtk.Window;
                ArchivePlugin.create_with_dialog.begin(paths, ext, parent, (obj, res) => {
                    ArchivePlugin.create_with_dialog.end(res);
                });
            });
            submenu.add(fmt_item);
        }

        compress_menu.set_submenu(submenu);
        add(compress_menu);
    }

    // -- Open With Submenu --------------------------------------

    private void add_open_with_submenu(string path) {
        string mime_type = file_manager.get_mime_type(path);
        if (mime_type == null || mime_type == "")
            return;

        var open_with_menu = new Gtk.MenuItem.with_label("Open With");
        var submenu = new Gtk.Menu();

        var apps = AppInfo.get_all_for_type(mime_type);
        if (apps != null) {
            foreach (AppInfo app in apps) {
                string app_name = app.get_display_name() ?? app.get_name() ?? "Unknown";
                var app_item = new Gtk.MenuItem.with_label(app_name);
                app_item.activate.connect(() => {
                    open_with_request(path, app);
                    try {
                        var _files = new List<File>(); _files.append(File.new_for_path(path)); app.launch(_files, null);
                    } catch (Error e) {
                        warning("Failed to open '%s' with '%s': %s", path, app_name, e.message);
                    }
                });
                submenu.add(app_item);
            }
        }

        // -- Other Application... --
        submenu.add(new Gtk.SeparatorMenuItem());
        var other_app_item = new Gtk.MenuItem.with_label("Other Application...");
        other_app_item.activate.connect(() => {
            show_open_with_dialog(path, mime_type);
        });
        submenu.add(other_app_item);

        open_with_menu.set_submenu(submenu);
        add(open_with_menu);
    }

    private void show_open_with_dialog(string path, string mime_type) {
        var dialog = new Gtk.AppChooserDialog(
            null,
            Gtk.DialogFlags.MODAL,
            File.new_for_path(path)
        );
        dialog.set_title("Open With");

        int response = dialog.run();
        if (response == Gtk.ResponseType.OK) {
            AppInfo app = dialog.get_app_info();
            if (app != null) {
                open_with_request(path, app);
                try {
                    var files = new List<File>();
                    files.append(File.new_for_path(path));
                    app.launch(files, null);
                } catch (Error e) {
                    warning("Failed to open: %s", e.message);
                }
            }
        }
        dialog.destroy();
    }

    // -- Properties Dialog --------------------------------------

    private void show_properties_dialog(string path) {
        var dialog = new Gtk.Dialog.with_buttons(
            "Properties",
            null,
            Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
            "_Close",
            Gtk.ResponseType.CLOSE,
            null
        );
        dialog.set_default_size(400, 300);

        var content = dialog.get_content_area();
        content.margin = 12;
        content.spacing = 8;

        var grid = new Gtk.Grid();
        grid.row_spacing = 6;
        grid.column_spacing = 12;

        FileInfo? info = file_manager.get_file_info(path);
        if (info == null) {
            var error_label = new Gtk.Label("Failed to read file information.");
            content.add(error_label);
        } else {
            int row = 0;

            // Name
            add_prop_row(grid, ref row, "Name:", info.get_name());

            // Type
            string content_type = info.get_content_type() ?? "Unknown";
            string desc = ContentType.get_description(content_type) ?? content_type;
            add_prop_row(grid, ref row, "Type:", desc);

            // Size
            int64 size = info.get_size();
            add_prop_row(grid, ref row, "Size:", format_size(size));

            // Modified
            try {
                var mod_time = info.get_modification_date_time ();
                if (mod_time != null) {
                    add_prop_row(grid, ref row, "Modified:", mod_time.format("%Y-%m-%d %H:%M:%S"));
                }
            } catch (Error e) {}

            // Accessed
            if (info.has_attribute("time::modified")) {
                uint64 atime = info.get_attribute_uint64("time::modified");
                var dt = new DateTime.from_unix_local((int64) atime);
                add_prop_row(grid, ref row, "Accessed:", dt.format("%Y-%m-%d %H:%M:%S"));
            }

            // Location
            var file = File.new_for_path(path);
            string? parent = file.get_parent()?.get_path();
            add_prop_row(grid, ref row, "Location:", parent ?? "Unknown");

            // Permissions
            add(new Gtk.SeparatorMenuItem());
            var perm_label = new Gtk.Label("");
            perm_label.use_markup = true;
            perm_label.halign = Gtk.Align.START;
            perm_label.set_markup("<b>Permissions</b>");
            grid.attach(perm_label, 0, row, 2, 1);
            row++;

            uint32 mode = info.get_attribute_uint32("unix::mode");
            add_prop_row(grid, ref row, "Owner:", format_permissions(mode, 6));
            add_prop_row(grid, ref row, "Group:", format_permissions(mode, 3));
            add_prop_row(grid, ref row, "Other:", format_permissions(mode, 0));
        }

        var scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.add_with_viewport(grid);
        scroll.expand = true;
        content.add(scroll);

        dialog.show_all();
        dialog.response.connect((response) => {
            dialog.destroy();
        });
    }

    private void add_prop_row(Gtk.Grid grid, ref int row, string label_text, string value_text) {
        var label = new Gtk.Label(label_text);
        label.halign = Gtk.Align.END;
        label.hexpand = false;

        var value = new Gtk.Label(value_text);
        value.halign = Gtk.Align.START;
        value.hexpand = true;
        value.selectable = true;
        value.xalign = 0;

        grid.attach(label, 0, row, 1, 1);
        grid.attach(value, 1, row, 1, 1);
        row++;
    }

    private string format_size(int64 size) {
        if (size < 1024)
            return "%lld bytes".printf(size);
        if (size < 1024 * 1024)
            return "%.1f KB".printf(size / 1024.0);
        if (size < 1024 * 1024 * 1024)
            return "%.1f MB".printf(size / (1024.0 * 1024.0));
        return "%.1f GB".printf(size / (1024.0 * 1024.0 * 1024.0));
    }

    private string format_permissions(uint32 mode, int shift) {
        int r = ((int)(mode >> (shift + 2))) & 1;
        int w = ((int)(mode >> (shift + 1))) & 1;
        int x = ((int)(mode >> shift)) & 1;
        return "%s%s%s".printf(
            r == 1 ? "r" : "-",
            w == 1 ? "w" : "-",
            x == 1 ? "x" : "-"
        );
    }

    // -- Helpers ------------------------------------------------

    private void copy_path_to_system_clipboard(string path) {
        var display = Gdk.Display.get_default();
        if (display == null)
            return;

        Gtk.Clipboard clipboard_default = Gtk.Clipboard.get_default(display);
        if (clipboard_default != null) {
            clipboard_default.set_text(path, -1);
            clipboard_default.store();
        }
    }

    private void open_terminal(string dir) {
        string[] terminals = {
            "x-terminal-emulator",
            "exo-open --launch TerminalEmulator",
            "gnome-terminal",
            "xfce4-terminal",
            "konsole",
            "lxterminal",
            "alacritty",
            "kitty",
            "xterm"
        };

        foreach (var term in terminals) {
            string[] argv;
            try {
                if (term == "x-terminal-emulator" || term == "exo-open --launch TerminalEmulator") {
                    Shell.parse_argv(term, out argv);
                } else if (term.has_prefix("gnome-terminal") || term.has_prefix("xfce4-terminal")) {
                    Shell.parse_argv("%s --working-directory=%s".printf(term, Shell.quote(dir)), out argv);
                } else {
                    Shell.parse_argv(term, out argv);
                }

                Process.spawn_async(
                    dir,
                    argv,
                    null,
                    SpawnFlags.SEARCH_PATH,
                    null,
                    null
                );
                return;
            } catch (Error e) {
                continue;
            }
        }

        warning("Could not find a terminal emulator to open in '%s'", dir);
    }

    private async void create_new_folder(string parent_dir) {
        var dialog = new Gtk.Dialog.with_buttons(
            "Create New Folder",
            null,
            Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
            "_Cancel",
            Gtk.ResponseType.CANCEL,
            "_Create",
            Gtk.ResponseType.OK,
            null
        );
        dialog.set_default_size(300, 100);

        var content = dialog.get_content_area();
        content.margin = 12;

        var entry = new Gtk.Entry();
        entry.set_text("New Folder");
        entry.set_activates_default(true);
        entry.select_region(0, -1);
        content.add(entry);

        dialog.show_all();

        int response = dialog.run();
        string name = entry.get_text().strip();
        dialog.destroy();

        if (response == Gtk.ResponseType.OK && name != "") {
            string new_path = Path.build_filename(parent_dir, name);
            try {
                var dir = File.new_for_path(new_path);
                yield dir.make_directory_async(Priority.DEFAULT, null);
            } catch (Error e) {
                warning("Failed to create folder '%s': %s", new_path, e.message);
            }
        }
    }
}

}
