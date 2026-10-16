class_name Languages
extends RefCounted
## The languages of the game (docs/LEVEL.md, «Языки»). The source language is
## Russian: a key of the tables in assets/locale/ is the Russian text itself,
## so the Russian table holds only the plural forms. GameSettings keeps the
## player's language and puts it on at the start.

## The languages in the order of the settings panel; the first is the source.
const IDS: Array[String] = ["ru", "en"]
const SOURCE := "ru"
## Each language by its own name: the list reads the same in every language.
const NAMES: Dictionary[String, String] = {"ru": "Русский", "en": "English"}

static func valid(id: String) -> String:
	return id if id in IDS else SOURCE

## The system's language when the game has it, else the source.
static func system_default() -> String:
	return valid(OS.get_locale_language())

## Puts `id` on: tr() and every Control that shows a key speak it from now,
## and every node in the tree gets NOTIFICATION_TRANSLATION_CHANGED.
static func apply(id: String) -> void:
	TranslationServer.set_locale(valid(id))
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and DisplayServer.get_name() != "headless":
		tree.root.title = TranslationServer.translate(str(ProjectSettings.get_setting("application/config/name")))
