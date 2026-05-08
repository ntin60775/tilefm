# SDD: TASK-2026-0003 — Selection и файловые операции

## Контекст

Selection и файловые операции затрагивают FileView (базовый абстрактный класс), IconView, ListView, Window, ClipboardManager, FileManager, TrashManager. Множество edge cases связано с поведением выделения в GTK.

## Допустимые связи

```
FileView (модификация)
  └── абстрактные методы: select_all(), invert_selection(), clear_selection()
  └── абстрактный сигнал: selection_changed(Gee.ArrayList<string> paths)

IconView (реализация)
  └── реализует абстрактные методы через GtkIconView selection API

ListView (реализация)
  └── реализует абстрактные методы через GtkTreeSelection

Window (модификация)
  └── обработка Ctrl+A, Ctrl+I, Ctrl+Shift+A, Ctrl+Shift+C, Ctrl+Shift+N, Shift+Delete, F2
  └── подключение к active_tile.view

ClipboardManager (модификация)
  └── новый метод: copy_paths_to_clipboard(string[] paths)

FileManager (модификация)
  └── новый метод: create_folder(string parent, string name) async

TrashManager (модификация)
  └── уже есть delete_permanently(), подключить к Shift+Delete

Tile (модификация)
  └── expose rename для inline edit
```

## Недопустимые связи

- Selection не должен напрямую трогать FileManager (только через ClipboardManager для copy)
- Bulk rename не входит в эту задачу (уже есть в TASK-2026-0001 как BulkRenameDialog)
- Undo для delete/permanent delete не в этой задаче — в TASK-2026-0004 (drag-drop включает undo)

## Инварианты

1. `select_all()` выделяет **все** элементы в текущей директории (включая скрытые если show_hidden=true)
2. `invert_selection()`: выделенные → сняты, невыделенные → выделены
3. `clear_selection()` снимает **все** выделения
4. `Shift+Click` выделяет **от last_selected до current** (inclusive)
5. `Ctrl+Click` **переключает** выделение конкретного элемента (toggle)
6. При `Ctrl+A` в уже частично выделенном наборе → выделяются **все** (не добавить к существующим)
7. `Ctrl+Shift+C` копирует **полные абсолютные пути** выделенных файлов, разделённые newline
8. `Ctrl+Shift+N` создаёт папку и сразу переводит в rename mode
9. `Shift+Delete` требует подтверждения через dialog, не bypassable
10. `F2` работает только когда **ровно один** элемент выбран; если 0 или >1 — nothing happens или show dialog

## Новые зависимости

- `Gtk.MessageDialog` (для confirmation)
- `Gtk.Clipboard` (для copy_paths)
- `Gtk.Entry` (для inline rename)

## Диагностические маркеры

- `selection_changed` signal → отладка изменения выделения
- `view_mode_changed` signal при переключении view mode
- FileManager operation_progress для create_folder

## Edge cases

1. `Ctrl+A` в пустой директории → ничего не происходит (no crash)
2. `invert_selection()` в пустой директории → ничего не меняет
3. `Shift+Click` без предварительного выделения → выделить от index 0 до кликнутого
4. `F2` при множественном выделении → показать dialog "выберите один файл"
5. `Ctrl+Shift+N` при невозможности создать папку (permission denied) → показать error dialog
6. `Shift+Delete` на директории с вложенными файлами → спросить "удалить рекурсивно?"
7. Inline rename: Enter → подтвердить, Escape → отменить, duplicate name → show error и не закрывать Entry

## Реализация

### select_all() / invert_selection() в IconView

```vala
public override void select_all() {
    icon_view.select_all();
}

public override void invert_selection() {
    var items = icon_view.get_selected_items();
    var model = icon_view.get_model();
    int count = model.iter_n_children(null);
    for (int i = 0; i < count; i++) {
        var path = new Gtk.TreePath.from_indices(i);
        if (items.contains(path)) {
            icon_view.unselect_path(path);
        } else {
            icon_view.select_path(path);
        }
    }
}
```

### copy_paths_to_clipboard в ClipboardManager

```vala
public void copy_paths_to_clipboard(string[] paths) {
    var text = string.join("\n", paths);
    var clipboard = Gtk.Clipboard.get_default(Gdk.Display.get_default());
    clipboard.set_text(text);
}
```

### create_folder в FileManager

```vala
public async bool create_folder(string parent_path, string name) throws Error {
    var folder = File.new_for_path(parent_path).get_child(name);
    return yield folder.make_directory_async();
}
```