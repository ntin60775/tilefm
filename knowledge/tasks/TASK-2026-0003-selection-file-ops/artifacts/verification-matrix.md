# Verification Matrix: TASK-2026-0003

## Инварианты и проверки

### Selection operations

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Ctrl+A выделяет все файлы | Все файлы выделены | Ctrl+A → сравнить count | TODO |
| Ctrl+A в пустой директории | No crash | Ctrl+A в empty dir | TODO |
| Ctrl+I инвертирует выделение | 10 файлов, выделено 3 → выделено 7 | Ctrl+I check | TODO |
| Ctrl+I в пустой директории | No crash | Ctrl+I в empty dir | TODO |
| Ctrl+Shift+A снимает выделение | Все сняты | Ctrl+Shift+A → count selected = 0 | TODO |
| Shift+Click выделяет диапазон | От последнего к кликнутому | Shift+Click на 5-м элементе | TODO |
| Shift+Click без предварительного | От index 0 до кликнутого | Click, then Shift+Click 5 | TODO |
| Ctrl+Click переключает | Toggle single item | Ctrl+Click на выделенном → снят | TODO |

### Copy path

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Ctrl+Shift+C копирует полный путь | Ctrl+V в терминале показывает абсолютный путь | Ctrl+Shift+C → Ctrl+V | TODO |
| Множественный выбор | newline-separated | Выделить 3 файла → Ctrl+Shift+C → Ctrl+V | TODO |
| Ничего не выбрано | Ничего не копируется, no error | Ctrl+Shift+C без selection | TODO |

### Create folder

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Ctrl+Shift+N создаёт New Folder | Папка создаётся, сразу rename mode | Ctrl+Shift+N | TODO |
| Папка уже существует | Error dialog | Ctrl+Shift+N → вручную создать New Folder → повторить | TODO |
| Permission denied | Error dialog с описанием | Ctrl+Shift+N в /root без sudo | TODO |
| Enter подтверждает rename | Папка переименована | Ctrl+Shift+N → type "Test" → Enter | TODO |
| Escape отменяет rename | Папка остаётся "New Folder" | Ctrl+Shift+N → type "Test" → Escape | TODO |

### Permanent delete

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Shift+Delete показывает confirm | Dialog с "Удалить навсегда?" | Shift+Delete на файле | TODO |
| Cancel отменяет delete | Файл не удалён | Нажать Cancel в dialog | TODO |
| Confirm удаляет навсегда | Файл удалён, не в корзине | Нажать Delete в confirm dialog | TODO |
| Папка с вложенными | Confirm рекурсивно | Shift+Delete на папке с файлами | TODO |

### F2 rename

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| F2 при 1 выделенном | Inline entry появляется | F2 | TODO |
| F2 при >1 выделенном | Nothing happens или dialog | Выделить 2 файла → F2 | TODO |
| F2 при 0 выделенных | Nothing happens | F2 без selection | TODO |
| Дублирующее имя | Error, не закрывать entry | Rename → existing name | TODO |
| Enter → подтвердить | Имя изменено | F2 → type "newname" → Enter | TODO |
| Escape → отменить | Имя не изменено | F2 → type "newname" → Escape | TODO |

## Проверки сборки

- `ninja -C build` — без ошибок
- Vala warnings — 0
- Memory leaks — 0

## Ручные проверки для acceptance

1. [ ] `Ctrl+A` выделяет все файлы
2. [ ] `Ctrl+I` инвертирует выделение
3. [ ] `Shift+Click` выделяет диапазон
4. [ ] `Ctrl+Click` переключает выделение
5. [ ] `Ctrl+Shift+A` снимает всё выделение
6. [ ] `Ctrl+Shift+C` копирует путь выбранных файлов
7. [ ] `Ctrl+Shift+N` создаёт папку и переводит в rename
8. [ ] `Shift+Delete` удаляет навсегда с подтверждением
9. [ ] `F2` переводит в inline rename для одного файла