# Hop Road

Тестовая карта игры «Хмельная тропа»: альпийская долина с таверной, озером и деревней. По ней можно ходить, плавать, рыбачить с лодки, разжигать костёр, менять погоду и время суток. В деревне стоят пивоварня, кузница, мельница с водяным колесом, бондарня, дом фонарщика и хмелесушильня с хмельником, на острове — маяк, у причала — каменная пристань; дороги ночью освещают фонари. У жителей свой распорядок дня, с ними можно разговаривать. Для прогулок открыт квадрат земли около 3 × 3 км; по его краю стоит невидимая стена, горы за ней — только фон.

Проект Godot 4.7.2 (Forward+). Проверен на macOS (Apple M1, Metal); на Windows и Linux не запускался.

*English summary is at the end.*

## Запуск

1. Поставьте [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/), обычную сборку (не .NET).
2. Скачайте репозиторий: `git clone` или «Code → Download ZIP». Он весит около 1,7 ГБ.
3. В менеджере проектов Godot нажмите «Импорт» и выберите `project.godot`. При первом открытии редактор импортирует ресурсы: на Apple M1 это около семи минут и ещё 1,3 ГБ в папке `.godot/`.
4. Нажмите F5. В главном меню выберите «Новая игра».

Игра рассчитана на запуск из редактора; экспорт отдельной сборкой целиком не проверялся. Сначала проект нужно открыть в редакторе: без импорта игра не запустится. Первый запуск дольше остальных, потому что видеокарта компилирует шейдеры; экран загрузки в это время не завис.

Если игра идёт медленно, F10 открывает настройки: качество изображения и текстур, экран, звук, клавиши. Там же выбирается язык: русский или английский.

## Управление

| Клавиша | Действие |
|---|---|
| W A S D, мышь | Ходьба и обзор |
| Shift | Бег |
| Пробел / C | Всплыть / нырнуть |
| E | Дверь, сесть, лестница, лодка, действия у костра, поговорить с жителем или позвать его на прогулку, мехи и точило в кузнице |
| V | Глоток из кружки |
| K | Поставить костёр |
| J | Достать или убрать удочку; заброс — зажать и отпустить левую кнопку мыши |
| I | Журнал улова |
| R / B | Вернуться к таверне / перейти на пляж |
| F5 / F6 | Погода: предыдущая / следующая |
| F7 | Погода меняется сама |
| [ / ] | Время суток на час назад / вперёд |
| F1–F4 | Ветер на озере: от штиля до шторма |
| F9 | Панорама долины |
| F10 | Настройки |
| H | Показать или скрыть кружку |
| F12 | Снимок экрана |
| Tab | Показать или скрыть подсказку по управлению |
| Esc | Пауза |

Остальные клавиши показывает подсказка по Tab. Клавиши меняются в настройках. R, B, F1–F7, F9, `[` и `]` — отладочные: они работают только в редакторе и в отладочной сборке.

## Сторонние ресурсы

Источники, авторы и лицензии записаны рядом с ресурсами: файлы `CREDITS.*`, `SOURCES.json` и `license.txt` в папках `assets/`.

- Сканы Poly Haven и ambientCG, звуки Freesound — CC0.
- Модели с Sketchfab (реквизит деревни, животные, лодка, кружка, дракон, житель) — CC BY 4.0.
- Рука, которая держит кружку, и руки пивовара — бесплатный скан Ten24 (3D Scan Store), условия на странице скана.
- Модели с OpenGameArt — CC0, CC BY 3.0 (окунь, форель) и CC BY-SA 3.0 (монах, чайка).
- Код озера в `src/lakeside/` частично адаптирован из проекта Tidewater — MIT, `assets/external/tidewater/`.

Файлы `CREDITS` упоминают скрипты из `tools/` и папки `source/`: это конвейер подготовки ресурсов, его в этом репозитории нет.

В этой версии нет модели одного из жителей: лицензия Sketchfab Standard не разрешает выкладывать её файлы. Повар и его брат-фонарщик выглядят как монах, торговец — как Марта, одного из прохожих нет.

Постройки деревни добавлены 12 октября 2026 года: пивоварня, кузница, мельница, маяк, дом фонарщика, хмелесушильня с хмельником, бондарня, гать через плавни, мостки для стирки, пристань и восемь фонарей дороги. По ним можно ходить, но яркость ламп и материалы на них ещё не подбирались.

## In English

A test map of the game "The Hop Road": an alpine valley with a tavern, a lake and a village. You can walk, swim, fish from a boat, light a campfire, and change the weather and the time of day. The village has a brewery, a smithy, a water mill, a cooperage, a lamplighter's house and a hop kiln with its hop garden; a lighthouse stands on the island, a stone quay at the pier, and lanterns light the roads at night. The villagers keep their own hours and can be talked to. The walkable land is a square of about 3 by 3 km; an invisible wall stands at its edge, and the mountains beyond are scenery.

To run it, install [Godot 4.7.2](https://godotengine.org/download/archive/4.7.2-stable/) (standard build), download this repository (about 1.7 GB), import `project.godot` in the Godot project manager, wait for the first import (about seven minutes on an Apple M1, 1.3 GB more in `.godot/`) and press F5, then choose «Новая игра» (New game) in the main menu. Run it from the editor: an exported build has not been tested end to end. The first launch takes longer because the shaders compile. Tested on macOS (Apple M1, Metal) only.

Keys: WASD and mouse to move, Shift to run, E to interact, V to drink, K for a campfire, J for the fishing rod, F10 for the settings (graphics, display, sound, keys), F12 for a screenshot, Tab for the controls help, Esc to pause. R, B, F1–F7, F9, `[` and `]` are debug keys: they work only in the editor and in a debug build. The game's text is in Russian and English: pick the language in the settings.

Third-party assets keep their own licences (CC0, CC BY 4.0, CC BY 3.0, CC BY-SA 3.0, MIT): see the `CREDITS.*`, `SOURCES.json` and `license.txt` files next to them in `assets/`.

The hands (the one holding the mug and the brewer's) are Ten24's free sample scan. One villager model is left out: its Sketchfab Standard licence does not allow sharing the model files. The cook and his brother wear the monk's model, the trader Marta's, and one passer-by is missing. The village's buildings are new (12 October 2026): the brewery, the smithy, the mill, the lighthouse, the lamplighter's house, the hop kiln and hop garden, the cooperage, a corduroy road through the marsh, a washing stage, the quay and eight road lanterns. They can be walked through; their lamps and materials are not tuned yet.
