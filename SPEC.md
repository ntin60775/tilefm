# TileFM — Specification v1.0

## Overview
TileFM — файловый менеджер для MX Linux 23.6 XFCE с tile-based рабочими пространствами.

## Tech Stack
- **Language**: Vala 0.56+
- **Toolkit**: GTK3
- **Build**: Meson
- **License**: GPL-3.0+
- **Dependencies**: libgee-0.8, libjson-glib-1.0, libgtk-3.0

## Architecture

```
TileFM
├── Application (Gtk.Application)
│   └── MainWindow (Gtk.ApplicationWindow)
│       ├── HeaderBar (Gtk.HeaderBar)
│       │   ├── BreadcrumbPathBar
│       │   ├── ViewModeSwitcher
│       │   └── [+Tile] [Save Layout] [Layouts]
│       ├── TileContainer (Gtk.Grid-based)
│       │   └── Tile[] (each = FileView + PathBar)
│       │       ├── IconView (Gtk.IconView)
│       │       └── ListView (Gtk.TreeView)
│       ├── StatusBar (Gtk.Statusbar)
│       ├── PreviewPanel (Gtk.Box, F11 toggle)
│       └── QuickLook (Gtk.Window, Space key)
├── Core
│   ├── FileManager (async GIO operations)
│   ├── AsyncWorker ( Gee.ArrayList task queue)
│   ├── LayoutManager (JSON v2 save/load)
│   ├── UndoManager (command history)
│   ├── FileSearcher (async search)
│   ├── ClipboardManager (GDK clipboard)
│   ├── TrashManager (GIO trash)
│   ├── CustomActionsManager (user actions)
│   ├── ThumbnailManager (Tumbler D-Bus + pixbuf fallback)
│   └── ArchivePlugin (GIO archive detection)
└── Widgets
    ├── BreadcrumbPathBar (breadcrumb + editable path)
    ├── FileView (abstract base: Icon/List)
    ├── Tile (container: FileView + controls)
    ├── ContextMenu (Gtk.Menu)
    ├── QuickLook (Space key popup)
    ├── PreviewPanel (F11 sidebar)
    ├── TypeAheadSearch (Ctrl+F)
    └── BulkRenameDialog (multi-file rename)
```

## Module Interface Contracts

### FileManager (core/file_manager.vala)
```vala
public class FileManager : Object {
    public signal void error_occurred(string message);
    public signal void operation_progress(string operation, double fraction);

    public async FileInfo[] list_directory(string path) throws Error;
    public async bool copy(string src, string dst) throws Error;
    public async bool move(string src, string dst) throws Error;
    public async bool delete(string path) throws Error;
    public async bool rename(string old_path, string new_path) throws Error;
    public async bool create_directory(string path) throws Error;
    public FileInfo? get_file_info(string path);
    public string get_mime_type(string path);
    public async string[] list_archive_contents(string path) throws Error;
}
```

### Tile (tile/tile.vala)
```vala
public class Tile : Gtk.Box {
    public string current_path { get; set; }
    public FileView view { get; }
    public ViewMode view_mode { get; set; }

    public Tile(FileManager fm, string? path = null);
    public void navigate_to(string path);
    public void set_view_mode(ViewMode mode);
    public void refresh();

    public signal void path_changed(string new_path);
    public signal void view_mode_changed(ViewMode mode);
    public signal void close_requested();
}
```

### TileContainer (tile/tile_container.vala)
```vala
public class TileContainer : Gtk.Grid {
    private Gee.ArrayList<Tile> tiles;
    private FileManager file_manager;

    public void add_tile(string? path = null);
    public void remove_tile(Tile tile);
    public Tile[] get_tiles();
    public void save_layout(string name) throws Error;
    public void load_layout(string name) throws Error;
    public string[] list_layouts();
    public void delete_layout(string name);
}
```

### LayoutManager (core/layout_manager.vala)
```vala
public class LayoutManager : Object {
    public void save_layout(string name, Layout layout) throws Error;
    public Layout? load_layout(string name);
    public string[] list_layouts();
    public void delete_layout(string name);

    public signal void layout_saved(string name);
    public signal void layout_loaded(string name);
}
```

### UndoManager (core/undo_manager.vala)
```vala
public class UndoManager : Object {
    public signal void undo_status_changed(bool can_undo, bool can_redo);

    public void push_operation(UndoOperation op);
    public void undo();
    public void redo();
    public bool can_undo();
    public bool can_redo();
    public void clear();
}
```

### ClipboardManager (core/clipboard_manager.vala)
```vala
public class ClipboardManager : Object {
    public signal void clipboard_changed(string[] paths, ClipboardAction action);

    public void copy_paths(string[] paths);
    public void cut_paths(string[] paths);
    public void paste(string target_dir);
    public string[]? get_clipboard_paths(out ClipboardAction action);
}
```

### TrashManager (core/trash_manager.vala)
```vala
public class TrashManager : Object {
    public signal void trash_changed();

    public async bool move_to_trash(string path) throws Error;
    public async bool restore_from_trash(string path, string target_dir) throws Error;
    public async bool delete_permanently(string path) throws Error;
    public async FileInfo[] list_trash() throws Error;
    public void empty_trash();
}
```

### ThumbnailManager (core/thumbnail_manager.vala)
```vala
public class ThumbnailManager : Object {
    public signal void thumbnail_ready(string path, Gdk.Pixbuf pixbuf);

    public async Gdk.Pixbuf? get_thumbnail(string path, int size) throws Error;
    public void clear_cache();
    public void cache_pixbuf(string key, Gdk.Pixbuf pixbuf);
    private async Gdk.Pixbuf? load_tumbler_thumbnail(string path, int size);
    private Gdk.Pixbuf? load_pixbuf_thumbnail(string path, int size);
}
```

### ContextMenu (widgets/context_menu.vala)
```vala
public class ContextMenu : Gtk.Menu {
    public signal void open_file_request(string path);
    public signal void open_with_request(string path, AppInfo app);
    public signal void cut_request(string[] paths);
    public signal void copy_request(string[] paths);
    public signal void paste_request(string target_dir);
    public signal void rename_request(string path);
    public signal void trash_request(string[] paths);
    public signal void delete_request(string[] paths);
    public signal void copy_path_request(string path);
    public signal void open_terminal_request(string dir);
    public signal void properties_request(string path);
    public signal void bulk_rename_request(string[] paths);

    public ContextMenu(FileManager fm, ClipboardManager cb);
    public void show_file_menu(string[] paths, Gdk.EventButton? event);
    public void show_background_menu(string dir, Gdk.EventButton? event);
}
```

### QuickLook (widgets/quick_look.vala)
```vala
public class QuickLook : Gtk.Window {
    public signal void closed();
    public signal void navigate_to(string path);

    public QuickLook(FileManager fm);
    public void show_file(string path);
    public void close();
    public bool navigate_previous();
    public bool navigate_next();
}
```

### PreviewPanel (widgets/preview_panel.vala)
```vala
public class PreviewPanel : Gtk.Box {
    public signal void file_selected(string path);

    public void update_preview(string? path, FileManager fm);
    public void clear();
}
```

### BulkRenameDialog (widgets/bulk_rename_dialog.vala)
```vala
public enum RenameMode {
    FIND_REPLACE,
    NUMBERING,
    INSERT,
    REMOVE,
    EXTENSION
}

public class BulkRenameDialog : Gtk.Dialog {
    public signal void apply_rename(string[] old_paths, string[] new_names);

    public BulkRenameDialog(string[] file_paths);
    public void set_rename_mode(RenameMode mode);
    public void set_find_replace(string find, string replace);
    public void set_numbering(string prefix, int start, int padding);
    public void set_insert(string text, int position);
    public void set_remove(int position, int count);
    public void set_extension(string new_ext);
    public string[] get_preview();
}
```

### TypeAheadSearch (widgets/typeahead_search.vala)
```vala
public class TypeAheadSearch : Gtk.Box {
    public signal void search_text_changed(string text);
    public signal void search_activated(string text);
    public signal void search_cancelled();

    public void start_search(FileView view);
    public void append_char(unichar c);
    public void delete_char();
    public void activate();
    public void cancel();
    public string get_search_text();
}
```

## Data Formats

### Layout JSON v2
```json
{
    "name": "my-project",
    "version": 2,
    "created": "2026-01-15T10:30:00Z",
    "tiles": [
        {
            "path": "/home/user/Projects/my-app",
            "view_mode": "list",
            "tile_x": 0,
            "tile_y": 0,
            "tile_w": 400,
            "tile_h": 600
        },
        {
            "path": "/home/user/Projects/my-app/src",
            "view_mode": "icon",
            "tile_x": 400,
            "tile_y": 0,
            "tile_w": 400,
            "tile_h": 600
        }
    ]
}
```

### Undo Operation JSON
```json
{
    "type": "move",
    "timestamp": "2026-01-15T10:30:00Z",
    "source_paths": ["/path/file1.txt", "/path/file2.txt"],
    "destination": "/new/path/",
    "display_name": "Move 2 files to /new/path/"
}
```

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+N` | New Tile |
| `Ctrl+W` | Close Tile |
| `Ctrl+S` | Save Layout |
| `Ctrl+Q` | Quit |
| `Ctrl+Tab` | Next Tile |
| `Ctrl+Shift+Tab` | Previous Tile |
| `F11` | Toggle Preview Panel |
| `Space` | Quick Look |
| `Ctrl+F` | Typeahead Search |
| `Ctrl+Z` | Undo |
| `Ctrl+Shift+Z` | Redo |
| `Ctrl+C` | Copy |
| `Ctrl+X` | Cut |
| `Ctrl+V` | Paste |
| `Delete` | Move to Trash |
| `Shift+Delete` | Permanent Delete |
| `F2` | Rename |
| `Ctrl+R` | Refresh |

## Build Instructions
```bash
meson setup build
cd build
ninja
sudo ninja install
```

## v1.0 MVP Features
- [x] Application + MainWindow
- [x] Single Tile with directory listing
- [x] IconView + ListView switching
- [x] Breadcrumb path bar
- [x] Multiple tiles (split panes)
- [x] Basic navigation (double-click, breadcrumb)
- [x] Async directory loading (AsyncWorker)
- [x] Quick Look (Space key)
- [x] Preview Panel (F11 toggle)
- [x] Typeahead search (Ctrl+F)
- [x] Undo/Redo (UndoManager)
- [x] Bulk Rename dialog
- [x] Layout save/load (JSON v2)
- [x] Configurable shortcuts (Gtk.Application accels)
- [x] Custom Actions (user-defined commands)
- [x] Archive Plugin (detect archives, show contents)
- [x] Thumbnails (Tumbler D-Bus + pixbuf fallback)
- [x] Context menu (right-click)
- [x] Clipboard manager (copy/cut/paste)
- [x] Trash manager (move to trash, restore, empty)
- [x] File searcher (async search)
- [ ] Automount (udisk integration)

## File Structure
```
tilefm/
├── data/
│   ├── tilefm.desktop
│   └── tilefm-menu.ui
├── src/
│   ├── main.vala
│   ├── application.vala
│   ├── window.vala
│   ├── core/
│   │   ├── file_manager.vala
│   │   ├── async_worker.vala
│   │   ├── layout_manager.vala
│   │   ├── undo_manager.vala
│   │   ├── file_searcher.vala
│   │   ├── clipboard_manager.vala
│   │   ├── trash_manager.vala
│   │   ├── custom_actions.vala
│   │   ├── archive_plugin.vala
│   │   └── thumbnail_manager.vala
│   ├── view/
│   │   ├── file_view.vala
│   │   ├── icon_view.vala
│   │   └── list_view.vala
│   ├── tile/
│   │   ├── tile.vala
│   │   └── tile_container.vala
│   ├── widgets/
│   │   ├── breadcrumb_path_bar.vala
│   │   ├── context_menu.vala
│   │   ├── quick_look.vala
│   │   ├── preview_panel.vala
│   │   ├── typeahead_search.vala
│   │   └── bulk_rename_dialog.vala
│   └── meson.build
├── SPEC.md
├── README.md
├── AGENTS.md
└── meson.build
```