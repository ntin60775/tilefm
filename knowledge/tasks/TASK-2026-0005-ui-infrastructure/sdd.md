# SDD: TASK-2026-0005 — UI Infrastructure: Настройки, Справка

## Контекст

UI Infrastructure — окна настроек и справки. Затрагивает Application, Window, создание новых виджетов. Включает persistence настроек через GLib.Settings или KeyFile.

## Допустимые связи

```
Application (модификация)
  └── добавление MenuItem "Справка" → submenu
  └── регистрация Ctrl+H, Ctrl+, обработчиков

Window (модификация)
  └── добавление кнопки "?" в toolbar
  └── вызов show_preferences(), show_shortcuts_help()

PreferencesDialog (новый)
  └── создаёт и управляет настройками
  └── содержит: General, View, Shortcuts, Extensions, About pages

Settings (новый, singleton)
  └── GLib.Settings или KeyFile для persistence
  └── сигнал settings_changed → все订阅者 обновляются

ShortcutsHelpDialog (новый)
  └── показывает таблицу горячих клавиш
  └── может быть modal overlay или обычное dialog

HelpDialog (новый)
  └── показывает общую справку
  └── использует TextView или WebView

BreadcrumbPathBar (модификация)
  └── использует Settings для default_path_behavior

FileView subclasses (модификация)
  └── читают Settings для icon_size, show_hidden, default_sort
```

## Недопустимые связи

- PreferencesDialog не должен обращаться напрямую к FileManager, UndoManager и т.д.
- Settings не должны содержать состояние UI ( позиция window, открытые tabs) — это layout, не settings
- HelpDialog не должен открывать внешние URL (всё локально)

## Инварианты

1. Settings singleton создаётся один раз и живёт всё время жизни приложения
2. Все изменения настроек **сохраняются сразу** (не по кнопке "Apply", автосохранение)
3. При загрузке приложения Settings читаются и применяются ко всем виджетам
4. ShortcutsHelpDialog показывает **актуальные** шорткаты (читает из Application accels)
5. PreferencesDialog не закрывается по Escape (только по Cancel/OK)
6. F1 открывает HelpDialog, не ShortcutsHelpDialog
7. `?` button и `Ctrl+H` открывают ShortcutsHelpDialog

## Settings schema

```vala
public class Settings : Object {
    // General
    public bool confirm_delete { get; set; default = true; }
    public bool confirm_overwrite { get; set; default = true; }
    public bool single_click_open { get; set; default = false; }

    // View
    public int icon_size { get; set; default = 48; }  // 16/24/32/48
    public bool show_hidden { get; set; default = false; }
    public string default_sort { get; set; default = "name"; }  // name/size/date/type
    public bool sort_ascending { get; set; default = true; }

    // Behavior
    public bool confirm_trash { get; set; default = true; }
    public bool open_on_drop { get; set; default = true; }
}
```

## Pages in PreferencesDialog

### General page
- chk_confirm_delete: "Подтверждать удаление файлов"
- chk_confirm_overwrite: "Подтверждать перезапись файлов"
- chk_single_click_open: "Открывать файлы одиночным кликом"

### View page
- cmb_icon_size: ComboBoxText с значениями 16, 24, 32, 48
- chk_show_hidden: "Показывать скрытые файлы"
- cmb_default_sort: ComboBoxText name/size/date/type
- chk_sort_ascending: "Сортировка по возрастанию"

### Shortcuts page
- TreeView с columns: Действие, Горячая клавиша
- Double-click на row → modal dialog "Press key combination"
- Captures key event и сохраняет
- Кнопка "Сбросить" сбрасывает на defaults

### Extensions page
- Список доступных плагинов
- Checkbutton enable/disable для каждого

### About page
- TileFM icon/logo
- Version: "1.0"
- Description: "Tile-based file manager for MX Linux"
- Copyright: "© 2026"
- Authors: developer names

## ShortcutsHelpDialog content

```vala
private void build_shortcuts_table() {
    // Navigation
    "Alt+←", "Назад",
    "Alt+→", "Вперёд",
    "Alt+↑", "В родительскую папку",
    "Alt+Home", "Домашняя папка",
    "Ctrl+L", "Редактировать путь",
    "F5", "Обновить",

    // Selection
    "Ctrl+A", "Выделить всё",
    "Ctrl+I", "Инвертировать выделение",
    "Ctrl+Shift+A", "Снять выделение",

    // File operations
    "Ctrl+C", "Копировать",
    "Ctrl+X", "Вырезать",
    "Ctrl+V", "Вставить",
    "Ctrl+Shift+C", "Копировать путь",
    "Ctrl+Shift+N", "Создать папку",
    "Shift+Delete", "Удалить навсегда",
    "F2", "Переименовать",

    // Tiles
    "Ctrl+N", "Новая плитка",
    "Ctrl+W", "Закрыть плитку",
    "Ctrl+Tab", "Следующая плитка",

    // View
    "Ctrl+1", "Вид иконок",
    "Ctrl+2", "Вид списка",
    "F11", "Панель предпросмотра",
    "Space", "Быстрый просмотр",

    // Help
    "F1", "Справка",
    "Ctrl+H", "Горячие клавиши",
    "Ctrl+,", "Настройки",
}
```

## Новые зависимости

- `GLib.Settings` — schema-based, или `GLib.KeyFile` — simplest
- `Gtk.ComboBoxText` для dropdowns
- `Gtk.TreeView` для shortcuts table
- `Gtk.ButtonBox` для кнопок OK/Cancel

## Edge cases

1. Settings file corrupted → fallback to defaults, warn user
2. Unknown key in shortcuts → ignore during parsing
3. Duplicate shortcut assignment → highlight conflict in red, prevent save
4. Help file missing → show "Help not available" message instead of crash

## Help content (HelpDialog)

```markdown
# TileFM — Справка

## О программе
TileFM — файловый менеджер с поддержкой плиток (tiles).
Версия 1.0.

## Основные концепции

### Плитки
Каждая плитка — независимый view директории.
Можно открыть несколько плиток и перетаскивать файлы между ними.

### Навигация
- Breadcrumb bar: клик по сегменту пути
- Alt+←/→: назад/вперёд
- Ctrl+L: редактировать путь напрямую

### Layouts
Сохраняйте и загружайте наборы плиток через меню или Ctrl+S.

## Горячие клавиши
См. Ctrl+H.

## Расширения
TileFM поддерживает плагины. Управлять ими можно в настройках.
```

## Реализация Settings singleton

```vala
public class Settings : Object {
    private static Settings? _instance;
    private GLib.Settings? settings;

    public static Settings get_default() {
        if (_instance == null) {
            _instance = new Settings();
        }
        return _instance;
    }

    private Settings() {
        // Initialize GLib.Settings with app schema
        // Or use KeyFile for simplicity
    }
}
```