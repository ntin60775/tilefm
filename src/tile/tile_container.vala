/* TileFM -- TileContainer
 * Grid-based tile layout with configurable columns
 * Replaces Gtk.Paned with Gtk.Grid for true 2D tile arrangement
 */

namespace TileFm {
    public class TileContainer : Gtk.Grid {
        // Signals
        public signal void tile_count_changed(uint count);
        public signal void active_tile_changed();
        public signal void grid_columns_changed(int columns);

        // Properties
        public int grid_columns {
            get { return _grid_columns; }
            set {
                if (_grid_columns != value) {
                    _grid_columns = value.clamp(1, 4);
                    reflow_grid();
                    grid_columns_changed(_grid_columns);
                }
            }
        }
        private int _grid_columns = 2;

        // Private
        private FileManager file_manager;
        private Gee.ArrayList<Tile> tiles;
        private Gtk.ScrolledWindow scrolled;
        private Gtk.Grid content_grid;
        private Tile? active_tile;

        public TileContainer() {
            Object(
                row_spacing: 4,
                column_spacing: 4,
                margin: 4
            );

            file_manager = new FileManager();
            tiles = new Gee.ArrayList<Tile>();

            // Scrolled window for the grid
            scrolled = new Gtk.ScrolledWindow(null, null);
            scrolled.set_policy(
                Gtk.PolicyType.AUTOMATIC,
                Gtk.PolicyType.AUTOMATIC
            );
            scrolled.expand = true;

            // Content grid -- where tiles actually live
            content_grid = new Gtk.Grid();
            content_grid.row_spacing = 4;
            content_grid.column_spacing = 4;
            content_grid.set_column_homogeneous(true);
            content_grid.set_row_homogeneous(true);
            content_grid.expand = true;
            content_grid.vexpand = true;
            content_grid.hexpand = true;

            scrolled.add(content_grid);
            attach(scrolled, 0, 0, 1, 1);
        }

        // Grid configuration presets
        public void set_grid_preset(int columns) {
            grid_columns = columns.clamp(1, 4);
        }

        public void next_grid_preset() {
            int next = _grid_columns + 1;
            if (next > 4) next = 1;
            grid_columns = next;
        }

        public string get_grid_label() {
            return "%d column(s)".printf(_grid_columns);
        }

        // Tile management
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
            content_grid.attach(tile, tiles.size - 1, 0, 1, 1);

            reflow_grid();
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
            content_grid.remove(tile);

            if (active_tile == tile) {
                active_tile = null;
                if (tiles.size > 0) {
                    set_active_tile(tiles[0]);
                }
            }

            tile.destroy();

            reflow_grid();
            tile_count_changed((uint) tiles.size);
            active_tile_changed();
        }

        public void close_active_tile() {
            if (active_tile != null) {
                remove_tile(active_tile);
            }
        }

        public void close_all_tiles() {
            // Keep first, navigate rest to home
            for (int i = tiles.size - 1; i > 0; i--) {
                remove_tile(tiles[i]);
            }
            if (tiles.size > 0) {
                tiles[0].navigate_to(Environment.get_home_dir());
            }
        }

        public void set_view_mode_for_active(ViewMode mode) {
            if (active_tile != null) {
                active_tile.change_view_mode(mode);
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

        // Refresh all tiles
        public void refresh_all() {
            foreach (var tile in tiles) {
                tile.refresh();
            }
        }

        // ── Preview Panel ─────────────────────────────────────────

        /**
         * Toggle the preview panel for the active tile.
         */
        public void toggle_preview_for_active() {
            if (active_tile != null) {
                active_tile.toggle_preview();
            }
        }

        // ── Search ────────────────────────────────────────────────

        /**
         * Show the typeahead search widget for the active tile.
         */
        public void show_search_for_active() {
            if (active_tile != null) {
                active_tile.show_search();
            }
        }

        /**
         * Hide the typeahead search widget for the active tile.
         */
        public void hide_search_for_active() {
            if (active_tile != null) {
                active_tile.hide_search();
            }
        }

        /**
         * Check if search is active in the active tile.
         */
        public bool is_search_active_for_active() {
            if (active_tile != null) {
                return active_tile.is_search_active();
            }
            return false;
        }

        // ── Undo / Redo ───────────────────────────────────────────

        /**
         * Perform undo in the active tile's undo manager.
         */
        public void undo_for_active() {
            if (active_tile != null) {
                active_tile.undo();
            }
        }

        /**
         * Perform redo in the active tile's undo manager.
         */
        public void redo_for_active() {
            if (active_tile != null) {
                active_tile.redo();
            }
        }

        // ── Selection ─────────────────────────────────────────────

        /**
         * Get the first selected file path from the active tile.
         * Returns null if no tile is active or nothing is selected.
         */
        public string? get_selected_file_for_active() {
            if (active_tile != null) {
                return active_tile.get_selected_file_path();
            }
            return null;
        }

        /**
         * Get all selected file paths from the active tile.
         */
        public string[] get_selected_files_for_active() {
            if (active_tile != null) {
                return active_tile.get_selected_file_paths();
            }
            return new string[0];
        }

        // ── Layout persistence ────────────────────────────────────

        public Layout export_layout() {
            var layout = new Layout();
            layout.grid_columns = _grid_columns;
            foreach (var tile in tiles) {
                var tile_layout = new TileLayout();
                tile_layout.path = tile.current_path;
                tile_layout.view_mode = view_mode_to_string(tile.view_mode);
                layout.tiles.add(tile_layout);
            }
            return layout;
        }

        public void import_layout(Layout layout) {
            // Remove existing tiles
            while (tiles.size > 0) {
                var tile = tiles[0];
                tiles.remove_at(0);
                content_grid.remove(tile);
                tile.destroy();
            }
            active_tile = null;

            // Restore grid columns
            if (layout.grid_columns > 0) {
                _grid_columns = layout.grid_columns.clamp(1, 4);
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
                tile.change_view_mode(mode);
            }

            reflow_grid();

            if (tiles.size > 0) {
                set_active_tile(tiles[0]);
            }

            tile_count_changed((uint) tiles.size);
            grid_columns_changed(_grid_columns);
            show_all();
        }

        // Reflow tiles into the grid based on column count
        private void reflow_grid() {
            // Remove all tiles from grid
            foreach (var tile in tiles) {
                if (tile.get_parent() == content_grid) {
                    content_grid.remove(tile);
                }
            }

            // Re-attach in grid positions
            for (int i = 0; i < tiles.size; i++) {
                int row = i / _grid_columns;
                int col = i % _grid_columns;
                content_grid.attach(tiles[i], col, row, 1, 1);
            }

            content_grid.show_all();
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
