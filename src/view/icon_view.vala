/* TileFM -- IconView
 * Icon/grid display mode
 */

namespace TileFm {
    public class IconViewWidget : FileView {
        private Gtk.IconView icon_view;
        private Gtk.ListStore store;
        private Gtk.TreeModelFilter filter_model;
        private string last_directory;
        private FileInfo[] last_infos;

        private enum Column {
            ICON,
            NAME,
            PATH,
            IS_DIRECTORY,
            DISPLAY_NAME
        }

        public IconViewWidget(FileManager fm) {
            base(fm);

            // ListStore: GdkPixbuf, string, string, bool, string
            store = new Gtk.ListStore(
                5,
                typeof(Gdk.Pixbuf),   // ICON
                typeof(string),        // NAME (internal)
                typeof(string),        // PATH
                typeof(bool),          // IS_DIRECTORY
                typeof(string)         // DISPLAY_NAME
            );

            // Filter model for search
            filter_model = new Gtk.TreeModelFilter(store, null);
            filter_model.set_visible_func((model, iter) => {
                if (current_filter == "") return true;
                string display_name;
                model.get(iter, Column.DISPLAY_NAME, out display_name, -1);
                return display_name.ascii_down().contains(current_filter.ascii_down());
            });

            icon_view = new Gtk.IconView.with_model(filter_model);
            icon_view.set_text_column(Column.DISPLAY_NAME);
            icon_view.set_pixbuf_column(Column.ICON);
            icon_view.set_selection_mode(Gtk.SelectionMode.MULTIPLE);
            icon_view.set_item_width(100);
            icon_view.set_spacing(4);
            icon_view.set_row_spacing(8);
            icon_view.set_column_spacing(8);
            icon_view.set_margin(8);

            // Activate on double-click
            icon_view.item_activated.connect((path) => {
                Gtk.TreeIter filter_iter;
                Gtk.TreeIter child_iter;
                bool _got_iter = ((Gtk.TreeModel)filter_model).get_iter(out filter_iter, path);
                if (_got_iter) {
                    filter_model.convert_iter_to_child_iter(out child_iter, filter_iter); if (true) {
                        string filepath;
                        store.get(child_iter, Column.PATH, out filepath, -1);
                        item_activated(filepath);
                    }
                }
            });

            // Selection changed
            icon_view.selection_changed.connect(() => {
                var paths = get_selected_paths();
                selection_changed(paths);
            });

            // Context menu
            icon_view.button_press_event.connect((event) => {
                if (event.button == 3) { // Right click
                    var path = icon_view.get_path_at_pos((int) event.x, (int) event.y);
                    if (path != null) {
                        Gtk.TreeIter iter;
                        Gtk.TreeIter child_iter;
                        bool _got_iter = ((Gtk.TreeModel)filter_model).get_iter(out iter, path);
                        if (_got_iter) {
                            filter_model.convert_iter_to_child_iter(out child_iter, iter); if (true) {
                                string filepath;
                                store.get(child_iter, Column.PATH, out filepath, -1);
                                context_menu_requested(filepath, event);
                            }
                        }
                    } else {
                        background_context_menu_requested(event);
                    }
                    return true;
                }
                return false;
            });

            var scrolled = new Gtk.ScrolledWindow(null, null);
            scrolled.set_policy(
                Gtk.PolicyType.AUTOMATIC,
                Gtk.PolicyType.AUTOMATIC
            );
            scrolled.add(icon_view);
            scrolled.expand = true;

            add(scrolled);
        }

        public override void set_files(string directory, FileInfo[] infos) {
            current_directory = directory;
            last_directory = directory;
            last_infos = infos;
            store.clear();
            file_map.clear();

            var icon_theme = Gtk.IconTheme.get_default();

            foreach (var info in infos) {
                var name = info.get_name();
                var display_name = info.get_display_name() ?? name;
                var full_path = Path.build_filename(directory, name);
                var is_dir = info.get_file_type() == FileType.DIRECTORY;

                file_map[name] = info;

                // Get icon
                Gdk.Pixbuf? pixbuf = null;
                var icon = info.get_icon();
                if (icon != null) {
                    try {
                        pixbuf = icon_theme.load_icon(
                            icon.to_string(),
                            48,
                            Gtk.IconLookupFlags.USE_BUILTIN
                        );
                    } catch (Error e) {
                        // Fallback icon
                        try {
                            pixbuf = icon_theme.load_icon(
                                is_dir ? "folder" : "text-x-generic",
                                48,
                                Gtk.IconLookupFlags.USE_BUILTIN
                            );
                        } catch (Error e2) {
                            // Will show without icon
                        }
                    }
                }

                Gtk.TreeIter iter;
                store.append(out iter);
                store.set(iter,
                    Column.ICON, pixbuf,
                    Column.NAME, name,
                    Column.PATH, full_path,
                    Column.IS_DIRECTORY, is_dir,
                    Column.DISPLAY_NAME, display_name,
                    -1
                );
            }

            if (current_filter != "") {
                filter_model.refilter();
            }
        }

        public override string[] get_selected_paths() {
            var selected = icon_view.get_selected_items();
            var paths = new string[0];

            foreach (var path in selected) {
                Gtk.TreeIter filter_iter;
                Gtk.TreeIter child_iter;
                bool _got_iter = ((Gtk.TreeModel)filter_model).get_iter(out filter_iter, path);
                if (_got_iter) {
                    filter_model.convert_iter_to_child_iter(out child_iter, filter_iter); if (true) {
                        string filepath;
                        store.get(child_iter, Column.PATH, out filepath, -1);
                        paths += filepath;
                    }
                }
            }

            return paths;
        }

        public override void select_all() {
            icon_view.select_all();
        }

        public override void select_none() {
            icon_view.unselect_all();
        }

        public override void refresh() {
            load_directory.begin(current_directory);
        }

        public override void filter_files(string query) {
            current_filter = query;
            filter_model.refilter();
        }

        public override void clear_filter() {
            current_filter = "";
            filter_model.refilter();
        }

        public override void select_next() {
            var selected = icon_view.get_selected_items();
            Gtk.TreePath? next_path = null;

            if (selected.length() > 0) {
                // Get last selected and move to next
                unowned GLib.List<Gtk.TreePath> sel_list = selected;
                var last_path = (Gtk.TreePath)sel_list.nth_data(selected.length() - 1);
                next_path = last_path.copy();
                next_path.next();

                Gtk.TreeIter iter;
                if (!filter_model.get_iter(out iter, next_path)) {
                    next_path = null;
                }
            }

            if (next_path == null) {
                // Select first item
                next_path = new Gtk.TreePath.first();
            }

            if (next_path != null) {
                icon_view.unselect_all();
                icon_view.select_path(next_path);
                icon_view.scroll_to_path(next_path, false, 0, 0);
            }
        }

        public override void select_previous() {
            var selected = icon_view.get_selected_items();
            Gtk.TreePath? prev_path = null;

            if (selected.length() > 0) {
                unowned GLib.List<Gtk.TreePath> sel_list = selected;
                var first_path = (Gtk.TreePath)sel_list.nth_data(0);
                int depth;
                int[] indices = first_path.get_indices();
                if (indices[0] > 0) {
                    prev_path = new Gtk.TreePath.from_indices(indices[0] - 1, -1);
                }
            }

            if (prev_path == null) {
                // Try to get last item
                int n_items = filter_model.iter_n_children(null);
                if (n_items > 0) {
                    prev_path = new Gtk.TreePath.from_indices(n_items - 1, -1);
                }
            }

            if (prev_path != null) {
                icon_view.unselect_all();
                icon_view.select_path(prev_path);
                icon_view.scroll_to_path(prev_path, false, 0, 0);
            }
        }

        public override void activate_selected() {
            var selected = icon_view.get_selected_items();
            if (selected.length() > 0) {
                unowned GLib.List<Gtk.TreePath> sel_list = selected;
                var path = (Gtk.TreePath)sel_list.nth_data(0);
                Gtk.TreeIter filter_iter;
                Gtk.TreeIter child_iter;
                bool _got_iter = ((Gtk.TreeModel)filter_model).get_iter(out filter_iter, path);
                if (_got_iter) {
                    filter_model.convert_iter_to_child_iter(out child_iter, filter_iter); if (true) {
                        string filepath;
                        store.get(child_iter, Column.PATH, out filepath, -1);
                        item_activated(filepath);
                    }
                }
            }
        }

        private async void load_directory(string path) {
            try {
                var infos = yield file_manager.list_directory(path);
                set_files(path, infos);
            } catch (Error e) {
                warning("Failed to refresh: %s", e.message);
            }
        }
    }
}
