# SDD: TASK-2026-0002 — Навигация и базовые операции

## Контекст

Архитектурно сложная задача: навигация требует введения нового компонента `HistoryNavigator` и модификации нескольких существующих модулей. Затрагивает: FileView (базовый абстрактный класс), IconView, ListView, Tile, TileContainer, Window, Application, BreadcrumbPathBar.

## Допустимые связи

```
HistoryNavigator (новый)
  └── используется Tile и FileView (композиция, one-per-tile)
  └── сигнал history_changed → Tile → обновляет UI

FileView (модификация)
  └── получает HistoryNavigator nav_history
  └── методы: navigate_back(), navigate_forward(), navigate_up(), navigate_home(), refresh()

Tile (модификация)
  └── содержит HistoryNavigator
  └── expose методов навигации из FileView наружу

Window (модификация)
  └── обработка Alt+←/→/↑, Alt+Home, F5, Ctrl+L
  └── XButton events через event filter

Application (модификация)
  └── регистрация горячих клавиш через Gtk.Application.set_accels_for_action()

BreadcrumbPathBar (модификация)
  └── режим "editable" (double-click, Ctrl+L)
  └── правый клик → popup menu
  └── сигнал path_edit_confirmed → Tile.navigate_to()
```

## Недопустимые связи

- HistoryNavigator не должен напрямую обращаться к FileManager или делать I/O
- HistoryNavigator не должен обращаться к UndoManager (история навигации ≠ история операций)
- BreadcrumbPathBar не должен сам делать navigate_to — только сигналить, решение принимает Tile/Window
- Навигационные шорткаты не должны работать глобально когда фокус в TextEntry или Dialog

## Инварианты

1. Каждая плитка имеет **независимую** историю навигации
2. При переключении плиток история **не сливается** и не сбрасывается
3. `navigate_back()` вызывается только когда `can_go_back() == true`
4. `navigate_forward()` вызывается только когда `can_go_forward() == true`
5. При навигации в новую директорию через `navigate_to()` — **forward стек очищается**
6. Breadcrumb в режиме редактирования **не реагирует** на клики мыши по сегментам пути
7. XButton events работают **только** когда фокус на виджете внутри Tile, не в dialog/modal

## Новые зависимости

- `Gdk` (для XButton events, event masks)
- `Gee.ArrayList<string>` для back_stack и forward_stack
- Нет новых внешних зависимостей (всё уже в GTK3, Gee 0.8)

## Диагностические маркеры

- `history_changed` signal — отладка переключения состояния кнопок назад/вперёд
- Логи в `navigate_to()` — трейс навигации: "Navigating to: {path}"
- Проверка: back_stack/forward_stack size после каждой навигации (debug build)

## Edge cases

1. `navigate_back()` на пустом back_stack → ничего не делать, не падать
2. `navigate_forward()` на пустом forward_stack → ничего не делать
3. Навигация в тот же path где уже находимся → back_stack не растёт (deduplicate)
4. Быстрые повторные нажатия Alt+← → debounce 100ms чтобы избежать двойной навигации
5. Перетаскивание файлов во время навигации → навигация не блокирует drag/drop
6. HistoryNavigator живорождён при создании Tile, умирает при destroy Tile

## Реализация

### HistoryNavigator

```vala
public class HistoryNavigator : Object {
    private Gee.ArrayList<string> back_stack;
    private Gee.ArrayList<string> forward_stack;
    private string current_path;

    public signal void history_changed(string? back_target, string? forward_target);

    public HistoryNavigator(string initial_path) {
        this.current_path = initial_path;
        this.back_stack = new Gee.ArrayList<string>();
        this.forward_stack = new Gee.ArrayList<string>();
    }

    public void navigate_to(string path) {
        if (path == current_path) return;
        if (back_stack.is_empty || back_stack[back_stack.size - 1] != current_path) {
            back_stack.add(current_path);
        }
        forward_stack.clear();
        current_path = path;
        history_changed(peek_back(), peek_forward());
    }

    public bool can_go_back() { return !back_stack.is_empty; }
    public bool can_go_forward() { return !forward_stack.is_empty; }

    public string? go_back() {
        if (!can_go_back()) return null;
        forward_stack.add(current_path);
        current_path = back_stack.remove_at(back_stack.size - 1);
        history_changed(peek_back(), peek_forward());
        return current_path;
    }

    public string? go_forward() {
        if (!can_go_forward()) return null;
        back_stack.add(current_path);
        current_path = forward_stack.remove_at(forward_stack.size - 1);
        history_changed(peek_back(), peek_forward());
        return current_path;
    }

    private string? peek_back() {
        return back_stack.is_empty ? null : back_stack[back_stack.size - 1];
    }

    private string? peek_forward() {
        return forward_stack.is_empty ? null : forward_stack[forward_stack.size - 1];
    }
}
```

### XButton handling

В конструкторе Window/FileView подключить обработку:
```vala
var event_controller = new Gtk.EventControllerKey();
event_controller.key_pressed.connect((keyval, keycode, state) => {
    // XButton1 = 8, XButton2 = 9
});
```

Или через `Gtk.Widget.add_events()` с `Gdk.EventMask.BUTTON_PRESS_MASK` и `button_press_event`.