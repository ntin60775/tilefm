/* TileFM - Tile
 * Single tile: pathbar + typeahead search + file view (with DnD) + preview panel
 * + ContextMenu + Undo/Redo + Trash + Clipboard + CustomActions
 */

namespace TileFm {
    public enum ViewMode {
        ICON,
        LIST,
        DETAILS
    }

    public class Tile : Gtk.Box {
        // Properties
        public string current_path { get; private set; }
        public ViewMode view_mode { get; set; default = ViewMode.ICON; }
        public bool is_active { get; set; default = false; }

        // Signals
        public signal void path_changed (string new_path);
        public signal void navigate_request (string path);
        public signal void close_requested ();
        public signal void file_activated (string path);
        public signal void selection_info_changed (int selected_count, int64 total_size);

        // Private — UI
        private FileManager file_manager;
        private BreadcrumbPathBar pathbar;
        private Gtk.ScrolledWindow scrolled;
        private FileView current_view;
        private Gtk.Button close_btn;
        private TypeaheadSearch search_widget;
        private PreviewPanel preview_panel;
        private Gtk.Paned main_paned;
        private bool preview_visible;

        // Private — managers (ContextMenu + Undo/Redo + Trash + Clipboard + CustomActions)
        private ContextMenu context_menu;
        private UndoManager undo_manager;
        private ClipboardManager clipboard_mgr;
        private CustomActionsManager custom_actions_mgr;

        // File storage for filtering
        private FileInfo[] all_files;
        private FileInfo[] filtered_files;

        // Drag and Drop
        private const Gtk.TargetEntry[] drag_targets = {
            { "text/uri-list", 0, 0 }
        };
        private const Gtk.TargetEntry[] source_targets = {
            { "text/uri-list", 0, 0 }
        };

        // ── Constructor ───────────────────────────────────────────

        public Tile (FileManager fm, string? path = null) {
            Object (
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0
            );

            file_manager = fm;
            current_path = path ?? Environment.get_home_dir ();
            all_files = new FileInfo[0];
            filtered_files = new FileInfo[0];
            preview_visible = false;

            // ── Managers ──
            clipboard_mgr = new ClipboardManager ();
            custom_actions_mgr = new CustomActionsManager ();
            undo_manager = new UndoManager (fm);
            context_menu = new ContextMenu (fm, clipboard_mgr);

            // Wire context-menu signals
            wire_context_menu_signals ();

            get_style_context ().add_class ("tilefm-tile");

            // ── Toolbar with pathbar + close button ──
            var toolbar_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            toolbar_box.get_style_context ().add_class ("tilefm-pathbar");

            pathbar = new BreadcrumbPathBar ();
            pathbar.path_changed.connect ((new_path) => {
                navigate_to (new_path);
            });
            pathbar.navigate_up.connect (() => {
                var parent = file_manager.get_parent (current_path);
                if (parent != null) {
                    navigate_to (parent);
                }
            });
            toolbar_box.pack_start (pathbar, true, true, 0);

            var nav_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);

            var up_btn = new Gtk.Button.from_icon_name (
                "go-up-symbolic", Gtk.IconSize.MENU
            );
            up_btn.tooltip_text = "Parent Directory";
            up_btn.clicked.connect (() => {
                var parent = file_manager.get_parent (current_path);
                if (parent != null) {
                    navigate_to (parent);
                }
            });
            nav_box.add (up_btn);

            var home_btn = new Gtk.Button.from_icon_name (
                "go-home-symbolic", Gtk.IconSize.MENU
            );
            home_btn.tooltip_text = "Home";
            home_btn.clicked.connect (() => {
                navigate_to (Environment.get_home_dir ());
            });
            nav_box.add (home_btn);

            toolbar_box.pack_start (nav_box, false, false, 4);

            close_btn = new Gtk.Button.from_icon_name (
                "window-close-symbolic", Gtk.IconSize.MENU
            );
            close_btn.tooltip_text = "Close Tile";
            close_btn.clicked.connect (() => close_requested ());
            toolbar_box.pack_end (close_btn, false, false, 0);

            pack_start (toolbar_box, false, false, 0);

            // ── Typeahead Search Widget ──
            search_widget = new TypeaheadSearch ();
            search_widget.search_changed.connect (on_search_changed);
            search_widget.search_closed.connect (on_search_closed);
            pack_start (search_widget, false, false, 0);

            // ── Main content: Paned (FileView | PreviewPanel) ──
            main_paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            main_paned.expand = true;

            scrolled = new Gtk.ScrolledWindow (null, null);
            scrolled.set_policy (
                Gtk.PolicyType.AUTOMATIC,
                Gtk.PolicyType.AUTOMATIC
            );
            scrolled.expand = true;
            main_paned.pack1 (scrolled, true, false);

            preview_panel = new PreviewPanel ();
            preview_panel.no_show_all = true;
            preview_panel.hide ();
            main_paned.pack2 (preview_panel, false, false);

            pack_start (main_paned, true, true, 0);

            // ── Keyboard shortcuts ──
            key_press_event.connect (on_key_press);

            // ── Drag & Drop: DESTINATION ──
            Gtk.drag_dest_set (
                this,
                Gtk.DestDefaults.ALL,
                drag_targets,
                Gdk.DragAction.COPY | Gdk.DragAction.MOVE
            );
            drag_data_received.connect (on_drag_data_received);

            // ── Drag & Drop: SOURCE ──
            Gtk.drag_source_set (
                scrolled,
                Gdk.ModifierType.BUTTON1_MASK,
                source_targets,
                Gdk.DragAction.COPY | Gdk.DragAction.MOVE
            );
            scrolled.drag_begin.connect (on_drag_begin);
            scrolled.drag_data_get.connect (on_drag_data_get);

            // ── Initial navigation ──
            update_pathbar ();
            create_view ();
            load_directory.begin (current_path);
        }

        // ── Context Menu Signal Wiring ────────────────────────────

        private void wire_context_menu_signals () {
            context_menu.open_file_request.connect ((path) => {
                file_manager.open_file (path);
            });

            context_menu.cut_request.connect ((paths) => {
                clipboard_mgr.cut_files (paths);
                refresh ();
            });

            context_menu.copy_request.connect ((paths) => {
                clipboard_mgr.copy_files (paths);
            });

            context_menu.paste_request.connect ((target_dir) => {
                handle_paste.begin (target_dir);
            });

            context_menu.rename_request.connect ((path) => {
                show_rename_dialog.begin (path);
            });

            context_menu.trash_request.connect ((paths) => {
                handle_trash.begin (paths);
            });

            context_menu.delete_request.connect ((paths) => {
                handle_delete.begin (paths);
            });

            context_menu.copy_path_request.connect ((path) => {
                copy_path_to_system_clipboard (path);
            });

            context_menu.open_terminal_request.connect ((dir) => {
                open_terminal (dir);
            });

            context_menu.properties_request.connect ((path) => {
                show_properties_dialog (path);
            });

            context_menu.bulk_rename_request.connect ((paths) => {
                show_bulk_rename_dialog (paths);
            });
        }

        private void show_bulk_rename_dialog (string[] paths) {
            var dialog = new BulkRenameDialog (
                get_toplevel () as Gtk.Window,
                paths
            );
            dialog.apply_rename.connect ((old_paths, new_names) => {
                apply_bulk_rename (old_paths, new_names);
            });
            dialog.show ();
        }

        private void apply_bulk_rename (string[] old_paths, string[] new_names) {
            for (int i = 0; i < old_paths.length; i++) {
                string old_name = Path.get_basename (old_paths[i]);
                if (old_name == new_names[i]) continue;

                var parent = File.new_for_path (old_paths[i]).get_parent ();
                if (parent == null) continue;
                string new_path = Path.build_filename (parent.get_path (), new_names[i]);

                try {
                    var file = File.new_for_path (old_paths[i]);
                    file.move (File.new_for_path (new_path), FileCopyFlags.NONE);
                    undo_manager.record_rename (old_paths[i], new_path);
                } catch (Error e) {
                    warning ("Failed to rename '%s' to '%s': %s", old_paths[i], new_names[i], e.message);
                }
            }
            refresh ();
        }

        // ── Public API ────────────────────────────────────────────

        public void navigate_to (string path) {
            if (path == current_path) {
                return;
            }
            current_path = path;
            update_pathbar ();
            load_directory.begin (path);
            path_changed (path);
        }

        public void change_view_mode (ViewMode mode) {
            if (view_mode == mode && current_view != null) {
                return;
            }
            view_mode = mode;

            if (current_view != null) {
                scrolled.remove (current_view);
            }
            create_view ();

            if (search_widget.is_searching && filtered_files.length > 0) {
                current_view.set_files (current_path, filtered_files);
            } else {
                current_view.set_files (current_path, all_files);
            }
        }

        public void refresh () {
            load_directory.begin (current_path);
        }

        public Layout export_layout () {
            var layout = new Layout ();
            var tile_layout = new TileLayout ();
            tile_layout.path = current_path;
            tile_layout.view_mode = view_mode_to_string (view_mode);
            layout.tiles.add (tile_layout);
            return layout;
        }

        public void set_active (bool active) {
            is_active = active;
            if (active) {
                get_style_context ().add_class ("tilefm-tile-active");
            } else {
                get_style_context ().remove_class ("tilefm-tile-active");
            }
        }

        // ── Preview panel control ──

        public void toggle_preview () {
            if (preview_visible) {
                hide_preview ();
            } else {
                show_preview ();
            }
        }

        public void show_preview () {
            preview_visible = true;
            preview_panel.no_show_all = false;
            preview_panel.show_all ();

            if (current_view != null) {
                var paths = current_view.get_selected_paths ();
                if (paths.length > 0) {
                    preview_panel.update_preview (paths[0], file_manager);
                } else {
                    preview_panel.clear ();
                }
            }

            int tile_width = get_allocated_width ();
            if (tile_width > 300) {
                main_paned.set_position (tile_width - 280);
            }
        }

        public void hide_preview () {
            preview_visible = false;
            preview_panel.no_show_all = true;
            preview_panel.hide ();
        }

        // ── Search control ──

        public void show_search () {
            search_widget.show_search ();
        }

        public void hide_search () {
            search_widget.hide_search ();
        }

        public bool is_search_active () {
            return search_widget.is_searching;
        }

        // ── Undo / Redo ──

        public void undo () {
            handle_undo.begin ();
        }

        public void redo () {
            handle_redo.begin ();
        }

        public UndoManager get_undo_manager () {
            return undo_manager;
        }

        // ── Selection ──

        public string? get_selected_file_path () {
            if (current_view == null) return null;
            var paths = current_view.get_selected_paths ();
            if (paths.length > 0) return paths[0];
            return null;
        }

        public string[] get_selected_file_paths () {
            if (current_view == null) return new string[0];
            return current_view.get_selected_paths ();
        }

        // ── Private: View ─────────────────────────────────────────

        private void create_view () {
            switch (view_mode) {
                case ViewMode.ICON:
                    current_view = new IconViewWidget (file_manager);
                    break;
                case ViewMode.LIST:
                    current_view = new ListViewWidget (file_manager, false);
                    break;
                case ViewMode.DETAILS:
                    current_view = new ListViewWidget (file_manager, true);
                    break;
            }

            current_view.item_activated.connect ((path) => {
                var info = file_manager.get_file_info (path);
                if (info != null && info.get_file_type () == FileType.DIRECTORY) {
                    navigate_to (path);
                } else {
                    file_activated (path);
                    file_manager.open_file (path);
                }
            });

            current_view.selection_changed.connect ((paths) => {
                if (preview_visible) {
                    if (paths.length > 0) {
                        preview_panel.update_preview (paths[0], file_manager);
                    } else {
                        preview_panel.clear ();
                    }
                }

                int64 total_size = 0;
                foreach (var p in paths) {
                    var info = file_manager.get_file_info (p);
                    if (info != null) {
                        total_size += info.get_size ();
                    }
                }
                selection_info_changed ((int) paths.length, total_size);
            });

            // Right-click on file → context menu
            current_view.context_menu_requested.connect ((path, event) => {
                context_menu.show_for_file (path, event);
            });

            // Right-click on empty space → background context menu
            current_view.background_context_menu_requested.connect ((event) => {
                context_menu.show_for_background (current_path, event);
            });

            scrolled.add (current_view);
            scrolled.show_all ();
        }

        private async void load_directory (string path) {
            try {
                var infos = yield file_manager.list_directory (path);
                all_files = infos;

                if (search_widget.is_searching) {
                    var query = search_widget.get_query ();
                    filtered_files = FileSearcher.filter (all_files, query);
                    current_view.set_files (path, filtered_files);
                    search_widget.set_info (
                        (uint) filtered_files.length,
                        (uint) all_files.length
                    );
                } else {
                    filtered_files = new FileInfo[0];
                    current_view.set_files (path, all_files);
                }
            } catch (Error e) {
                warning ("Failed to load directory: %s", e.message);
                all_files = new FileInfo[0];
                filtered_files = new FileInfo[0];
                current_view.set_files (path, new FileInfo[0]);
            }
        }

        private void update_pathbar () {
            pathbar.set_path (current_path);
        }

        // ── Typeahead search ──

        private void on_search_changed (string query) {
            filtered_files = FileSearcher.filter (all_files, query);
            current_view.set_files (current_path, filtered_files);
            search_widget.set_info (
                (uint) filtered_files.length,
                (uint) all_files.length
            );
        }

        private void on_search_closed () {
            filtered_files = new FileInfo[0];
            current_view.set_files (current_path, all_files);
        }

        // ── Keyboard handler ──

        private bool on_key_press (Gdk.EventKey event) {
            // Ctrl+Z → Undo
            if (event.keyval == Gdk.Key.z
                && (event.state & Gdk.ModifierType.CONTROL_MASK) != 0
                && (event.state & Gdk.ModifierType.SHIFT_MASK) == 0) {
                handle_undo.begin ();
                return true;
            }

            // Ctrl+Shift+Z → Redo
            if ((event.keyval == Gdk.Key.z || event.keyval == Gdk.Key.Z)
                && (event.state & Gdk.ModifierType.CONTROL_MASK) != 0
                && (event.state & Gdk.ModifierType.SHIFT_MASK) != 0) {
                handle_redo.begin ();
                return true;
            }

            // Ctrl+F → show search
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0
                && event.keyval == Gdk.Key.f) {
                show_search ();
                return true;
            }

            // '/' → show search
            if (event.keyval == Gdk.Key.slash
                && (event.state & Gdk.ModifierType.CONTROL_MASK) == 0) {
                show_search ();
                return true;
            }

            // Escape → hide search if active
            if (event.keyval == Gdk.Key.Escape) {
                if (search_widget.is_searching) {
                    hide_search ();
                    return true;
                }
            }

            return false;
        }

        // ── Undo / Redo ───────────────────────────────────────────

        private async void handle_undo () {
            if (!undo_manager.can_undo ()) {
                return;
            }
            try {
                bool success = yield undo_manager.undo ();
                if (success) {
                    refresh ();
                }
            } catch (Error e) {
                warning ("Undo failed: %s", e.message);
                show_error_dialog ("Undo failed: %s".printf (e.message));
            }
        }

        private async void handle_redo () {
            if (!undo_manager.can_redo ()) {
                return;
            }
            try {
                bool success = yield undo_manager.redo ();
                if (success) {
                    refresh ();
                }
            } catch (Error e) {
                warning ("Redo failed: %s", e.message);
                show_error_dialog ("Redo failed: %s".printf (e.message));
            }
        }

        // ── Operation Handlers ────────────────────────────────────

        private async void handle_paste (string target_dir) {
            if (clipboard_mgr.is_empty ()) {
                return;
            }

            string[] files = clipboard_mgr.get_files ();
            bool is_cut = (clipboard_mgr.action == ClipboardAction.CUT);

            if (is_cut) {
                undo_manager.begin_batch ("Move %d file(s)".printf (files.length));
            }

            foreach (var src_path in files) {
                string basename = Path.get_basename (src_path);
                string dst_path = Path.build_filename (target_dir, basename);

                try {
                    if (is_cut) {
                        bool ok = yield file_manager.move (src_path, dst_path);
                        if (ok) {
                            undo_manager.record_batch_move (src_path, dst_path);
                        }
                    } else {
                        bool ok = yield file_manager.copy (src_path, dst_path);
                        if (ok) {
                            undo_manager.record_batch_copy (src_path, dst_path);
                        }
                    }
                } catch (Error e) {
                    warning ("Paste operation failed for '%s': %s", src_path, e.message);
                }
            }

            if (is_cut) {
                undo_manager.commit_batch ();
                clipboard_mgr.clear ();
            }
            refresh ();
        }

        private async void handle_trash (string[] paths) {
            undo_manager.begin_batch ("Trash %d file(s)".printf (paths.length));

            foreach (var path in paths) {
                try {
                    bool ok = yield TrashManager.trash_file (path);
                    if (ok) {
                        var trashed_file = File.new_for_path (path);
                        string trash_uri = "trash:///" + trashed_file.get_basename ();
                        undo_manager.record_batch_delete (path, trash_uri);
                    }
                } catch (Error e) {
                    warning ("Failed to trash '%s': %s", path, e.message);
                }
            }

            undo_manager.commit_batch ();
            refresh ();
        }

        private async void handle_delete (string[] paths) {
            var dialog = new Gtk.MessageDialog (
                get_toplevel () as Gtk.Window,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.WARNING,
                Gtk.ButtonsType.NONE,
                "Are you sure you want to permanently delete the selected item(s)?"
            );
            dialog.add_button ("_Cancel", Gtk.ResponseType.CANCEL);
            dialog.add_button ("_Delete", Gtk.ResponseType.OK);
            int response = dialog.run ();
            dialog.destroy ();

            if (response != Gtk.ResponseType.OK) {
                return;
            }

            undo_manager.begin_batch ("Delete %d file(s)".printf (paths.length));

            foreach (var path in paths) {
                try {
                    bool ok = yield file_manager.delete_file (path);
                    if (ok) {
                        undo_manager.record_batch_delete (path, "");
                    }
                } catch (Error e) {
                    warning ("Failed to delete '%s': %s", path, e.message);
                }
            }

            undo_manager.commit_batch ();
            refresh ();
        }

        // ── Rename Dialog ─────────────────────────────────────────

        private async void show_rename_dialog (string path) {
            string basename = Path.get_basename (path);
            string parent = file_manager.get_parent (path) ?? ".";

            var dialog = new Gtk.Dialog.with_buttons (
                "Rename",
                get_toplevel () as Gtk.Window,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                "_Cancel", Gtk.ResponseType.CANCEL,
                "_Rename", Gtk.ResponseType.OK,
                null
            );
            dialog.set_default_size (350, 100);

            var content = dialog.get_content_area ();
            content.margin = 12;
            content.spacing = 8;

            var label = new Gtk.Label ("Enter new name:");
            label.halign = Gtk.Align.START;
            content.add (label);

            var entry = new Gtk.Entry ();
            entry.set_text (basename);
            entry.set_activates_default (true);
            entry.select_region (0, -1);
            content.add (entry);

            dialog.set_default_response (Gtk.ResponseType.OK);
            dialog.show_all ();

            int response = dialog.run ();
            string new_name = entry.get_text ().strip ();
            dialog.destroy ();

            if (response == Gtk.ResponseType.OK && new_name != "" && new_name != basename) {
                try {
                    string old_path = path;
                    bool ok = yield file_manager.rename (old_path, new_name);
                    if (ok) {
                        string new_path = Path.build_filename (parent, new_name);
                        undo_manager.record_rename (old_path, new_path);
                    }
                } catch (Error e) {
                    warning ("Failed to rename '%s': %s", path, e.message);
                    show_error_dialog ("Rename failed: %s".printf (e.message));
                }
                refresh ();
            }
        }

        // ── Properties Dialog ─────────────────────────────────────

        private void show_properties_dialog (string path) {
            var dialog = new Gtk.Dialog.with_buttons (
                "Properties",
                get_toplevel () as Gtk.Window,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                "_Close", Gtk.ResponseType.CLOSE,
                null
            );
            dialog.set_default_size (400, 300);

            var content = dialog.get_content_area ();
            content.margin = 12;
            content.spacing = 8;

            var grid = new Gtk.Grid ();
            grid.row_spacing = 6;
            grid.column_spacing = 12;

            FileInfo? info = file_manager.get_file_info (path);
            if (info == null) {
                var error_label = new Gtk.Label ("Failed to read file information.");
                content.add (error_label);
            } else {
                int row = 0;

                add_prop_row (grid, ref row, "Name:", info.get_name ());

                string content_type = info.get_content_type () ?? "Unknown";
                string desc = ContentType.get_description (content_type) ?? content_type;
                add_prop_row (grid, ref row, "Type:", desc);

                int64 size = info.get_size ();
                add_prop_row (grid, ref row, "Size:", format_size (size));

                var mod_date = info.get_modification_date_time ();
                if (mod_date != null) {
                    add_prop_row (grid, ref row, "Modified:", mod_date.format ("%Y-%m-%d %H:%M:%S"));
                }

                if (info.has_attribute ("time::modified")) {
                    uint64 atime = info.get_attribute_uint64 ("time::modified");
                    var dt = new DateTime.from_unix_local ((int64) atime);
                    add_prop_row (grid, ref row, "Accessed:", dt.format ("%Y-%m-%d %H:%M:%S"));
                }

                var f = File.new_for_path (path);
                string? fparent = f.get_parent ()?.get_path ();
                add_prop_row (grid, ref row, "Location:", fparent ?? "Unknown");

                row++;
                var perm_label = new Gtk.Label ("");
                perm_label.use_markup = true;
                perm_label.halign = Gtk.Align.START;
                perm_label.set_markup ("<b>Permissions</b>");
                grid.attach (perm_label, 0, row, 2, 1);
                row++;

                uint32 mode = info.get_attribute_uint32 ("unix::mode");
                add_prop_row (grid, ref row, "Owner:", format_permissions (mode, 6));
                add_prop_row (grid, ref row, "Group:", format_permissions (mode, 3));
                add_prop_row (grid, ref row, "Other:", format_permissions (mode, 0));
            }

            var scroll = new Gtk.ScrolledWindow (null, null);
            scroll.set_policy (Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
            scroll.add_with_viewport (grid);
            scroll.expand = true;
            content.add (scroll);

            dialog.show_all ();
            dialog.response.connect ((response) => {
                dialog.destroy ();
            });
        }

        private void add_prop_row (Gtk.Grid grid, ref int row, string label_text, string value_text) {
            var label = new Gtk.Label (label_text);
            label.halign = Gtk.Align.END;
            label.hexpand = false;

            var value = new Gtk.Label (value_text);
            value.halign = Gtk.Align.START;
            value.hexpand = true;
            value.selectable = true;
            value.xalign = 0;

            grid.attach (label, 0, row, 1, 1);
            grid.attach (value, 1, row, 1, 1);
            row++;
        }

        // ── Helpers ───────────────────────────────────────────────

        private string format_size (int64 size) {
            if (size < 1024)
                return "%lld bytes".printf (size);
            if (size < 1024 * 1024)
                return "%.1f KB".printf (size / 1024.0);
            if (size < 1024 * 1024 * 1024)
                return "%.1f MB".printf (size / (1024.0 * 1024.0));
            return "%.1f GB".printf (size / (1024.0 * 1024.0 * 1024.0));
        }

        private string format_permissions (uint32 mode, int shift) {
            int r = ((int)(mode >> (shift + 2))) & 1;
            int w = ((int)(mode >> (shift + 1))) & 1;
            int x = ((int)(mode >> shift)) & 1;
            return "%s%s%s".printf (
                r == 1 ? "r" : "-",
                w == 1 ? "w" : "-",
                x == 1 ? "x" : "-"
            );
        }

        private void copy_path_to_system_clipboard (string path) {
            var display = Gdk.Display.get_default ();
            if (display == null)
                return;

            Gtk.Clipboard clipboard_default = Gtk.Clipboard.get_default (display);
            if (clipboard_default != null) {
                clipboard_default.set_text (path, -1);
                clipboard_default.store ();
            }
        }

        private void open_terminal (string dir) {
            string[] terminals = {
                "x-terminal-emulator",
                "gnome-terminal",
                "xfce4-terminal",
                "konsole",
                "lxterminal",
                "alacritty",
                "kitty",
                "xterm"
            };

            foreach (var term in terminals) {
                string cmd;
                if (term == "x-terminal-emulator") {
                    cmd = "x-terminal-emulator -w %s".printf (Shell.quote (dir));
                } else if (term == "gnome-terminal" || term == "xfce4-terminal") {
                    cmd = "%s --working-directory=%s".printf (term, Shell.quote (dir));
                } else {
                    cmd = term;
                }

                try {
                    Process.spawn_command_line_async (cmd);
                    return;
                } catch (Error e) {
                    continue;
                }
            }

            warning ("Could not find a terminal emulator to open in '%s'", dir);
        }

        private void show_error_dialog (string message) {
            var dialog = new Gtk.MessageDialog (
                get_toplevel () as Gtk.Window,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.ERROR,
                Gtk.ButtonsType.OK,
                "%s", message
            );
            dialog.run ();
            dialog.destroy ();
        }

        // ── Drag & Drop ───────────────────────────────────────────

        private void on_drag_begin (Gdk.DragContext context) {
            var paths = current_view.get_selected_paths ();
            if (paths.length > 0) {
                Gtk.drag_source_set_icon_name (scrolled, "text-x-generic");
            }
        }

        private void on_drag_data_get (
            Gdk.DragContext context,
            Gtk.SelectionData data,
            uint info,
            uint time
        ) {
            var paths = current_view.get_selected_paths ();
            if (paths.length == 0) {
                return;
            }

            string[] uris = new string[paths.length + 1];
            for (int i = 0; i < paths.length; i++) {
                uris[i] = File.new_for_path (paths[i]).get_uri ();
            }
            uris[paths.length] = null;

            data.set_uris (uris);
        }

        private void on_drag_data_received (
            Gdk.DragContext context,
            int x, int y,
            Gtk.SelectionData data,
            uint info,
            uint time
        ) {
            var uris = data.get_uris ();
            var action = context.get_selected_action ();

            foreach (var uri in uris) {
                var file = File.new_for_uri (uri);
                var path = file.get_path ();
                if (path == null) {
                    continue;
                }

                var file_info = file_manager.get_file_info (path);
                if (file_info != null
                    && file_info.get_file_type () == FileType.DIRECTORY) {
                    navigate_to (path);
                } else {
                    var basename = file.get_basename ();
                    var dest_path = Path.build_filename (current_path, basename);

                    if (action == Gdk.DragAction.MOVE) {
                        handle_drag_move.begin (path, dest_path);
                    } else {
                        handle_drag_copy.begin (path, dest_path);
                    }
                }
            }

            Gtk.drag_finish (context, true, action == Gdk.DragAction.MOVE, time);
        }

        private async void handle_drag_move (string src_path, string dest_path) {
            try {
                bool ok = yield file_manager.move (src_path, dest_path);
                if (ok) {
                    undo_manager.record_move (src_path, dest_path);
                }
            } catch (Error e) {
                warning ("Drag move failed: %s", e.message);
            }
            refresh ();
        }

        private async void handle_drag_copy (string src_path, string dest_path) {
            try {
                bool ok = yield file_manager.copy (src_path, dest_path);
                if (ok) {
                    undo_manager.record_copy (src_path, dest_path);
                }
            } catch (Error e) {
                warning ("Drag copy failed: %s", e.message);
            }
            refresh ();
        }

        private string view_mode_to_string (ViewMode mode) {
            switch (mode) {
                case ViewMode.ICON: return "icon";
                case ViewMode.LIST: return "list";
                case ViewMode.DETAILS: return "details";
                default: return "icon";
            }
        }
    }
}
