# TileFM

Tile-based File Manager for MX Linux 23.6 XFCE

## Features (Skeleton v0.1)

- **Tile Workspaces**: Multiple directory tiles in one window
- **Project Layouts**: Save and restore tile arrangements
- **View Modes**: Icon, List, Details
- **Breadcrumb Path Bar**: Clickable breadcrumbs + editable path (Ctrl+L)
- **Async Directory Loading**: Non-blocking file operations
- **Drag & Drop**: Between tiles and external apps

## Tech Stack

- Vala 0.56+
- GTK3
- Meson build system
- GIO (async file operations)
- JSON-GLib (layout persistence)

## Building

### Prerequisites (MX Linux 23.6)

```bash
sudo apt update
sudo apt install -y \
    valac \
    libgtk-3-dev \
    libgee-0.8-dev \
    libjson-glib-dev \
    meson \
    ninja-build
```

### Compile

```bash
meson setup build
cd build
ninja
```

### Install

```bash
sudo ninja install
sudo update-desktop-database
```

### Run

```bash
tilefm
# or from build directory:
./tilefm
```

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+T | New Tile |
| Ctrl+W | Close Tile |
| Ctrl+L | Edit Path |
| F3 | Split View (toggle) |
| F5 | Refresh |
| Ctrl+Q | Quit |

## Project Structure

```
tilefm/
├── meson.build
├── src/
│   ├── meson.build
│   ├── main.vala
│   ├── application.vala
│   ├── window.vala
│   ├── core/
│   │   ├── file_manager.vala
│   │   ├── async_worker.vala
│   │   └── layout_manager.vala
│   ├── tile/
│   │   ├── tile.vala
│   │   └── tile_container.vala
│   ├── view/
│   │   ├── file_view.vala
│   │   ├── icon_view.vala
│   │   └── list_view.vala
│   └── widgets/
│       └── breadcrumb_pathbar.vala
├── data/
│   ├── meson.build
│   └── com.github.tilefm.desktop.in
└── README.md
```

## Roadmap

### v0.1 Skeleton (current)
- [x] Basic window with tiles
- [x] Icon/List/Details view
- [x] Breadcrumb path bar
- [x] Async directory loading
- [x] Layout save/load

### v1.0 MVP
- [ ] Typeahead search
- [ ] Quick Look (Space preview)
- [ ] Preview Panel (F11)
- [ ] Undo/Redo
- [ ] Bulk Rename
- [ ] Configurable Shortcuts
- [ ] Custom Actions (Thunar UCA compatible)
- [ ] Thumbnails (Tumbler integration)
- [ ] Archive Plugin
- [ ] Automount
- [ ] Network (GVfs)

### v2.0 Power User
- [ ] Miller Columns
- [ ] Integrated Terminal (F4)
- [ ] Tree View (F7)
- [ ] Plugin System (Lua)
- [ ] Git Integration
- [ ] Directory Comparison
- [ ] Command Palette

## License

GPL-3.0+
