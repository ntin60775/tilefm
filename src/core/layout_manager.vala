/* TileFM — LayoutManager
 * Save/load tile layouts as JSON with grid columns
 */

namespace TileFm {
    public class Layout : Object {
        public string name { get; set; }
        public int version { get; set; default = 2; }
        public int grid_columns { get; set; default = 2; }
        public Gee.ArrayList<TileLayout> tiles { get; set; }
        
        public Layout() {
            tiles = new Gee.ArrayList<TileLayout>();
        }
    }
    
    public class TileLayout : Object {
        public string path { get; set; }
        public string view_mode { get; set; default = "icon"; }
    }
    
    public class LayoutManager : Object {
        private string layouts_dir;
        
        public LayoutManager() {
            layouts_dir = Path.build_filename(
                Environment.get_user_config_dir(), "tilefm", "layouts"
            );
            
            // Ensure directory exists
            var dir = File.new_for_path(layouts_dir);
            if (!dir.query_exists()) {
                try {
                    dir.make_directory_with_parents();
                } catch (Error e) {
                    warning("Failed to create layouts directory: %s", e.message);
                }
            }
        }
        
        public void save_layout(string name, Layout layout) {
            var builder = new Json.Builder();
            builder.begin_object();
            
            builder.set_member_name("name");
            builder.add_string_value(name);
            
            builder.set_member_name("version");
            builder.add_int_value(2);
            
            builder.set_member_name("grid_columns");
            builder.add_int_value(layout.grid_columns);
            
            builder.set_member_name("tiles");
            builder.begin_array();
            foreach (var tile in layout.tiles) {
                builder.begin_object();
                builder.set_member_name("path");
                builder.add_string_value(tile.path);
                builder.set_member_name("view_mode");
                builder.add_string_value(tile.view_mode);
                builder.end_object();
            }
            builder.end_array();
            
            builder.end_object();
            
            var generator = new Json.Generator();
            generator.set_pretty(true);
            generator.set_root(builder.get_root());
            
            var filepath = get_layout_path(name);
            try {
                generator.to_file(filepath);
            } catch (Error e) {
                warning("Failed to save layout: %s", e.message);
            }
        }
        
        public Layout? load_layout(string name) {
            var filepath = get_layout_path(name);
            var file = File.new_for_path(filepath);
            
            if (!file.query_exists()) {
                return null;
            }
            
            try {
                var parser = new Json.Parser();
                parser.load_from_file(filepath);
                
                var root = parser.get_root().get_object();
                var layout = new Layout();
                layout.name = root.get_string_member("name") ?? name;
                layout.version = (int) root.get_int_member("version");
                
                // Grid columns (v2+)
                if (root.has_member("grid_columns")) {
                    layout.grid_columns = (int) root.get_int_member("grid_columns");
                } else {
                    // v1 fallback: auto-detect from tile count
                    layout.grid_columns = 2;
                }
                
                var tiles_array = root.get_array_member("tiles");
                for (uint i = 0; i < tiles_array.get_length(); i++) {
                    var tile_obj = tiles_array.get_object_element(i);
                    var tile = new TileLayout();
                    tile.path = tile_obj.get_string_member("path") ?? Environment.get_home_dir();
                    tile.view_mode = tile_obj.get_string_member("view_mode") ?? "icon";
                    layout.tiles.add(tile);
                }
                
                return layout;
            } catch (Error e) {
                warning("Failed to load layout: %s", e.message);
                return null;
            }
        }
        
        public string[] list_layouts() {
            var layouts = new Gee.ArrayList<string>();
            
            try {
                var dir = Dir.open(layouts_dir);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (name.has_suffix(".json")) {
                        layouts.add(name.substring(0, name.length - 5));
                    }
                }
            } catch (Error e) {
                warning("Failed to list layouts: %s", e.message);
            }
            
            // Sort alphabetically
            layouts.sort((a, b) => a.collate(b));
            
            var result = new string[layouts.size];
            for (int i = 0; i < layouts.size; i++) {
                result[i] = layouts[i];
            }
            return result;
        }
        
        public void delete_layout(string name) {
            var filepath = get_layout_path(name);
            var file = File.new_for_path(filepath);
            try {
                file.delete();
            } catch (Error e) {
                warning("Failed to delete layout: %s", e.message);
            }
        }
        
        public bool has_layout(string name) {
            return FileUtils.test(get_layout_path(name), FileTest.EXISTS);
        }
        
        private string get_layout_path(string name) {
            return Path.build_filename(layouts_dir, name + ".json");
        }
    }
}
