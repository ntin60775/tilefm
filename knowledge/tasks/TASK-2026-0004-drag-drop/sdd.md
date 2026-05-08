# SDD: TASK-2026-0004 — Drag & Drop между плитками

## Контекст

D&D затрагивает FileView, IconView, ListView, Tile, TileContainer, FileManager, UndoManager. Это наиболее сложная задача с точки зрения взаимодействия компонентов — требует координации между source tile, target tile, и background FileManager operations.

## Допустимые связи

```
FileView (модификация)
  └── drop_targets: "text/uri-list" (external), "x-application/tilefm-item" (internal)
  └── абстрактные методы: on_drag_motion(), on_drag_drop(), get_selected_paths()
  └── абстрактный сигнал: items_dropped(string[] paths, string target_dir, DndAction action)

IconView (реализация)
  └── drag_source_set() для инициации D&D
  └── drag_dest_set() для приёма D&D
  └── реализация on_drag_motion, on_drag_drop

ListView (реализация)
  └── аналогично IconView

Tile (модификация)
  └── обработка drag_motion для подсветки drop zone
  └── expose get_selected_paths()

TileContainer (модификация)
  └── координация между tiles для cross-tile D&D
  └── может определять which tile is "target"

FileManager (модификация)
  └── move_async(), copy_async() — уже есть или добавить
  └── create_symlink_async()

UndoManager (модификация)
  └── push_operation(UndoMoveOperation) после успешного D&D
  └── push_operation(UndoCopyOperation) после Ctrl+D&D
```

## Недопустимые связи

- D&D не должен напрямую модифицировать TileContainer layout — только содержимое tiles
- ThumbnailManager не участвует в D&D логике
- Undo для D&D — это UndoMove/UndoCopy, не UndoRename и не UndoDelete

## Инварианты

1. Drag из tile A на tile B → показывает визуальный индикатор на tile B
2. Drop на tile B → операция выполняется в зависимости от модификаторов:
   - Plain drag → move (источник удаляется)
   - Ctrl+drag → copy (источник остаётся)
   - Shift+drag → symlink (создаёт symlink в target)
3. Drop zone — это **всегда** конкретный tile, даже если hover над пустой областью
4. Drop на файл внутри tile → использовать parent directory этого файла как target
5. Undo доступен после каждой D&D операции
6. D&D отменяется (cancel) по Escape или клику вне drop zone
7. Progress bar показывается для операций >1MB или >10 файлов

## D&D actions enum

```vala
public enum DndAction {
    MOVE,
    COPY,
    LINK,
    ASK  // Если неясно — показать dialog
}
```

## Drop targets

```vala
protected const Gtk.TargetEntry[] drop_targets = {
    { "text/uri-list", 0, 0 },     // External (from other apps, DnD files from桌面)
    { "x-application/tilefm-item", 0, 1 },  // Internal (between tiles)
};
```

## Недопустимые связи

- D&D не модифицирует layout TileContainer
- ThumbnailManager не участвует в D&D логике
- Undo D&D — только UndoMove/UndoCopy

## Инварианты (дополнительные)

8. Drag между двумя разными tiles → source tile не меняется (B не становится source)
9. Если target directory = source directory parent → **не делать ничего** (нет смысла move в тот же dir)
10. Если target существует и это file (не directory) → показать error "нельзя drop на файл"
11. Symlink не создаётся если уже существует symlink с таким именем → показать error

## Новые зависимости

- `Gdk.DragContext`
- `Gtk.drag_begin()`, `gtk_drag_set_icon_widget()`
- Все уже в GTK3

## Edge cases

1. D&D папки рекурсивно → copy/move все вложенные
2. D&D на несуществующую цель → error dialog
3. D&D прерывается (source tile closed) → операция отменяется, no partial state
4. D&D очень большого файла → progress bar, cancellation support
5. D&D между tiles в разных FileManager instances → FileManager handles cross-fs moves

## Реализация skeleton

### IconView D&D initialization

```vala
private void setup_drag_source() {
    Gtk.drag_source_set(icon_view, Gdk.ModifierType.BUTTON1_MASK, drop_targets,
                        Gdk.DragAction.MOVE | Gdk.DragAction.COPY | Gdk.DragAction.LINK);
    icon_view.drag_begin.connect((context) => {
        var selected = icon_view.get_selected_items();
        // Build list of paths from selected items
        // Store in drag context for later retrieval
    });
}

private void setup_drag_dest() {
    Gtk.drag_dest_set(icon_view, Gtk.DestDefaults.ALL, drop_targets,
                      Gdk.DragAction.MOVE | Gdk.DragAction.COPY | Gdk.DragAction.LINK);
}
```

### on_drag_motion

```vala
public bool on_drag_motion(Gdk.DragContext context, int x, int y, uint time) {
    // Check if drag is from our app (internal) or external
    // If internal and from different tile → highlight self as drop target
    // Return true to indicate we can accept the drop
}
```

### on_drag_drop

```vala
public void on_drag_drop(Gdk.DragContext context, int x, int y, uint time) {
    // Get source paths from drag context
    // Determine action (move/copy/link) from context.actions and modifier keys
    // Determine target directory
    // Execute operation
    // Clear drag state
}
```