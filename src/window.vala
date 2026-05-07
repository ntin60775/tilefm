/* TileFM — MainWindow class
 * Contains headerbar, tile container, statusbar
 */

namespace TileFm {
    public class MainWindow : Gtk.ApplicationWindow {
        private Gtk.HeaderBar headerbar;
        private TileContainer tile_container;
        private Gtk.Statusbar statusbar;
        private FileManager file_manager;
        private LayoutManager layout_manager;
        
        public MainWindow(Application app) {
            Object(
                application: app,
                title: "TileFM",
                default_width: 1200,
                default_height: 700
            );
            
            file_manager = new FileManager();
            layout_manager = new LayoutManager();
            
            setup_ui();
            setup_actions();
            
            // Open home directory in first tile
            add_tile(Environment.get_home_dir());
        }
        
        private void setup_ui() {
            // HeaderBar
            headerbar = new Gtk.HeaderBar();
            headerbar.show_close_button = true;
            headerbar.set_title("TileFM");
            this.set_titlebar(headerbar);
            
            // Left side: +Tile button
            var new_tile_btn = new Gtk.Button.from_icon_name(
                "list-add-symbolic", Gtk.IconSize.BUTTON
            );
            new_tile_btn.tooltip_text = "New Tile (Ctrl+T)";
            new_tile_btn.clicked.connect(() => add_tile(Environment.get_home_dir()));
            headerbar.pack_start(new_tile_btn);
            
            // Layout menu
            var layout_btn = new Gtk.MenuButton();
            layout_btn.image = new Gtk.Image.from_icon_name(
                "view-grid-symbolic", Gtk.IconSize.BUTTON
            );
            layout_btn.tooltip_text = "Layouts";
            
            var layout_menu = new Menu();
            layout_menu.append("Save Layout...", "win.save-layout");
            layout_menu.append("Manage Layouts...", "win.manage-layouts");
            layout_menu.append_section(null, new Menu());
            layout_btn.set_menu_model(layout_menu);
            headerbar.pack_start(layout_btn);
            
            // Right side: View mode switcher
            var view_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            view_box.get_style_context().add_class("linked");
            
            var icon_btn = new Gtk.RadioButton.with_label_from_widget(
                null, "Icons"
            );
            icon_btn.set_mode(false);
            icon_btn.clicked.connect(() => {
                tile_container.set_view_mode_for_active(ViewMode.ICON);
            });
            
            var list_btn = new Gtk.RadioButton.with_label_from_widget(
                icon_btn, "List"
            );
            list_btn.set_mode(false);
            list_btn.clicked.connect(() => {
                tile_container.set_view_mode_for_active(ViewMode.LIST);
            });
            
            var details_btn = new Gtk.RadioButton.with_label_from_widget(
                icon_btn, "Details"
            );
            details_btn.set_mode(false);
            details_btn.clicked.connect(() => {
                tile_container.set_view_mode_for_active(ViewMode.DETAILS);
            });
            
            view_box.add(icon_btn);
            view_box.add(list_btn);
            view_box.add(details_btn);
            headerbar.pack_end(view_box);
            
            // Main content
            var vbox = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            this.add(vbox);
            
            // Tile Container
            tile_container = new TileContainer();
            tile_container.tile_count_changed.connect((count) => {
                update_statusbar();
            });
            tile_container.active_tile_changed.connect(() => {
                update_title();
            });
            vbox.pack_start(tile_container, true, true, 0);
            
            // StatusBar
            statusbar = new Gtk.Statusbar();
            statusbar.get_style_context().add_class("tilefm-statusbar");
            vbox.pack_start(statusbar, false, false, 0);
            
            update_statusbar();
        }
        
        private void setup_actions() {
            var actions = new SimpleActionGroup();
            
            var save_layout = new SimpleAction("save-layout", null);
            save_layout.activate.connect(() => {
                show_save_layout_dialog();
            });
            actions.add_action(save_layout);
            
            var manage_layouts = new SimpleAction("manage-layouts", null);
            manage_layouts.activate.connect(() => {
                show_manage_layouts_dialog();
            });
            actions.add_action(manage_layouts);
            
            this.insert_action_group("win", actions);
        }
        
        public void add_tile(string? path) {
            tile_container.add_tile(path);
        }
        
        public void close_active_tile() {
            tile_container.close_active_tile();
        }
        
        private void update_statusbar() {
            var context_id = statusbar.get_context_id("tiles");
            statusbar.pop(context_id);
            
            var tiles = tile_container.get_tiles();
            var msg = "%u tile(s)".printf(tiles.length);
            statusbar.push(context_id, msg);
        }
        
        private void update_title() {
            var active = tile_container.get_active_tile();
            if (active != null) {
                headerbar.set_subtitle(active.current_path);
            } else {
                headerbar.set_subtitle(null);
            }
        }
        
        private void show_save_layout_dialog() {
            var dialog = new Gtk.Dialog.with_buttons(
                "Save Layout",
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.USE_HEADER_BAR,
                "_Cancel", Gtk.ResponseType.CANCEL,
                "_Save", Gtk.ResponseType.ACCEPT,
                null
            );
            
            var content = dialog.get_content_area();
            var entry = new Gtk.Entry();
            entry.set_placeholder_text("Layout name...");
            entry.set_margin_top(12);
            entry.set_margin_bottom(12);
            entry.set_margin_start(12);
            entry.set_margin_end(12);
            content.add(entry);
            
            content.show_all();
            
            dialog.response.connect((response) => {
                if (response == Gtk.ResponseType.ACCEPT) {
                    var name = entry.get_text();
                    if (name.length > 0) {
                        var layout = tile_container.export_layout();
                        layout_manager.save_layout(name, layout);
                    }
                }
                dialog.destroy();
            });
            
            dialog.show();
        }
        
        private void show_manage_layouts_dialog() {
            var dialog = new Gtk.Dialog.with_buttons(
                "Manage Layouts",
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.USE_HEADER_BAR,
                "_Close", Gtk.ResponseType.CLOSE,
                null
            );
            
            var content = dialog.get_content_area();
            var list_box = new Gtk.ListBox();
            list_box.set_selection_mode(Gtk.SelectionMode.NONE);
            
            var layouts = layout_manager.list_layouts();
            if (layouts.length == 0) {
                var label = new Gtk.Label("No saved layouts");
                label.set_margin_top(24);
                label.set_margin_bottom(24);
                content.add(label);
            } else {
                foreach (var name in layouts) {
                    var row = new Gtk.ListBoxRow();
                    var hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                    hbox.set_margin_top(6);
                    hbox.set_margin_bottom(6);
                    hbox.set_margin_start(12);
                    hbox.set_margin_end(12);
                    
                    var label = new Gtk.Label(name);
                    label.set_xalign(0);
                    hbox.pack_start(label, true, true, 0);
                    
                    var load_btn = new Gtk.Button.from_icon_name(
                        "document-open-symbolic", Gtk.IconSize.BUTTON
                    );
                    load_btn.tooltip_text = "Load";
                    load_btn.clicked.connect(() => {
                        var layout = layout_manager.load_layout(name);
                        if (layout != null) {
                            tile_container.import_layout(layout);
                        }
                        dialog.destroy();
                    });
                    hbox.pack_start(load_btn, false, false, 0);
                    
                    var del_btn = new Gtk.Button.from_icon_name(
                        "edit-delete-symbolic", Gtk.IconSize.BUTTON
                    );
                    del_btn.tooltip_text = "Delete";
                    del_btn.get_style_context().add_class("destructive-action");
                    del_btn.clicked.connect(() => {
                        layout_manager.delete_layout(name);
                        row.destroy();
                    });
                    hbox.pack_start(del_btn, false, false, 0);
                    
                    row.add(hbox);
                    list_box.add(row);
                }
                
                var scrolled = new Gtk.ScrolledWindow(null, null);
                scrolled.set_min_content_height(300);
                scrolled.set_min_content_width(400);
                scrolled.add(list_box);
                content.add(scrolled);
            }
            
            content.show_all();
            
            dialog.response.connect((response) => {
                dialog.destroy();
            });
            
            dialog.show();
        }
    }
}
