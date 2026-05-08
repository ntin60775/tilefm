# План: TASK-2026-0002 — Навигация и базовые операции

## Зависимости

- От: TASK-2026-0001 (MVP integration) — базовая архитектура уже есть
- Предшествует: TASK-2026-0003 (selection), TASK-2026-0004 (drag-drop)

## Этапы

### 1. Добавить HistoryNavigator в FileView или Tile

Нужна структура для хранения истории навигации per-tile:
```vala
public class HistoryNavigator : Object {
    private Gee.ArrayList<string> back_stack;
    private Gee.ArrayList<string> forward_stack;
    private string current_path;

    public signal void history_changed(string? back_target, string? forward_target);
    public void navigate_to(string path);
    public bool can_go_back();
    public bool can_go_forward();
    public string? go_back();
    public string? go_forward();
}
```

Класс `FileView` (или `Tile`) получает поле `HistoryNavigator nav_history` и методы `navigate_back()`, `navigate_forward()`, `navigate_up()`, `navigate_home()`.

### 2. Подключить горячие клавиши в Window/Application

В `application.vala` или `window.vala` добавить обработку:
- `Alt+Left` → `view.navigate_back()`
- `Alt+Right` → `view.navigate_forward()`
- `Alt+Up` → `view.navigate_up()`
- `Alt+Home` → `view.navigate_home()`
- `F5` → `view.refresh()`

Для XButton: подключиться к `Gdk.EventButton` через `Gdk.EventMask.BUTTON_PRESS_MASK` и проверять `event.button` (9 = XButton2, 8 = XButton1 в GTK). 

### 3. Реализовать редактируемый Breadcrumb

В `breadcrumb_path_bar.vala`:
- Double-click → переключить режим "view only" ↔ "editable"
- В режиме редактирования — TextEntry с текущим путём
- Enter → принять путь и вызвать navigate_to()
- Escape → отменить редактирование

Правый клик → PopupMenu с пунктами:
- "Копировать путь" → копирует путь в буфер
- "Открыть терминал здесь" → запускает терминал в этом пути

### 4. Ctrl+L обработка

В `window.vala` добавить обработку `Ctrl+L` → вызвать `breadcrumb.set_editing(true)` на активной плитке.

## Новые зависимости

- `using Gdk;` для XButton events
- `Gee.ArrayList` для стеков истории (уже есть Gee 0.8)

## Проверки

- `ninja -C build` — без ошибок
- Ручная проверка каждой горячей клавиши
- Проверка что история не сбрасывается при переключении плиток

##估計工作量

3-4 дня