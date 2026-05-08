/* TileFM — IconView
 * Icon/grid display mode
 */

namespace TileFm {
    public class IconViewWidget : FileView {
        private Gtk.IconView icon_view;
        private Gtk.ListStore store;
        
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
            
            icon_view = new Gtk.IconView.with_model(store);
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
                Gtk.TreeIter iter;
                if (store.get_iter(out iter, path)) {
                    string filepath;
                    store.get(iter, Column.PATH, out filepath, -1);
                    on_item_activated(Path.get_basename(filepath));
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
                        if (store.get_iter(out iter, path)) {
                            string filepath;
                            store.get(iter, Column.PATH, out filepath, -1);
                            context_menu_requested(filepath, event);
                        }
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
        }
        
        public override string[] get_selected_paths() {
            var selected = icon_view.get_selected_items();
            var paths = new string[0];
            
            foreach (var path in selected) {
                Gtk.TreeIter iter;
                if (store.get_iter(out iter, path)) {
                    string filepath;
                    store.get(iter, Column.PATH, out filepath, -1);
                    paths += filepath;
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
            // Trigger reload
            load_directory.begin(current_directory);
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
