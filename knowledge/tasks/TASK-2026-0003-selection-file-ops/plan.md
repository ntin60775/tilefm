# План: TASK-2026-0003 — Selection и файловые операции

## Зависимости

- От: TASK-2026-0002 (навигация) — базовая инфраструктура плиток
- Предшествует: TASK-2026-0004 (drag-drop)

## Этапы

### 1. Selection в IconView и ListView

В `file_view.vala` (базовый класс) добавить:
```vala
public abstract void select_all();
public abstract void invert_selection();
public abstract void toggle_selection(Gtk.TreePath path);
public abstract void select_range(Gtk.TreePath start, Gtk.TreePath end);
public abstract void clear_selection();
```

Реализация в `icon_view.vala` и `list_view.vala` через `GtkIconView.get_selected_items()` / `GtkTreeSelection`.

### 2. Обработка шорткатов в Window

В `window.vala` добавить обработку:
- `Ctrl+A` → `active_tile.view.select_all()`
- `Ctrl+I` → `active_tile.view.invert_selection()`
- `Ctrl+Shift+A` → `active_tile.view.clear_selection()`
- `Shift+Click` и `Ctrl+Click` — через event handlers в view

### 3. Копирование пути

Добавить в `clipboard_manager.vala`:
```vala
public void copy_paths_to_clipboard(string[] paths) {
    // Копирует пути как текст, newline-separated
    // Использовать Gtk.Clipboard.get_default(display)
}
```

Вызывать по `Ctrl+Shift+C` когда есть выделенные файлы.

### 4. Создание папки

Добавить в `file_manager.vala`:
```vala
public async bool create_folder(string parent_path, string name) throws Error;
```

По `Ctrl+Shift+N`:
1. Вызвать `file_manager.create_folder(current_dir, "New Folder")`
2. Если успешно — добавить в модель и сразу вызвать `start_rename()` для новой папки

### 5. Permanent delete

В `trash_manager.vala` уже есть `delete_permanently()`. По `Shift+Delete`:
1. Показать `Gtk.MessageDialog` с подтверждением: "Удалить навсегда? Это действие необратимо."
2. Если подтверждено — вызвать `trash_manager.delete_permanently(paths)`

### 6. F2 — inline rename

Реализовать в `file_view.vala`:
```vala
public abstract void start_rename(Gtk.TreePath path);
```

В `icon_view.vala` и `list_view.vala` — создать редактируемый Entry поверх виджета, позиционированный по элементу.

## Новые зависимости

- `Gtk.MessageDialog` для подтверждения permanent delete
- `Gtk.Clipboard` для копирования путей

## Проверки

- `ninja -C build` — без ошибок
- Ручная проверка каждого шортката

##估計工作量

2-3 дня