/* TileFM — FileView (abstract base)
 * Common interface for all file view modes
 */

namespace TileFm {
    public abstract class FileView : Gtk.Box {
        // Signals
        public signal void item_activated(string path);
        public signal void selection_changed(string[] paths);
        public signal void context_menu_requested(string path, Gdk.EventButton event);
        
        // Protected
        protected FileManager file_manager;
        protected string current_directory;
        protected Gee.HashMap<string, FileInfo> file_map;
        
        // Drag and drop
        protected const Gtk.TargetEntry[] drag_targets = {
            { "text/uri-list", 0, 0 },
            { "text/plain", 0, 1 }
        };
        
        protected Gtk.TargetEntry[] source_targets = {
            { "text/uri-list", 0, 0 }
        };
        
        protected FileView(FileManager fm) {
            Object(
                orientation: Gtk.Orientation.VERTICAL,
                spacing: 0
            );
            
            file_manager = fm;
            file_map = new Gee.HashMap<string, FileInfo>();
            current_directory = Environment.get_home_dir();
            
            setup_drag_source();
            setup_drag_dest();
        }
        
        public abstract void set_files(string directory, FileInfo[] infos);
        public abstract string[] get_selected_paths();
        public abstract void select_all();
        public abstract void select_none();
        public abstract void refresh();
        
        protected string get_full_path(string filename) {
            return Path.build_filename(current_directory, filename);
        }
        
        protected void on_item_activated(string filename) {
            var full_path = get_full_path(filename);
            item_activated(full_path);
        }
        
        private void setup_drag_source() {
            // Subclasses should call this on their specific widget
        }
        
        private void setup_drag_dest() {
            Gtk.drag_dest_set(
                this,
                Gtk.DestDefaults.ALL,
                drag_targets,
                Gdk.DragAction.COPY | Gdk.DragAction.MOVE
            );
        }
        
        protected Gdk.Atom get_uri_list_target() {
            return Gdk.Atom.intern("text/uri-list", false);
        }
    }
}
