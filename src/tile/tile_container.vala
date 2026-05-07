/* TileFM — TileContainer
 * Manages multiple tiles in split panes
 */

namespace TileFm {
    public class TileContainer : Gtk.Box {
        // Signals
        public signal void tile_count_changed(uint count);
        public signal void active_tile_changed();
        
        // Private
        private FileManager file_manager;
        private Gee.ArrayList<Tile> tiles;
        private Gtk.Paned main_paned;
        private Tile? active_tile;
        
        public TileContainer() {
            Object(
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0
            );
            
            file_manager = new FileManager();
            tiles = new Gee.ArrayList<Tile>();
            
            main_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            main_paned.expand = true;
            add(main_paned);
        }
        
        public void add_tile(string? path = null) {
            var tile = new Tile(file_manager, path);
            tile.close_requested.connect(() => remove_tile(tile));
            tile.path_changed.connect((new_path) => {
                if (tile == active_tile) {
                    active_tile_changed();
                }
            });
            
            // Set active on click
            tile.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
            tile.button_press_event.connect((event) => {
                set_active_tile(tile);
                return false;
            });
            
            tiles.add(tile);
            
            // Add to paned container
            if (tiles.size == 1) {
                main_paned.pack1(tile, true, false);
            } else if (tiles.size == 2) {
                main_paned.pack2(tile, true, false);
            } else {
                // For 3+ tiles, create nested panes
                var last_widget = main_paned.get_child2() ?? main_paned.get_child1();
                if (last_widget != null) {
                    var new_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
                    main_paned.remove(last_widget);
                    new_paned.pack1(last_widget, true, false);
                    new_paned.pack2(tile, true, false);
                    main_paned.pack2(new_paned, true, false);
                }
            }
            
            set_active_tile(tile);
            tile_count_changed((uint) tiles.size);
            show_all();
        }
        
        public void remove_tile(Tile tile) {
            if (tiles.size <= 1) {
                // Don't remove the last tile, just navigate to home
                tile.navigate_to(Environment.get_home_dir());
                return;
            }
            
            tiles.remove(tile);
            
            // Rebuild the paned container
            rebuild_paned();
            
            if (active_tile == tile) {
                active_tile = null;
                if (tiles.size > 0) {
                    set_active_tile(tiles[0]);
                }
            }
            
            tile.destroy();
            tile_count_changed((uint) tiles.size);
            active_tile_changed();
        }
        
        public void close_active_tile() {
            if (active_tile != null) {
                remove_tile(active_tile);
            }
        }
        
        public void set_view_mode_for_active(ViewMode mode) {
            if (active_tile != null) {
                active_tile.set_view_mode(mode);
            }
        }
        
        public void set_active_tile(Tile tile) {
            if (active_tile == tile) {
                return;
            }
            
            if (active_tile != null) {
                active_tile.set_active(false);
            }
            
            active_tile = tile;
            active_tile.set_active(true);
            active_tile_changed();
        }
        
        public Tile? get_active_tile() {
            return active_tile;
        }
        
        public Tile[] get_tiles() {
            var result = new Tile[tiles.size];
            for (int i = 0; i < tiles.size; i++) {
                result[i] = tiles[i];
            }
            return result;
        }
        
        public uint get_tile_count() {
            return (uint) tiles.size;
        }
        
        public Layout export_layout() {
            var layout = new Layout();
            foreach (var tile in tiles) {
                var tile_layout = new TileLayout();
                tile_layout.path = tile.current_path;
                tile_layout.view_mode = view_mode_to_string(tile.view_mode);
                // TODO: get actual position/size from widget
                tile_layout.position_x = 0;
                tile_layout.position_y = 0;
                tile_layout.width = 400;
                tile_layout.height = 600;
                layout.tiles.add(tile_layout);
            }
            return layout;
        }
        
        public void import_layout(Layout layout) {
            // Remove existing tiles
            while (tiles.size > 0) {
                var tile = tiles[0];
                tiles.remove_at(0);
                tile.destroy();
            }
            
            // Rebuild from layout
            foreach (var tile_layout in layout.tiles) {
                var tile = new Tile(file_manager, tile_layout.path);
                tile.close_requested.connect(() => remove_tile(tile));
                tile.path_changed.connect((new_path) => {
                    if (tile == active_tile) {
                        active_tile_changed();
                    }
                });
                
                tile.add_events(Gdk.EventMask.BUTTON_PRESS_MASK);
                tile.button_press_event.connect((event) => {
                    set_active_tile(tile);
                    return false;
                });
                
                tiles.add(tile);
                
                // Set view mode
                var mode = ViewMode.ICON;
                if (tile_layout.view_mode == "list") mode = ViewMode.LIST;
                if (tile_layout.view_mode == "details") mode = ViewMode.DETAILS;
                tile.set_view_mode(mode);
            }
            
            rebuild_paned();
            
            if (tiles.size > 0) {
                set_active_tile(tiles[0]);
            }
            
            tile_count_changed((uint) tiles.size);
            show_all();
        }
        
        private void rebuild_paned() {
            // Remove all children
            while (main_paned.get_child1() != null) {
                main_paned.remove(main_paned.get_child1());
            }
            while (main_paned.get_child2() != null) {
                main_paned.remove(main_paned.get_child2());
            }
            
            if (tiles.size == 0) {
                return;
            }
            
            if (tiles.size == 1) {
                main_paned.pack1(tiles[0], true, false);
                return;
            }
            
            if (tiles.size == 2) {
                main_paned.pack1(tiles[0], true, false);
                main_paned.pack2(tiles[1], true, false);
                return;
            }
            
            // Build nested panes for 3+ tiles
            Gtk.Paned current_paned = main_paned;
            current_paned.pack1(tiles[0], true, false);
            
            for (int i = 1; i < tiles.size; i++) {
                if (i == tiles.size - 1) {
                    current_paned.pack2(tiles[i], true, false);
                } else {
                    var new_paned = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
                    current_paned.pack2(new_paned, true, false);
                    new_paned.pack1(tiles[i], true, false);
                    current_paned = new_paned;
                }
            }
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
