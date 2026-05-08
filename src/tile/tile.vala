/* TileFM — Tile
 * Single tile: contains pathbar + file view
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
        public signal void path_changed(string new_path);
        public signal void navigate_request(string path);
        public signal void close_requested();
        public signal void file_activated(string path);
        
        // Private
        private FileManager file_manager;
        private BreadcrumbPathBar pathbar;
        private Gtk.ScrolledWindow scrolled;
        private FileView current_view;
        private Gtk.Toolbar toolbar;
        private Gtk.Button close_btn;
        
        private const Gtk.TargetEntry[] drag_targets = {
            { "text/uri-list", 0, 0 }
        };
        
        public Tile(FileManager fm, string? path = null) {
            Object(
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0
            );
            
            file_manager = fm;
            current_path = path ?? Environment.get_home_dir();
            
            get_style_context().add_class("tilefm-tile");
            
            // Toolbar with pathbar + close button
            var toolbar_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            toolbar_box.get_style_context().add_class("tilefm-pathbar");
            
            // PathBar
            pathbar = new BreadcrumbPathBar();
            pathbar.path_changed.connect((new_path) => {
                navigate_to(new_path);
            });
            pathbar.navigate_up.connect(() => {
                var parent = file_manager.get_parent(current_path);
                if (parent != null) {
                    navigate_to(parent);
                }
            });
            toolbar_box.pack_start(pathbar, true, true, 0);
            
            // Navigation buttons
            var nav_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            
            var up_btn = new Gtk.Button.from_icon_name(
                "go-up-symbolic", Gtk.IconSize.MENU
            );
            up_btn.tooltip_text = "Parent Directory";
            up_btn.clicked.connect(() => {
                var parent = file_manager.get_parent(current_path);
                if (parent != null) {
                    navigate_to(parent);
                }
            });
            nav_box.add(up_btn);
            
            var home_btn = new Gtk.Button.from_icon_name(
                "go-home-symbolic", Gtk.IconSize.MENU
            );
            home_btn.tooltip_text = "Home";
            home_btn.clicked.connect(() => {
                navigate_to(Environment.get_home_dir());
            });
            nav_box.add(home_btn);
            
            toolbar_box.pack_start(nav_box, false, false, 4);
            
            // Close button
            close_btn = new Gtk.Button.from_icon_name(
                "window-close-symbolic", Gtk.IconSize.MENU
            );
            close_btn.tooltip_text = "Close Tile";
            close_btn.clicked.connect(() => close_requested());
            toolbar_box.pack_end(close_btn, false, false, 0);
            
            pack_start(toolbar_box, false, false, 0);
            
            // File View (scrolled)
            scrolled = new Gtk.ScrolledWindow(null, null);
            scrolled.set_policy(
                Gtk.PolicyType.AUTOMATIC,
                Gtk.PolicyType.AUTOMATIC
            );
            scrolled.expand = true;
            pack_start(scrolled, true, true, 0);
            
            // Setup drag and drop
            Gtk.drag_dest_set(
                this,
                Gtk.DestDefaults.ALL,
                drag_targets,
                Gdk.DragAction.COPY | Gdk.DragAction.MOVE
            );
            
            drag_data_received.connect(on_drag_data_received);
            
            // Initial navigation
            update_pathbar();
            create_view();
            load_directory.begin(current_path);
        }
        
        public void navigate_to(string path) {
            if (path == current_path) {
                return;
            }
            
            current_path = path;
            update_pathbar();
            load_directory.begin(path);
            path_changed(path);
        }
        
        public void change_view_mode(ViewMode mode) {
            if (view_mode == mode && current_view != null) {
                return;
            }
            
            view_mode = mode;
            
            // Remove old view
            if (current_view != null) {
                scrolled.remove(current_view);
            }
            
            // Create new view
            create_view();
            load_directory.begin(current_path);
        }
        
        public void refresh() {
            load_directory.begin(current_path);
        }
        
        public Layout export_layout() {
            var layout = new Layout();
            var tile_layout = new TileLayout();
            tile_layout.path = current_path;
            tile_layout.view_mode = view_mode_to_string(view_mode);
            layout.tiles.add(tile_layout);
            return layout;
        }
        
        public void set_active(bool active) {
            is_active = active;
            if (active) {
                get_style_context().add_class("tilefm-tile-active");
            } else {
                get_style_context().remove_class("tilefm-tile-active");
            }
        }
        
        private void create_view() {
            switch (view_mode) {
                case ViewMode.ICON:
                    current_view = new IconViewWidget(file_manager);
                    break;
                case ViewMode.LIST:
                    current_view = new ListViewWidget(file_manager, false);
                    break;
                case ViewMode.DETAILS:
                    current_view = new ListViewWidget(file_manager, true);
                    break;
            }
            
            current_view.item_activated.connect((path) => {
                var info = file_manager.get_file_info(path);
                if (info != null && info.get_file_type() == FileType.DIRECTORY) {
                    navigate_to(path);
                } else {
                    file_activated(path);
                    file_manager.open_file(path);
                }
            });
            
            current_view.selection_changed.connect((paths) => {
                // TODO: update status bar with selection info
            });
            
            scrolled.add(current_view);
            scrolled.show_all();
        }
        
        private async void load_directory(string path) {
            try {
                var infos = yield file_manager.list_directory(path);
                current_view.set_files(path, infos);
            } catch (Error e) {
                warning("Failed to load directory: %s", e.message);
                current_view.set_files(path, new FileInfo[0]);
            }
        }
        
        private void update_pathbar() {
            pathbar.set_path(current_path);
        }
        
        private void on_drag_data_received(
            Gdk.DragContext context,
            int x, int y,
            Gtk.SelectionData data,
            uint info,
            uint time
        ) {
            var uris = data.get_uris();
            foreach (var uri in uris) {
                var file = File.new_for_uri(uri);
                var path = file.get_path();
                if (path != null) {
                    // If it's a directory, navigate to it
                    var file_info = file_manager.get_file_info(path);
                    if (file_info != null && file_info.get_file_type() == FileType.DIRECTORY) {
                        navigate_to(path);
                    } else {
                        // TODO: copy/move file to current directory
                    }
                }
            }
            
            Gtk.drag_finish(context, true, false, time);
        }
        
        private string view_mode_to_string(ViewMode mode) {
            switch (mode) {
                case ViewMode.ICON: return "icon";
                case ViewMode.LIST: return "list";
                case ViewMode.DETAILS: return "details";
                default: return "icon";
            }
        }
    }
}
