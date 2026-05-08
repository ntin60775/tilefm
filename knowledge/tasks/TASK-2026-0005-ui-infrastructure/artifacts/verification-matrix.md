# Verification Matrix: TASK-2026-0005

## Инварианты и проверки

### Settings persistence

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Изменить настройку →重启 app | Значение сохраняется | chk_show_hidden = true → restart → still true | TODO |
| Settings file missing | Defaults used, no crash | rm settings file → start TileFM | TODO |
| Settings file corrupted | Defaults used, warning shown | Edit settings file → corrupt JSON → start | TODO |
| Auto-save on change | No "Apply" button needed | Change any setting → check file updated | TODO |

### PreferencesDialog

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Ctrl+, открывает dialog | Dialog appears centered | Press Ctrl+, | TODO |
| All pages accessible | Stack switches correctly | Click each tab in settings | TODO |
| General page: changes apply | Confirmed delete works | Toggle chk → try delete → confirmation shows/hides | TODO |
| View page: icon size change | View updates | Change size → immediately see bigger/smaller icons | TODO |
| Shortcuts page: edit shortcut | New shortcut works | Double-click → press Ctrl+B → test new shortcut | TODO |
| Shortcuts page: conflict | Conflict highlighted | Set duplicate shortcut → see red warning | TODO |
| Extensions page: toggle plugin | Plugin state changes | Uncheck custom_actions → reload → custom actions disabled | TODO |
| About page: shows version | Version matches | Check "О программе" shows "1.0" | TODO |

### ShortcutsHelpDialog

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| Ctrl+H opens dialog | Dialog appears | Press Ctrl+H | TODO |
| ? button opens dialog | Dialog appears | Click ? in toolbar | TODO |
| Dialog shows all shortcuts | Table complete | Compare with spec in sdd.md | TODO |
| Dialog closes on Escape | Dialog closes | Press Escape | TODO |

### HelpDialog (F1)

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| F1 opens help | Help dialog appears | Press F1 | TODO |
| Help shows content | Content rendered | Check text visible | TODO |
| Help has navigation | Can scroll | Scroll through help | TODO |
| Missing help file | "Help not available" message | Remove help file → F1 | TODO |

### Menu integration

| Сценарий нарушения | Проверка | Действие | Статус |
|---|---|---|---|
| "Справка" menu exists | Menu visible in menubar | Check app menu | TODO |
| Submenu: "Справка", "Горячие клавиши", "О программе" | All items present | Check submenu | TODO |
| "О программе" shows dialog | Dialog with version | Click "О программе" | TODO |

## Проверки сборки

- `ninja -C build` — без ошибок
- Vala warnings — 0
- Memory leaks — 0
- New files compile: preferences_dialog.vala, shortcuts_help_dialog.vala, help_dialog.vala, settings.vala

## Ручные проверки для acceptance

1. [ ] `Ctrl+,` открывает диалог настроек
2. [ ] Все вкладки настроек работают (General, View, Shortcuts, Extensions, About)
3. [ ] Изменения в настройках сохраняются между сессиями
4. [ ] `Ctrl+H` показывает окно с горячими клавишами
5. [ ] Кнопка `?` в toolbar открывает то же что `Ctrl+H`
6. [ ] `F1` открывает общую справку
7. [ ] Меню "Справка → О программе" показывает версию и копирайт
8. [ ] Справка по горячим клавишам закрывается по Escape
9. [ ] PreferencesDialog закрывается по OK/Cancel (не Escape)
10. [ ] Duplicate shortcut в настройках показывает ошибку