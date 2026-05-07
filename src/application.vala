/* TileFM — Application class
 * Manages app lifecycle, settings, global actions
 */

namespace TileFm {
    public class Application : Gtk.Application {
        public static Application instance { get; private set; }
        
        private Settings settings;
        
        public Application() {
            Object(
                application_id: "com.github.tilefm",
                flags: ApplicationFlags.HANDLES_OPEN
            );
            
            instance = this;
        }
        
        protected override void activate() {
            var window = get_or_create_window();
            window.present();
        }
        
        protected override void open(File[] files, string hint) {
            var window = get_or_create_window();
            
            foreach (var file in files) {
                var path = file.get_path();
                if (path != null) {
                    window.add_tile(path);
                }
            }
            
            window.present();
        }
        
        private MainWindow get_or_create_window() {
            var windows = this.get_windows();
            if (windows.length() > 0) {
                return windows.data as MainWindow;
            }
            return new MainWindow(this);
        }
        
        protected override void startup() {
            base.startup();
            
            // CSS styling
            var css_provider = new Gtk.CssProvider();
            css_provider.load_from_data(
                """
                .tilefm-tile {
                    border: 1px solid @borders;
                    border-radius: 4px;
                    background: @theme_base_color;
                }
                .tilefm-tile:focus {
                    border: 2px solid @theme_selected_bg_color;
                }
                .tilefm-pathbar {
                    padding: 4px 8px;
                    background: @theme_bg_color;
                    border-bottom: 1px solid @borders;
                }
                .tilefm-statusbar {
                    font-size: small;
                    padding: 2px 8px;
                }
                """
            );
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(),
                css_provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
            
            // Global actions
            var actions = new SimpleActionGroup();
            
            var new_tile_action = new SimpleAction("new-tile", null);
            new_tile_action.activate.connect(() => {
                var window = get_or_create_window();
                window.add_tile(Environment.get_home_dir());
            });
            actions.add_action(new_tile_action);
            
            var close_tile_action = new SimpleAction("close-tile", null);
            close_tile_action.activate.connect(() => {
                var window = get_or_create_window();
                window.close_active_tile();
            });
            actions.add_action(close_tile_action);
            
            this.set_accels_for_action("app.new-tile", {"<Ctrl>t"});
            this.set_accels_for_action("app.close-tile", {"<Ctrl>w"});
            this.set_accels_for_action("app.quit", {"<Ctrl>q"});
            
            this.insert_action_group("app", actions);
        }
    }
}
