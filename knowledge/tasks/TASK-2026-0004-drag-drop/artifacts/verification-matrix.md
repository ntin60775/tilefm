# Verification Matrix: TASK-2026-0004

## Инварианты и проверки

### Basic D&D operations

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Drag файлов из tile A в tile B | Файлы перемещаются в B, исчезают из A | Drag file from left tile to right tile | TODO |
| Ctrl+Drag | Файлы копируются, источник остаётся | Ctrl+Drag | TODO |
| Shift+Drag | Symlink создаётся в target | Shift+Drag | TODO |
| Drop zone подсвечивается | Tile highlight при hover | Drag over target tile | TODO |
| Escape отменяет | Drag cancel, ничего не происходит | Start drag → Escape | TODO |
| Drop на пустую область tile | Открыть parent dir в target tile | Drag to empty space in tile | TODO |
| Drop на файл (не папку) | Error или parent dir используется | Drag to file item in tile | TODO |

### Cross-tile coordination

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Source tile не меняется после D&D | Tile A остаётся Tile A, focus не меняется | Drag from A to B | TODO |
| Target tile обновляется | Содержимое target обновляется после drop | Drag to B → check B contents | TODO |
| D&D между 3+ tiles | Корректно работает с любой комбинацией | Drag A→B→C | TODO |

### Undo after D&D

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Undo после move | Файлы возвращаются в source | Ctrl+Z after move D&D | TODO |
| Undo после copy | Source остаётся, copy удаляется | Ctrl+Z after copy D&D | TODO |
| Undo после symlink | Symlink удаляется | Ctrl+Z after link D&D | TODO |
| Redo доступен после Undo | Ctrl+Shift+Z восстанавливает | Ctrl+Z → Ctrl+Shift+Z | TODO |

### Progress and cancellation

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Progress bar для большого файла | Progress visible | Drag 100MB+ file | TODO |
| Cancel операции | Operation cancelled | Click cancel in progress | TODO |

### Error cases

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Drop в несуществующую директорию | Error dialog | Drag to deleted target | TODO |
| Drop на файл напрямую | Error или use parent dir | Drag to .txt file | TODO |
| Duplicate symlink name | Error dialog | Shift+Drag create existing link name | TODO |
| Permission denied | Error dialog | Drag to /root without permission | TODO |

### External D&D (from other apps)

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Drop file from Nautilus/Thunar | Файл копируется в target | Drag from Thunar → TileFM | TODO |
| Drop folder from other app | Folder copied | Drag folder from desktop | TODO |

## Проверки сборки

- `ninja -C build` — без ошибок
- Vala warnings — 0
- Memory leaks — 0

## Ручные проверки для acceptance

1. [ ] Drag файлов между плитками перемещает файлы
2. [ ] Ctrl+Drag копирует файлы
3. [ ] Shift+Drag создаёт symlink
4. [ ] Drop zone подсвечивается при наведении
5. [ ] Progress показывается для больших операций
6. [ ] Undo доступен после D&D
7. [ ] Ctrl+Z отменяет D&D операцию
8. [ ] D&D из внешних приложений работает