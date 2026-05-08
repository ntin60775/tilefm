/* TileFM -- ListView and DetailsView
 * List and detailed column display modes
 */

namespace TileFm {
    public class ListViewWidget : FileView {
        private Gtk.TreeView tree_view;
        private Gtk.ListStore store;
        private Gtk.TreeModelFilter filter_model;
        private bool is_details_mode;

        private enum Column {
            ICON,
            NAME,
            PATH,
            SIZE,
            SIZE_SORT,
            MODIFIED,
            MODIFIED_SORT,
            TYPE,
            IS_DIRECTORY,
            DISPLAY_NAME
        }

        public ListViewWidget(FileManager fm, bool details) {
            base(fm);
            is_details_mode = details;

            // ListStore: icon-name, name, path, size-display, size-bytes,
            //           modified-display, modified-time, mime-type, is-dir, display-name
            store = new Gtk.ListStore(
                10,
                typeof(string),     // ICON (icon name)
                typeof(string),     // NAME (internal filename)
                typeof(string),     // PATH (full path)
                typeof(string),     // SIZE (display string)
                typeof(int64),      // SIZE_SORT (bytes for sorting)
                typeof(string),     // MODIFIED (display string)
                typeof(int64),      // MODIFIED_SORT (time for sorting)
                typeof(string),     // TYPE (MIME type)
                typeof(bool),       // IS_DIRECTORY
                typeof(string)      // DISPLAY_NAME
            );

            // Filter model for search
            filter_model = new Gtk.TreeModelFilter(store, null);
            filter_model.set_visible_func((model, iter) => {
                if (current_filter == "") return true;
                string display_name;
                model.get(iter, Column.DISPLAY_NAME, out display_name, -1);
                return display_name.ascii_down().contains(current_filter.ascii_down());
            });

            tree_view = new Gtk.TreeView.with_model(filter_model);
            tree_view.set_rules_hint(true);
            tree_view.set_enable_search(true);
            tree_view.set_search_column(Column.DISPLAY_NAME);
            tree_view.set_headers_visible(true);

            // Name column with icon
            var name_renderer = new Gtk.CellRendererPixbuf();
            var name_text_renderer = new Gtk.CellRendererText();
            name_text_renderer.ellipsize = Pango.EllipsizeMode.END;

            var name_column = new Gtk.TreeViewColumn();
            name_column.title = "Name";
            name_column.pack_start(name_renderer, false);
            name_column.pack_start(name_text_renderer, true);
            name_column.add_attribute(name_renderer, "icon-name", Column.ICON);
            name_column.add_attribute(name_text_renderer, "text", Column.DISPLAY_NAME);
            name_column.set_sort_column_id(Column.DISPLAY_NAME);
            name_column.set_resizable(true);
            name_column.set_expand(true);
            name_column.set_min_width(200);
            tree_view.append_column(name_column);

            // Size column (only in details mode)
            if (details) {
                var size_renderer = new Gtk.CellRendererText();
                size_renderer.xalign = 1.0f;
                var size_column = new Gtk.TreeViewColumn();
                size_column.title = "Size";
                size_column.pack_start(size_renderer, true);
                size_column.add_attribute(size_renderer, "text", Column.SIZE);
                size_column.set_sort_column_id(Column.SIZE_SORT);
                size_column.set_resizable(true);
                size_column.set_min_width(80);
                tree_view.append_column(size_column);

                // Type column
                var type_renderer = new Gtk.CellRendererText();
                var type_column = new Gtk.TreeViewColumn();
                type_column.title = "Type";
                type_column.pack_start(type_renderer, true);
                type_column.add_attribute(type_renderer, "text", Column.TYPE);
                type_column.set_resizable(true);
                type_column.set_min_width(120);
                tree_view.append_column(type_column);

                // Modified column
                var mod_renderer = new Gtk.CellRendererText();
                var mod_column = new Gtk.TreeViewColumn();
                mod_column.title = "Modified";
                mod_column.pack_start(mod_renderer, true);
                mod_column.add_attribute(mod_renderer, "text", Column.MODIFIED);
                mod_column.set_sort_column_id(Column.MODIFIED_SORT);
                mod_column.set_resizable(true);
                mod_column.set_min_width(150);
                tree_view.append_column(mod_column);
            }

            // Selection
            var selection = tree_view.get_selection();
            selection.set_mode(Gtk.SelectionMode.MULTIPLE);
            selection.changed.connect(() => {
                selection_changed(get_selected_paths());
            });

            // Activate on double-click
            tree_view.row_activated.connect((path, column) => {
                Gtk.TreeIter filter_iter;
                Gtk.TreeIter child_iter;
                bool _got_iter = ((Gtk.TreeModel)filter_model).get_iter(out filter_iter, path);
                if (_got_iter) {
                    filter_model.convert_iter_to_child_iter(out child_iter, filter_iter); if (true) {
                        string filepath;
                        store.get(child_iter, Column.PATH, out filepath, -1);
                        on_item_activated(Path.get_basename(filepath));
                    }
                }
            });

            // Context menu: right-click on file or background
            tree_view.button_press_event.connect((event) => {
                if (event.button == 3) { // Right click
                    Gtk.TreePath path;
                    if (tree_view.get_path_at_pos((int) event.x, (int) event.y, out path, null, null, null)) {
                        // Right-click on a file row
                        Gtk.TreeIter filter_iter;
                        Gtk.TreeIter child_iter;
                        bool _got_iter = ((Gtk.TreeModel)filter_model).get_iter(out filter_iter, path);
                        if (_got_iter) {
                            filter_model.convert_iter_to_child_iter(out child_iter, filter_iter); if (true) {
                                string filepath;
                                store.get(child_iter, Column.PATH, out filepath, -1);
                                context_menu_requested(filepath, event);
                            }
                        }
                    } else {
                        // Right-click on empty space (background)
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
            scrolled.add(tree_view);
            scrolled.expand = true;

            add(scrolled);
        }

        public override void set_files(string directory, FileInfo[] infos) {
            current_directory = directory;
            store.clear();
            file_map.clear();

            foreach (var info in infos) {
                var name = info.get_name();
                var display_name = info.get_display_name() ?? name;
                var full_path = Path.build_filename(directory, name);
                var is_dir = info.get_file_type() == FileType.DIRECTORY;

                file_map[name] = info;

                // Icon
                var icon = info.get_icon();
                var icon_name = icon != null ? icon.to_string() : "text-x-generic";
                if (is_dir) {
                    icon_name = "folder";
                }

                // Size
                int64 size = 0;
                string size_str = "";
                if (!is_dir) {
                    size = info.get_size();
                    size_str = format_size(size);
                }

                // Modified time
                int64 mod_time = 0;
                string mod_str = "";
                var mod_date = info.get_modification_date_time();
                if (mod_date != null) {
                    mod_time = mod_date.to_unix();
                    mod_str = mod_date.format("%Y-%m-%d %H:%M");
                }

                // MIME type
                var mime = info.get_content_type() ?? "unknown";

                Gtk.TreeIter iter;
                store.append(out iter);
                store.set(iter,
                    Column.ICON, icon_name,
                    Column.NAME, name,
                    Column.PATH, full_path,
                    Column.SIZE, size_str,
                    Column.SIZE_SORT, size,
                    Column.MODIFIED, mod_str,
                    Column.MODIFIED_SORT, mod_time,
                    Column.TYPE, mime,
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
            var selection = tree_view.get_selection();
            var model = selection.get_selected_rows(null);
            var paths = new string[0];

            foreach (var path in model) {
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
            tree_view.get_selection().select_all();
        }

        public override void select_none() {
            tree_view.get_selection().unselect_all();
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
            var selection = tree_view.get_selection();
            var selected_rows = selection.get_selected_rows(null);

            Gtk.TreePath? next_path = null;
            if (selected_rows.length() > 0) {
                unowned GLib.List<Gtk.TreePath> rows = selected_rows;
                var last = (Gtk.TreePath)rows.nth_data(selected_rows.length() - 1);
                next_path = last.copy();
                next_path.next();

                Gtk.TreeIter iter;
                if (!filter_model.get_iter(out iter, next_path)) {
                    next_path = null;
                }
            }

            if (next_path == null) {
                next_path = new Gtk.TreePath.first();
            }

            if (next_path != null) {
                selection.unselect_all();
                selection.select_path(next_path);
                tree_view.scroll_to_cell(next_path, null, false, 0, 0);
            }
        }

        public override void select_previous() {
            var selection = tree_view.get_selection();
            var selected_rows = selection.get_selected_rows(null);

            Gtk.TreePath? prev_path = null;
            if (selected_rows.length() > 0) {
                unowned GLib.List<Gtk.TreePath> rows = selected_rows;
                var first = (Gtk.TreePath)rows.nth_data(0);
                int depth;
                int[] indices = first.get_indices();
                if (indices[0] > 0) {
                    prev_path = new Gtk.TreePath.from_indices(indices[0] - 1, -1);
                }
            }

            if (prev_path == null) {
                int n = filter_model.iter_n_children(null);
                if (n > 0) {
                    prev_path = new Gtk.TreePath.from_indices(n - 1, -1);
                }
            }

            if (prev_path != null) {
                selection.unselect_all();
                selection.select_path(prev_path);
                tree_view.scroll_to_cell(prev_path, null, false, 0, 0);
            }
        }

        public override void activate_selected() {
            var selection = tree_view.get_selection();
            var selected_rows = selection.get_selected_rows(null);
            if (selected_rows.length() > 0) {
                unowned GLib.List<Gtk.TreePath> rows = selected_rows;
                var path = (Gtk.TreePath)rows.nth_data(0);
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

        private string format_size(int64 size) {
            if (size < 1024) return "%lld B".printf(size);
            if (size < 1024 * 1024) return "%.1f KB".printf(size / 1024.0);
            if (size < 1024 * 1024 * 1024) return "%.1f MB".printf(size / (1024.0 * 1024));
            return "%.1f GB".printf(size / (1024.0 * 1024 * 1024));
        }
    }
}
