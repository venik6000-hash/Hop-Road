class_name BrewBook
extends RefCounted
## The brewer's book: the valley's recipes (assets/brewing/recipes.json) and
## the causes of flaws (assets/brewing/flaws.json). It names the beer a batch
## became: the recipe its profile (BrewTaste.profile) fits, else a nameless ale.
##
## A recipe is {id, name, taste, steps, need, none_of, ranges}: `need` are the
## notes the beer must have, `none_of` those it must not, `ranges` map a key
## of the profile to [low, high].

const RECIPES := "res://assets/brewing/recipes.json"
const FLAWS := "res://assets/brewing/flaws.json"

var recipes: Array[Dictionary] = []
var nameless: Dictionary = {}
var spoiled: Dictionary = {}
## Flaw id -> {name, cause}.
var flaws: Dictionary = {}

static func load_files(recipes_path := RECIPES, flaws_path := FLAWS) -> BrewBook:
	var book := BrewBook.new()
	var data: Variant = DataFile.read(recipes_path, BrewingSchemas.recipes())
	if data is Dictionary:
		var table: Dictionary = data
		var listed: Variant = table.get("recipes")
		if listed is Array:
			for recipe: Variant in listed:
				if recipe is Dictionary:
					book.recipes.append(_recipe(Values.table(recipe)))
		var none: Variant = table.get("nameless")
		book.nameless = none if none is Dictionary else {}
		var bad: Variant = table.get("spoiled")
		book.spoiled = bad if bad is Dictionary else {}
	var causes: Variant = DataFile.read(flaws_path, BrewingSchemas.flaws())
	book.flaws = causes if causes is Dictionary else {}
	return book

## A recipe with every key present: lists empty and ranges {} where missing.
static func _recipe(data: Dictionary) -> Dictionary:
	var recipe := data.duplicate()
	for key: String in ["need", "none_of", "steps"]:
		if not recipe.get(key) is Array:
			recipe[key] = []
	if not recipe.get("ranges") is Dictionary:
		recipe.ranges = {}
	return recipe

## Whether a profile fits the recipe.
static func fits(recipe: Dictionary, profile: Dictionary) -> bool:
	var notes: Array = profile.notes
	for note: Variant in recipe.need:
		if not notes.has(note):
			return false
	for note: Variant in recipe.none_of:
		if notes.has(note):
			return false
	var ranges: Dictionary = recipe.ranges
	for key: String in ranges:
		var span: Array = ranges[key]
		var value: float = profile.get(key, 0.0)
		if value < Values.real(span[0]) or value > Values.real(span[1]):
			return false
	return true

## The beer the profile is: of the recipes it fits, the one that needs the
## most notes, the earlier in the book of equals; the nameless ale when none
## fits, the spoiled batch when it is ruined.
func name_beer(profile: Dictionary) -> Dictionary:
	if profile.ruined:
		return spoiled
	var best := nameless
	var best_need := -1
	for recipe: Dictionary in recipes:
		var need: Array = recipe.need
		if need.size() > best_need and fits(recipe, profile):
			best = recipe
			best_need = need.size()
	return best

## The recipe of `id`, {} when the book has none.
func recipe(id: String) -> Dictionary:
	for each: Dictionary in recipes:
		if each.id == id:
			return each
	return {}

## A recipe as a page of the book, translated: its name, its taste, its steps.
static func recipe_page(recipe: Dictionary) -> String:
	var lines := PackedStringArray([_t(str(recipe.get("name", ""))), _t(str(recipe.get("taste", ""))), ""])
	for step: Variant in recipe.get("steps", []):
		lines.append("— " + _t(str(step)))
	return "\n".join(lines)

## The batch's journal (BrewBatch.journal) as the brewer writes it down, a
## line a step, and its flaws with their causes. Translated.
func journal_lines(journal: Array[Dictionary], batch_flaws: Array[String]) -> PackedStringArray:
	var lines := PackedStringArray()
	for entry: Dictionary in journal:
		lines.append(journal_line(entry))
	for id: String in batch_flaws:
		var flaw: Dictionary = flaws.get(id, {})
		lines.append(tr("Изъян: %s. %s") % [tr(str(flaw.get("name", id))), tr(str(flaw.get("cause", "")))])
	return lines

## One step of the journal in words, translated.
static func journal_line(entry: Dictionary) -> String:
	var n := func(key: String) -> float: return Values.real(entry.get(key, 0.0))
	match str(entry.step):
		"line_tun":
			return _t("Дно чана выстлано можжевельником: %.1f кг.") % n.call("kg")
		"mash_in":
			return _t("Затор: %.0f кг солода, %.0f л воды при %.0f°, затор %.0f°.") % [n.call("grain_kg"), n.call("water_l"),
				n.call("water_temp"), n.call("mash_temp")]
		"grain":
			return _t("Досыпано %.1f кг солода, затор %.0f°.") % [n.call("kg"), n.call("mash_temp")]
		"pour":
			return _t("Долито %.0f л при %.0f°, затор %.0f°.") % [n.call("liters"), n.call("temp"), n.call("mash_temp")]
		"rest":
			return _t("Затор стоял %.0f мин, остыл до %.0f°, осахарено %.0f %%.") % [n.call("minutes"), n.call("mash_temp"),
				n.call("conversion") * 100.0]
		"lauter":
			return _t("Слив: кран открыт на %.0f %%, промывка %.0f л, сусла %.0f л.") % [n.call("tap") * 100.0, n.call("sparge_l"),
				n.call("volume_l")]
		"spill":
			var spill := _t("Пролито %.0f л пива.") if entry.get("beer", false) else _t("Пролито %.0f л сусла.")
			return spill % n.call("liters")
		"water_down":
			return _t("В сусло попало %.0f л воды.") % n.call("liters")
		"boil":
			return _t("Кипело %.0f мин на огне %.0f %%, в котле %.0f л.") % [n.call("minutes"), n.call("fire") * 100.0,
				n.call("volume_l")]
		"hops":
			return _t("Хмель: %.0f г на %.0f-й минуте кипения.") % [n.call("grams"), n.call("at")]
		"draw_fire":
			return _t("Огонь снят после %.0f мин кипения.") % n.call("boil_minutes")
		"honey":
			var honey := _t("Мёд: %.1f кг после огня.") if entry.get("fire_out", false) else _t("Мёд: %.1f кг в кипение.")
			return honey % n.call("kg")
		"linden":
			return _t("Липовый цвет: %.2f кг.") % n.call("kg")
		"cool":
			return _t("Сусло стыло %.1f ч, до %.0f°.") % [n.call("hours"), n.call("wort_temp")]
		"pitch":
			var pitch := _t("Дрожжи: %.1f л в сусло при %.0f°, дрожжи сварились.") if entry.get("died", false) \
				else _t("Дрожжи: %.1f л в сусло при %.0f°.")
			return pitch % [n.call("yeast_l"), n.call("wort_temp")]
		"ferment_day":
			var day := _t("День брожения при %.0f°, пена снята.") if entry.get("skim", false) else _t("День брожения при %.0f°.")
			return day % n.call("cellar_temp")
		"rack":
			var rack := _t("Перелив в лагерную бочку: бочка ошпарена.") if entry.get("scalded", false) \
				else _t("Перелив в лагерную бочку: бочка не ошпарена.")
			if n.call("spilled_l") >= 0.5:
				rack += _t(" Пролито %.0f л.") % n.call("spilled_l")
			return rack
	return str(entry.step)

static func _t(key: String) -> String:
	return TranslationServer.translate(key)

## Lines of the journal a page holds.
const PAGE_LINES := 14

## The book as its pages, translated: the contents, a page a recipe, and the
## journal of `batch` with what it has become so far.
func pages(batch: BrewBatch) -> PackedStringArray:
	var result := PackedStringArray()
	var contents := PackedStringArray([tr("Книга пивовара"), "", tr("Рецепты долины:")])
	for each: Dictionary in recipes:
		contents.append("— " + tr(str(each.name)))
	result.append("\n".join(contents))
	for each: Dictionary in recipes:
		result.append(recipe_page(each))
	var lines := journal_lines(batch.journal, batch.flaws)
	var head := tr("Журнал варки")
	if batch.stage == BrewIds.STAGE_NEW:
		lines = PackedStringArray([tr("Варка не начата.")])
	elif batch.fire_out:
		head = tr("Журнал варки · сорт по книге: %s") % tr(str(name_beer(BrewTaste.profile(batch)).get("name", "")))
	for first in range(0, lines.size(), PAGE_LINES):
		result.append(head + "\n\n" + "\n".join(lines.slice(first, first + PAGE_LINES)))
	return result
