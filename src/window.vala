/* TileFM -- MainWindow class
 * Contains headerbar with grid controls, tile container, statusbar.
 * Integrates QuickLook (Space), Preview Panel (F11), Search (Ctrl+F),
 * Undo/Redo (Ctrl+Z / Ctrl+Shift+Z), and Archive/Bulk Rename.
 */

namespace TileFm {
    public class MainWindow : Gtk.ApplicationWindow {
        private Gtk.HeaderBar headerbar;
        private TileContainer tile_container;
        private Gtk.Statusbar statusbar;
        private FileManager file_manager;
        private LayoutManager layout_manager;
        private Gtk.Label grid_label;

        // QuickLook integration
        private QuickLook quick_look;

        public MainWindow(Application app) {
            Object(
                application: app,
                title: "TileFM",
                default_width: 1400,
                default_height: 900
            );

            file_manager = new FileManager();
            layout_manager = new LayoutManager();

            // Initialize QuickLook
            quick_look = new QuickLook(file_manager);

            setup_ui();
            setup_actions();
            setup_keyboard_shortcuts();
            setup_context_menu_integration();

            // Open home directory in first tile
            add_tile(Environment.get_home_dir());

            this.show_all();
        }

        private void setup_ui() {
            // HeaderBar
            headerbar = new Gtk.HeaderBar();
            headerbar.show_close_button = true;
            headerbar.set_title("TileFM");
            this.set_titlebar(headerbar);

            // === LEFT SIDE ===

            // +Tile button
            var new_tile_btn = new Gtk.Button.from_icon_name(
                "list-add-symbolic", Gtk.IconSize.BUTTON
            );
            new_tile_btn.tooltip_text = "New Tile (Ctrl+T)";
            new_tile_btn.clicked.connect(() => add_tile(Environment.get_home_dir()));
            headerbar.pack_start(new_tile_btn);

            // Grid preset buttons
            var grid_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            grid_box.get_style_context().add_class("linked");

            var grid_1 = new Gtk.Button.with_label("1");
            grid_1.tooltip_text = "1 column";
            grid_1.clicked.connect(() => tile_container.set_grid_preset(1));

            var grid_2 = new Gtk.Button.with_label("2");
            grid_2.tooltip_text = "2 columns";
            grid_2.clicked.connect(() => tile_container.set_grid_preset(2));

            var grid_3 = new Gtk.Button.with_label("3");
            grid_3.tooltip_text = "3 columns";
            grid_3.clicked.connect(() => tile_container.set_grid_preset(3));

            var grid_4 = new Gtk.Button.with_label("4");
            grid_4.tooltip_text = "4 columns";
            grid_4.clicked.connect(() => tile_container.set_grid_preset(4));

            grid_box.add(grid_1);
            grid_box.add(grid_2);
            grid_box.add(grid_3);
            grid_box.add(grid_4);
            headerbar.pack_start(grid_box);

            // Grid label
            grid_label = new Gtk.Label("2 cols");
            grid_label.get_style_context().add_class("dim-label");
            grid_label.set_margin_start(4);
            headerbar.pack_start(grid_label);

            // Layout menu
            var layout_btn = new Gtk.MenuButton();
            layout_btn.image = new Gtk.Image.from_icon_name(
                "view-grid-symbolic", Gtk.IconSize.BUTTON
            );
            layout_btn.tooltip_text = "Layouts";

            var layout_menu = new Menu();
            layout_menu.append("Save Layout...", "win.save-layout");
            layout_menu.append("Manage Layouts...", "win.manage-layouts");
            layout_btn.set_menu_model(layout_menu);
            headerbar.pack_start(layout_btn);

            // === RIGHT SIDE ===

            // View mode switcher
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

            // Search button
            var search_btn = new Gtk.ToggleButton();
            search_btn.image = new Gtk.Image.from_icon_name(
                "edit-find-symbolic", Gtk.IconSize.BUTTON
            );
            search_btn.tooltip_text = "Toggle Search (Ctrl+F)";
            search_btn.clicked.connect(() => {
                if (search_btn.active) {
                    tile_container.show_search_for_active();
                } else {
                    tile_container.hide_search_for_active();
                }
            });
            headerbar.pack_end(search_btn);

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
            tile_container.grid_columns_changed.connect((cols) => {
                grid_label.set_text("%d cols".printf(cols));
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
            save_layout.activate.connect(() => show_save_layout_dialog());
            actions.add_action(save_layout);

            var manage_layouts = new SimpleAction("manage-layouts", null);
            manage_layouts.activate.connect(() => show_manage_layouts_dialog());
            actions.add_action(manage_layouts);

            this.insert_action_group("win", actions);
        }

        /**
         * Wire up context menu signals for archive extraction,
         * bulk rename, etc.
         */
        private void setup_context_menu_integration() {
            // Context menu signals are connected per-tile in the tile creation.
            // The Tile emits context_menu_request signals which we handle here.
        }

        /**
         * Show the bulk rename dialog for the given file paths.
         */
        private void show_bulk_rename_dialog(string[] paths) {
            var dialog = new BulkRenameDialog(this, paths);
            dialog.apply_rename.connect((old_paths, new_names) => {
                apply_bulk_rename(old_paths, new_names);
            });
            dialog.show();
        }

        /**
         * Apply bulk rename by renaming each file individually.
         */
        private void apply_bulk_rename(string[] old_paths, string[] new_names) {
            for (int i = 0; i < old_paths.length; i++) {
                if (old_paths[i] == null || new_names[i] == null) continue;
                string old_name = Path.get_basename(old_paths[i]);
                if (old_name == new_names[i]) continue; // unchanged

                var parent = File.new_for_path(old_paths[i]).get_parent();
                if (parent == null) continue;
                string new_path = Path.build_filename(parent.get_path(), new_names[i]);

                try {
                    var file = File.new_for_path(old_paths[i]);
                    file.move(File.new_for_path(new_path), FileCopyFlags.NONE);
                } catch (Error e) {
                    warning("Failed to rename '%s' to '%s': %s", old_paths[i], new_names[i], e.message);
                }
            }
            // Refresh all tiles to show new names
            tile_container.refresh_all();
        }

        private void setup_keyboard_shortcuts() {
            this.key_press_event.connect((event) => {
                // Check if any modal dialog is active - if so, let it handle keys
                if (has_modal_dialog()) {
                    return false;
                }

                // Check if QuickLook is visible - let it handle its own keys
                if (quick_look.get_visible()) {
                    // QuickLook handles Escape, Space, arrows internally.
                    // We only intercept Space to close it (QuickLook's own handler does this).
                    return false;
                }

                // Check if search is active in the current tile
                if (tile_container.is_search_active_for_active()) {
                    // Let the search widget handle its own keys (Escape, Up, Down).
                    // Don't intercept Ctrl combos though.
                    if ((event.state & Gdk.ModifierType.CONTROL_MASK) == 0) {
                        return false;
                    }
                }

                // Ctrl+ modifiers
                if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    // Check for Shift as well (for Ctrl+Shift+Z redo)
                    bool has_shift = (event.state & Gdk.ModifierType.SHIFT_MASK) != 0;

                    switch (event.keyval) {
                        case Gdk.Key.@1:
                            tile_container.set_grid_preset(1);
                            return true;
                        case Gdk.Key.@2:
                            tile_container.set_grid_preset(2);
                            return true;
                        case Gdk.Key.@3:
                            tile_container.set_grid_preset(3);
                            return true;
                        case Gdk.Key.@4:
                            tile_container.set_grid_preset(4);
                            return true;
                        case Gdk.Key.t:
                            add_tile(Environment.get_home_dir());
                            return true;
                        case Gdk.Key.w:
                            close_active_tile();
                            return true;
                        case Gdk.Key.f:
                            tile_container.show_search_for_active();
                            return true;
                        case Gdk.Key.r:
                            tile_container.refresh_all();
                            return true;
                        case Gdk.Key.z:
                            if (has_shift) {
                                // Ctrl+Shift+Z = Redo
                                tile_container.redo_for_active();
                            } else {
                                // Ctrl+Z = Undo
                                tile_container.undo_for_active();
                            }
                            return true;
                        case Gdk.Key.y:
                            // Ctrl+Y = Redo (alternative)
                            tile_container.redo_for_active();
                            return true;
                        default:
                            break;
                    }
                }

                // F-keys
                switch (event.keyval) {
                    case Gdk.Key.space:
                        // Space = QuickLook for selected file
                        var selected = tile_container.get_selected_file_for_active();
                        if (selected != null) {
                            quick_look.show_file(selected);
                            return true;
                        }
                        return false;
                    case Gdk.Key.F3:
                        // F3 = Split view: clone active tile to a new tile
                        clone_active_tile();
                        return true;
                    case Gdk.Key.F5:
                        tile_container.refresh_all();
                        return true;
                    case Gdk.Key.F11:
                        // F11 = Toggle preview panel for active tile
                        tile_container.toggle_preview_for_active();
                        return true;
                    default:
                        break;
                }

                return false;
            });
        }

        /**
         * Check if any modal dialog is currently active.
         */
        private bool has_modal_dialog() {
            var toplevels = Gtk.Window.list_toplevels();
            foreach (var w in toplevels) {
                if (w is Gtk.Dialog && w.get_visible() && w != this) {
                    // Check if it's modal and transient for this window
                    var dialog = w as Gtk.Dialog;
                    if (dialog.get_modal() && dialog.get_transient_for() == this) {
                        return true;
                    }
                }
            }
            return false;
        }

        public void add_tile(string? path) {
            tile_container.add_tile(path);
        }

        public void close_active_tile() {
            tile_container.close_active_tile();
        }

        public void set_grid_columns(int cols) {
            tile_container.set_grid_preset(cols);
        }

        /**
         * Clone the active tile: open a new tile with the same path.
         */
        private void clone_active_tile() {
            var active = tile_container.get_active_tile();
            if (active != null) {
                add_tile(active.current_path);
            }
        }

        private void update_statusbar() {
            var context_id = statusbar.get_context_id("tiles");
            statusbar.pop(context_id);

            var tiles = tile_container.get_tiles();
            var msg = "%u tile(s) | Grid: %d cols".printf(
                tiles.length, tile_container.grid_columns
            );
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
            content.set_spacing(8);
            content.set_margin_top(12);
            content.set_margin_bottom(12);
            content.set_margin_start(12);
            content.set_margin_end(12);

            var entry = new Gtk.Entry();
            entry.set_placeholder_text("Layout name...");
            entry.set_activates_default(true);
            content.add(entry);

            var info = new Gtk.Label("Saves tile paths, view modes and grid columns.");
            info.set_line_wrap(true);
            info.get_style_context().add_class("dim-label");
            info.set_margin_top(4);
            content.add(info);

            content.show_all();

            dialog.set_default_response(Gtk.ResponseType.ACCEPT);

            dialog.response.connect((response) => {
                if (response == Gtk.ResponseType.ACCEPT) {
                    var name = entry.get_text();
                    if (name.length > 0) {
                        var layout = tile_container.export_layout();
                        layout_manager.save_layout(name, layout);
                        update_statusbar();
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
            dialog.set_default_size(450, 350);

            var content = dialog.get_content_area();
            content.set_spacing(8);
            content.set_margin_top(8);
            content.set_margin_bottom(8);
            content.set_margin_start(12);
            content.set_margin_end(12);

            var layouts = layout_manager.list_layouts();
            if (layouts.length == 0) {
                var empty_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
                empty_box.set_valign(Gtk.Align.CENTER);
                empty_box.set_halign(Gtk.Align.CENTER);

                var icon = new Gtk.Image.from_icon_name(
                    "folder-open-symbolic", Gtk.IconSize.DIALOG
                );
                icon.set_pixel_size(48);
                icon.get_style_context().add_class("dim-label");
                empty_box.add(icon);

                var label = new Gtk.Label("No saved layouts");
                label.get_style_context().add_class("dim-label");
                empty_box.add(label);

                var hint = new Gtk.Label("Use 'Save Layout' to create one.");
                hint.get_style_context().add_class("dim-label");
                hint.set_margin_top(4);
                empty_box.add(hint);

                content.add(empty_box);
            } else {
                var list_box = new Gtk.ListBox();
                list_box.set_selection_mode(Gtk.SelectionMode.NONE);

                foreach (var name in layouts) {
                    var row = new Gtk.ListBoxRow();
                    var hbox = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
                    hbox.set_margin_top(6);
                    hbox.set_margin_bottom(6);
                    hbox.set_margin_start(12);
                    hbox.set_margin_end(12);

                    var icon = new Gtk.Image.from_icon_name(
                        "view-grid-symbolic", Gtk.IconSize.BUTTON
                    );
                    hbox.pack_start(icon, false, false, 0);

                    var label = new Gtk.Label(name);
                    label.set_xalign(0);
                    label.set_hexpand(true);
                    hbox.pack_start(label, true, true, 0);

                    var load_btn = new Gtk.Button.from_icon_name(
                        "document-open-symbolic", Gtk.IconSize.BUTTON
                    );
                    load_btn.tooltip_text = "Load Layout";
                    load_btn.clicked.connect(() => {
                        var layout = layout_manager.load_layout(name);
                        if (layout != null) {
                            tile_container.import_layout(layout);
                        }
                    });
                    hbox.pack_start(load_btn, false, false, 0);

                    var del_btn = new Gtk.Button.from_icon_name(
                        "edit-delete-symbolic", Gtk.IconSize.BUTTON
                    );
                    del_btn.tooltip_text = "Delete Layout";
                    del_btn.get_style_context().add_class("destructive-action");
                    del_btn.clicked.connect(() => {
                        layout_manager.delete_layout(name);
                        row.destroy();
                        if (list_box.get_children().length() == 0) {
                            dialog.destroy();
                            show_manage_layouts_dialog();
                        }
                    });
                    hbox.pack_start(del_btn, false, false, 0);

                    row.add(hbox);
                    list_box.add(row);
                }

                var scrolled = new Gtk.ScrolledWindow(null, null);
                scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
                scrolled.set_vexpand(true);
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
