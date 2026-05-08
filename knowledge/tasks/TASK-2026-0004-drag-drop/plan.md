# План: TASK-2026-0004 — Drag & Drop между плитками

## Зависимости

- От: TASK-2026-0002 (навигация), TASK-2026-0003 (selection)
- Предшествует: TASK-2026-0005 (ui-infrastructure)

## Этапы

### 1. Добавить TargetEntries для D&D в FileView

В `file_view.vala` добавить:
```vala
protected const Gtk.TargetEntry[] drop_targets = {
    { "text/uri-list", 0, 0 },  // Для файлов из других приложений
    { "x-application/tilefm-item", 0, 1 },  // Internal D&D между плитками
};
```

В `icon_view.vala` и `list_view.vala` — `Gtk.drag_dest_set()` с этими targets.

### 2. Реализовать drag_source в FileView

Добавить `Gtk.drag_source_set()` с теми же target entries.
При `drag_begin` — создать drag image из выбранных файлов.

### 3. Обработать drag_motion и drag_drop

В `icon_view.vala` и `list_view.vala`:
```vala
public bool on_drag_motion(Gdk.DragContext context, int x, int y, uint time) {
    // Проверить source, если из нашей плитки — показать индикатор
    // Если из другой плитки — подсветить drop zone
    // Вернуть true если можно drop сюда
}

public void on_drag_drop(Gdk.DragContext context, int x, int y, uint time) {
    // Определить source (внутри TileFM или внешний)
    // Определить модификаторы (Ctrl=copy, Shift=link)
    // Выполнить операцию
    // Если drop на файловый элемент — использовать его path как target
    // Если drop на пустую область — открыть родительскую папку
}
```

### 4. Обработка cross-tile D&D

Если source и target — разные плитки:
- Получить source paths из drag data
- Определить операцию: move (default), copy (Ctrl), link (Shift)
- Вызвать `file_manager.move()` или `file_manager.copy()` или создать symlink

### 5. Визуальная обратная связь

- Drop zone highlight: менять background плитки при drag_over
- Drag image: создавать через `gtk_drag_set_icon_widget()` с кастомным виджетом
- Progress: использовать `operation_progress` signal от FileManager

### 6. Undo support

После D&D операции создать `UndoMoveOperation` или `UndoCopyOperation` и добавить в UndoManager.

## Новые зависимости

- `Gdk.DragContext`
- `Gtk.drag_*` функции

## Проверки

- `ninja -C build` — без ошибок
- Ручная проверка: перетащить файлы между двумя плитками
- Проверить модификаторы Ctrl/Shift
- Проверить Undo после D&D

##估計工作量

3-4 дня