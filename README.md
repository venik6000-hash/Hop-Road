# Hop Road

Тестовая карта игры «Хмельная тропа»: альпийская долина с таверной, озером и деревней. По ней можно ходить, плавать, рыбачить с лодки, разжигать костёр, менять погоду и время суток.

Проект Godot 4.7.2 (Forward+). Проверен на macOS (Apple M1, Metal); на Windows и Linux не запускался.

*English summary is at the end.*

## Запуск

1. Поставьте [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/), обычную сборку (не .NET).
2. Скачайте репозиторий: `git clone` или «Code → Download ZIP». Он весит около 1,7 ГБ.
3. В менеджере проектов Godot нажмите «Импорт» и выберите `project.godot`. При первом открытии редактор импортирует ресурсы: на Apple M1 это около семи минут и ещё 1,3 ГБ в папке `.godot/`.
4. Нажмите F5.

Игра рассчитана на запуск из редактора; экспорт отдельной сборкой целиком не проверялся. Сначала проект нужно открыть в редакторе: без импорта игра не запустится. Первый запуск дольше остальных, потому что видеокарта компилирует шейдеры; экран загрузки в это время не завис.

Если игра идёт медленно, F10 открывает настройки графики: качество изображения и текстур.

## Управление

| Клавиша | Действие |
|---|---|
| W A S D, мышь | Ходьба и обзор |
| Shift | Бег |
| Пробел / C | Всплыть / нырнуть |
| E | Дверь, сесть, лестница, лодка, действия у костра, позвать жителя на прогулку |
| V | Глоток из кружки |
| K | Поставить костёр |
| J | Достать или убрать удочку; заброс — зажать и отпустить левую кнопку мыши |
| I | Журнал улова |
| R / B | Вернуться к таверне / перейти на пляж |
| F5 / F6 | Погода: предыдущая / следующая |
| [ / ] | Время суток на час назад / вперёд |
| F1–F4 | Ветер на озере: от штиля до шторма |
| F9 | Панорама долины |
| F10 | Настройки графики |
| H | Показать или скрыть кружку |
| Esc | Освободить курсор |

Остальные клавиши показывает подсказка в левом верхнем углу экрана.

## Сторонние ресурсы

Источники, авторы и лицензии записаны рядом с ресурсами: файлы `CREDITS.*`, `SOURCES.json` и `license.txt` в папках `assets/`.

- Сканы Poly Haven и ambientCG, звуки Freesound — CC0.
- Модели с Sketchfab (реквизит деревни, животные, лодка, кружка, дракон, житель) — CC BY 4.0.
- Модели с OpenGameArt — CC0, CC BY 3.0 (окунь, форель) и CC BY-SA 3.0 (монах, чайка).
- Код озера в `src/lakeside/` частично адаптирован из проекта Tidewater — MIT, `assets/external/tidewater/`.

Файлы `CREDITS` упоминают скрипты из `tools/` и папки `source/`: это конвейер подготовки ресурсов, его в этом репозитории нет.

В этой версии нет кисти руки, которая держит кружку, и одного из жителей (повара в таверне и двух прохожих): лицензия Sketchfab Standard не разрешает выкладывать файлы этих моделей. Кружку держит один рукав.

## In English

A test map of the game "The Hop Road": an alpine valley with a tavern, a lake and a village. You can walk, swim, fish from a boat, light a campfire, and change the weather and the time of day.

To run it, install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (standard build), download this repository (about 1.7 GB), import `project.godot` in the Godot project manager, wait for the first import (about seven minutes on an Apple M1, 1.3 GB more in `.godot/`) and press F5. Run it from the editor: an exported build has not been tested end to end. The first launch takes longer because the shaders compile. Tested on macOS (Apple M1, Metal) only.

Keys: WASD and mouse to move, Shift to run, E to interact, V to drink, K for a campfire, J for the fishing rod, F5/F6 for the weather, `[` and `]` for the time of day, F9 for an overview, F10 for the graphics settings, Esc to release the cursor. The in-game text is in Russian.

Third-party assets keep their own licences (CC0, CC BY 4.0, CC BY 3.0, CC BY-SA 3.0, MIT): see the `CREDITS.*`, `SOURCES.json` and `license.txt` files next to them in `assets/`.

The hand that holds the mug and one villager model are left out: their Sketchfab Standard licence does not allow sharing the model files.
