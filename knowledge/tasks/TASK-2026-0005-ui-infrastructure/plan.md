# План: TASK-2026-0005 — UI Infrastructure: Настройки, Справка

## Зависимости

- От: TASK-2026-0004 (drag-drop) — требует базовой стабильности
- Не предшествует никакой задаче (финальная инфраструктура)

## Этапы

### 1. PreferencesDialog

Создать `src/widgets/preferences_dialog.vala`:
```vala
public class PreferencesDialog : Gtk.Dialog {
    private Gtk.Stack stack;
    private Gtk.ListStore shortcuts_model;  // action, shortcut, description

    public PreferencesDialog();

    private void build_general_page();
    private void build_view_page();
    private void build_shortcuts_page();
    private void build_extensions_page();
    private void build_about_page();

    public void save_settings();
    public void load_settings();
}
```

**General page:**
- `chk_confirm_delete` — подтверждать удаление
- `chk_confirm_overwrite` — подтверждать перезапись
- `chk_single_click_open` — открывать файлы одиночным кликом
- `num_open_delay` — задержка перед открытием (slider)

**View page:**
- `cmb_icon_size` — размер иконок (16/24/32/48)
- `chk_show_hidden` — показывать скрытые файлы
- `cmb_default_sort` — сортировка по умолчанию (имя/размер/дата/тип)
- `chk_sort_ascending` — порядок сортировки

**Shortcuts page:**
- `Gtk.TreeView` с колонками: Действие, Горячая клавиша
- Редактирование по двойному клику →弹出 диалог с захватом клавиши
- Кнопка "Сбросить на默认值" для каждого ряда

**Extensions page:**
- Список установленных плагинов (CustomActions, ArchivePlugin и т.д.)
- enable/disable для каждого

**About page:**
- TileFM logo
- "TileFM v1.0"
- "© 2026"
- Список авторов/контрибьюторов

### 2. Settings persistence

Создать `src/core/settings.vala`:
```vala
public class Settings : Object {
    private KeyFile config;

    public bool confirm_delete { get; set; }
    public bool confirm_overwrite { get; set; }
    public int icon_size { get; set; }
    public bool show_hidden { get; set; }
    public string default_sort { get; set; }
    // и т.д.

    public Settings();
    public void load();
    public void save();
}
```

Или использовать GSettings через `GLib.Settings`.

### 3. ShortcutsHelpDialog

Создать `src/widgets/shortcuts_help_dialog.vala`:
```vala
public class ShortcutsHelpDialog : Gtk.Dialog {
    public ShortcutsHelpDialog();
}
```

Окно/overlay размером ~600x400, scrollable с двумя колонками:
- Таблица "Клавиша" | "Действие"

Вызывается по `Ctrl+H` или кнопке `?`.

### 4. HelpDialog (F1)

Создать `src/widgets/help_dialog.vala`:
```vala
public class HelpDialog : Gtk.ScrolledWindow {
    public HelpDialog();
}
```

Простой `TextView` с форматированным текстом справки или `WebView` с HTML файлом `data/help/ru/index.html`.

Содержание:
- Введение в TileFM
- Основные концепции (плитки, layouts)
- Все горячие клавиши
- FAQ

### 5. Интеграция в Application/Window

В `application.vala`:
```vala
// Добавить menu item "Справка" с submenu:
//   ├── Справка              F1
//   ├── Горячие клавиши      Ctrl+H
//   └── О программе

// Обработка Ctrl+H -> show_shortcuts_help()
// Обработка F1 -> show_help()
```

В `window.vala` добавить кнопку `?` в toolbar.

## Новые зависимости

- `Gtk.Dialog`, `Gtk.Stack`, `Gtk.ListStore` (уже GTK3)
- `GLib.KeyFile` или `GLib.Settings` для persistence

## Проверки

- `ninja -C build` — без ошибок
- Ручная проверка: открыть настройки, изменить значение, перезапустить, убедиться что сохранилось
- Проверить справку по горячим клавишам

##估計工作量

3-4 дня