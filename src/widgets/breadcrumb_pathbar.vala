/* TileFM — BreadcrumbPathBar
 * Combined breadcrumb + editable path bar
 */

namespace TileFm {
    public class BreadcrumbPathBar : Gtk.Box {
        // Signals
        public signal void path_changed(string new_path);
        public signal void navigate_up();
        
        // Private
        private Gtk.Stack stack;
        private Gtk.Box breadcrumb_box;
        private Gtk.Entry path_entry;
        private string current_path;
        private bool showing_entry;
        
        public BreadcrumbPathBar() {
            Object(
                orientation: Gtk.Orientation.HORIZONTAL,
                spacing: 0
            );
            
            current_path = "/";
            
            // Stack: breadcrumb | entry
            stack = new Gtk.Stack();
            stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE);
            stack.set_transition_duration(150);
            
            // Breadcrumb view
            var breadcrumb_scroll = new Gtk.ScrolledWindow(null, null);
            breadcrumb_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
            breadcrumb_scroll.set_propagate_natural_width(true);
            
            breadcrumb_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            breadcrumb_box.get_style_context().add_class("linked");
            breadcrumb_scroll.add(breadcrumb_box);
            
            stack.add_named(breadcrumb_scroll, "breadcrumb");
            
            // Editable entry view
            path_entry = new Gtk.Entry();
            path_entry.set_icon_from_icon_name(
                Gtk.EntryIconPosition.PRIMARY, "folder-symbolic"
            );
            path_entry.set_icon_from_icon_name(
                Gtk.EntryIconPosition.SECONDARY, "go-jump-symbolic"
            );
            path_entry.set_icon_tooltip_text(
                Gtk.EntryIconPosition.SECONDARY, "Go to path"
            );
            path_entry.activate.connect(() => {
                var text = path_entry.get_text();
                if (text.length > 0) {
                    // Expand ~ to home
                    if (text.has_prefix("~/")) {
                        text = Environment.get_home_dir() + text.substring(1);
                    }
                    path_changed(text);
                }
                show_breadcrumb();
            });
            path_entry.icon_release.connect((icon_pos, event) => {
                if (icon_pos == Gtk.EntryIconPosition.SECONDARY) {
                    var text = path_entry.get_text();
                    if (text.length > 0) {
                        path_changed(text);
                    }
                    show_breadcrumb();
                }
            });
            path_entry.focus_out_event.connect(() => {
                show_breadcrumb();
                return false;
            });
            path_entry.key_press_event.connect((event) => {
                if (event.keyval == Gdk.Key.Escape) {
                    show_breadcrumb();
                    return true;
                }
                return false;
            });
            
            stack.add_named(path_entry, "entry");
            
            pack_start(stack, true, true, 0);
            
            // Click to edit
            var click_gesture = new Gtk.GestureMultiPress(this);
            click_gesture.set_button(1);
            click_gesture.pressed.connect((n_press, x, y) => {
                if (n_press == 2 && !showing_entry) { // Double-click to edit
                    show_entry();
                }
            });
            
            // Ctrl+L shortcut
            this.key_press_event.connect((event) => {
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0 &&
                    event.keyval == Gdk.Key.l) {
                    show_entry();
                    return true;
                }
                return false;
            });
            
            show_breadcrumb();
            rebuild_breadcrumb();
        }
        
        public void set_path(string path) {
            if (path == current_path) {
                return;
            }
            current_path = path;
            path_entry.set_text(path);
            rebuild_breadcrumb();
        }
        
        public string get_path() {
            return current_path;
        }
        
        private void show_breadcrumb() {
            showing_entry = false;
            stack.set_visible_child_name("breadcrumb");
        }
        
        private void show_entry() {
            showing_entry = true;
            path_entry.set_text(current_path);
            stack.set_visible_child_name("entry");
            path_entry.grab_focus();
            path_entry.select_region(0, -1);
        }
        
        private void rebuild_breadcrumb() {
            // Remove old breadcrumb buttons
            foreach (var child in breadcrumb_box.get_children()) {
                breadcrumb_box.remove(child);
            }
            
            // Split path into components
            var components = new Gee.ArrayList<string>();
            var parts = current_path.split("/");
            
            // Root button
            var root_btn = new Gtk.Button.with_label("/");
            root_btn.relief = Gtk.ReliefStyle.NONE;
            root_btn.clicked.connect(() => path_changed("/"));
            root_btn.tooltip_text = "/";
            breadcrumb_box.add(root_btn);
            
            string accumulated = "";
            foreach (var part in parts) {
                if (part.length == 0) continue;
                
                accumulated += "/" + part;
                
                // Separator
                var sep = new Gtk.Label("›");
                sep.get_style_context().add_class("dim-label");
                sep.set_margin_start(4);
                sep.set_margin_end(4);
                breadcrumb_box.add(sep);
                
                // Directory button
                var btn = new Gtk.Button.with_label(part);
                btn.relief = Gtk.ReliefStyle.NONE;
                var path = accumulated; // capture for closure
                btn.clicked.connect(() => path_changed(path));
                btn.tooltip_text = path;
                breadcrumb_box.add(btn);
            }
            
            breadcrumb_box.show_all();
        }
    }
}
