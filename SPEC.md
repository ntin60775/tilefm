# TileFM — Specification v0.1 (Skeleton)

## Overview
TileFM — файловый менеджер для MX Linux 23.6 XFCE с tile-based рабочими пространствами.

## Tech Stack
- **Language**: Vala 0.56+
- **Toolkit**: GTK3
- **Build**: Meson
- **License**: GPL-3.0+

## Architecture

```
TileFM
├── Application (Gtk.Application)
│   └── MainWindow (Gtk.ApplicationWindow)
│       ├── HeaderBar (Gtk.HeaderBar)
│       │   ├── BreadcrumbPathBar
│       │   ├── ViewModeSwitcher
│       │   └── [+Tile] [Save Layout] [Layouts]
│       ├── TileContainer (Gtk.Paned-based)
│       │   └── Tile[] (each = FileView + PathBar)
│       │       ├── IconView (Gtk.IconView)
│       │       ├── ListView (Gtk.TreeView)
│       │       └── DetailsView (Gtk.TreeView)
│       └── StatusBar (Gtk.Statusbar)
├── Core
│   ├── FileManager (GIO: GFile, GFileEnumerator)
│   ├── AsyncWorker (GLib.ThreadPool)
│   └── LayoutManager (JSON: save/load layouts)
└── Widgets
    ├── BreadcrumbPathBar (breadcrumb + editable path)
    ├── FileView (abstract: Icon/List/Details)
    └── Tile (container: FileView + controls)
```

## Module Interface Contracts

### FileManager (core/file_manager.vala)
```vala
public class FileManager : Object {
    public async FileInfo[] list_directory(string path) throws Error;
    public async bool copy(string src, string dst) throws Error;
    public async bool move(string src, string dst) throws Error;
    public async bool delete(string path) throws Error;
    public async bool rename(string old, string new) throws Error;
    public string get_mime_type(string path);
    public signal void file_changed(string path);
}
```

### Tile (tile/tile.vala)
```vala
public class Tile : Gtk.Box {
    public string current_path { get; set; }
    public FileView view { get; }
    
    public Tile(string? path = null);
    public void navigate_to(string path);
    public void set_view_mode(ViewMode mode);
    
    public signal void path_changed(string new_path);
    public signal void close_requested();
}
```

### TileContainer (tile/tile_container.vala)
```vala
public class TileContainer : Gtk.Paned {
    public void add_tile(string? path = null);
    public void remove_tile(Tile tile);
    public Tile[] get_tiles();
    public void save_layout(string name);
    public void load_layout(string name);
}
```

### LayoutManager (core/layout_manager.vala)
```vala
public class LayoutManager : Object {
    public void save_layout(string name, Layout layout);
    public Layout? load_layout(string name);
    public string[] list_layouts();
    public void delete_layout(string name);
}
```

## Data Formats

### Layout JSON
```json
{
    "name": "my-project",
    "version": 1,
    "tiles": [
        {
            "path": "/home/user/Projects/my-app",
            "view_mode": "list",
            "position": {"x": 0, "y": 0, "width": 400, "height": 600}
        },
        {
            "path": "/home/user/Projects/my-app/src",
            "view_mode": "details",
            "position": {"x": 400, "y": 0, "width": 400, "height": 600}
        }
    ]
}
```

## Build Instructions
```bash
meson setup build
cd build
ninja
sudo ninja install
```

## v1 Skeleton Features
- [x] Application + MainWindow
- [x] Single Tile with directory listing
- [x] IconView + ListView switching
- [x] Breadcrumb path bar
- [x] Multiple tiles (split panes)
- [x] Basic navigation (double-click, breadcrumb)
- [ ] Async directory loading
- [ ] Quick Look (Space)
- [ ] Preview Panel (F11)
- [ ] Typeahead search
- [ ] Undo/Redo
- [ ] Bulk Rename
- [ ] Layout save/load
- [ ] Configurable shortcuts
- [ ] Custom Actions
- [ ] Archive Plugin
- [ ] Thumbnails (Tumbler)
- [ ] Automount
