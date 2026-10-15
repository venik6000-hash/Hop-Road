class_name BrewBook
extends RefCounted
## The brewer's book: the valley's recipes (assets/brewing/recipes.json) and
## the causes of flaws (assets/brewing/flaws.json). It names the beer a batch
## became: the recipe its profile (BrewBatch.profile) fits, else a nameless ale.
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
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(recipes_path))
	if data is Dictionary:
		var listed: Variant = data.get("recipes")
		if listed is Array:
			for recipe: Variant in listed:
				if recipe is Dictionary:
					book.recipes.append(_recipe(recipe))
		var none: Variant = data.get("nameless")
		book.nameless = none if none is Dictionary else {}
		var bad: Variant = data.get("spoiled")
		book.spoiled = bad if bad is Dictionary else {}
	var causes: Variant = JSON.parse_string(FileAccess.get_file_as_string(flaws_path))
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
		if value < float(span[0]) or value > float(span[1]):
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

## A recipe as a page of the book: its name, its taste, its steps.
static func recipe_page(recipe: Dictionary) -> String:
	var lines := PackedStringArray([str(recipe.get("name", "")), str(recipe.get("taste", "")), ""])
	for step: Variant in recipe.get("steps", []):
		lines.append("— " + str(step))
	return "\n".join(lines)

## The batch's journal (BrewBatch.journal) as the brewer writes it down, a
## line a step, and its flaws with their causes.
func journal_lines(journal: Array[Dictionary], batch_flaws: Array[String]) -> PackedStringArray:
	var lines := PackedStringArray()
	for entry: Dictionary in journal:
		lines.append(journal_line(entry))
	for id: String in batch_flaws:
		var flaw: Dictionary = flaws.get(id, {})
		lines.append("Изъян: %s. %s" % [flaw.get("name", id), flaw.get("cause", "")])
	return lines

## One step of the journal in words.
static func journal_line(entry: Dictionary) -> String:
	var n := func(key: String) -> float: return float(entry.get(key, 0.0))
	match str(entry.step):
		"line_tun":
			return "Дно чана выстлано можжевельником: %.1f кг." % n.call("kg")
		"mash_in":
			return "Затор: %.0f кг солода, %.0f л воды при %.0f°, затор %.0f°." % [n.call("grain_kg"), n.call("water_l"),
				n.call("water_temp"), n.call("mash_temp")]
		"grain":
			return "Досыпано %.1f кг солода, затор %.0f°." % [n.call("kg"), n.call("mash_temp")]
		"pour":
			return "Долито %.0f л при %.0f°, затор %.0f°." % [n.call("liters"), n.call("temp"), n.call("mash_temp")]
		"rest":
			return "Затор стоял %.0f мин, остыл до %.0f°, осахарено %.0f %%." % [n.call("minutes"), n.call("mash_temp"),
				n.call("conversion") * 100.0]
		"lauter":
			return "Слив: кран открыт на %.0f %%, промывка %.0f л, сусла %.0f л." % [n.call("tap") * 100.0, n.call("sparge_l"),
				n.call("volume_l")]
		"spill":
			return "Пролито %.0f л %s." % [n.call("liters"), "пива" if entry.get("beer", false) else "сусла"]
		"water_down":
			return "В сусло попало %.0f л воды." % n.call("liters")
		"boil":
			return "Кипело %.0f мин на огне %.0f %%, в котле %.0f л." % [n.call("minutes"), n.call("fire") * 100.0,
				n.call("volume_l")]
		"hops":
			return "Хмель: %.0f г на %.0f-й минуте кипения." % [n.call("grams"), n.call("at")]
		"draw_fire":
			return "Огонь снят после %.0f мин кипения." % n.call("boil_minutes")
		"honey":
			return "Мёд: %.1f кг%s." % [n.call("kg"), " после огня" if entry.get("fire_out", false) else " в кипение"]
		"linden":
			return "Липовый цвет: %.2f кг." % n.call("kg")
		"cool":
			return "Сусло стыло %.1f ч, до %.0f°." % [n.call("hours"), n.call("wort_temp")]
		"pitch":
			return "Дрожжи: %.1f л в сусло при %.0f°%s." % [n.call("yeast_l"), n.call("wort_temp"),
				", дрожжи сварились" if entry.get("died", false) else ""]
		"ferment_day":
			return "День брожения при %.0f°%s." % [n.call("cellar_temp"), ", пена снята" if entry.get("skim", false) else ""]
		"rack":
			var spilled: String = " пролито %.0f л." % n.call("spilled_l") if n.call("spilled_l") >= 0.5 else ""
			return "Перелив в лагерную бочку: бочка %s.%s" % ["ошпарена" if entry.get("scalded", false) else "не ошпарена",
				spilled]
	return str(entry.step)

## Lines of the journal a page holds.
const PAGE_LINES := 14

## The book as its pages: the contents, a page a recipe, and the journal of
## `batch` with what it has become so far.
func pages(batch: BrewBatch) -> PackedStringArray:
	var result := PackedStringArray()
	var contents := PackedStringArray(["Книга пивовара", "", "Рецепты долины:"])
	for each: Dictionary in recipes:
		contents.append("— " + str(each.name))
	result.append("\n".join(contents))
	for each: Dictionary in recipes:
		result.append(recipe_page(each))
	var lines := journal_lines(batch.journal, batch.flaws)
	var head := "Журнал варки"
	if batch.stage == "new":
		lines = PackedStringArray(["Варка не начата."])
	elif batch.fire_out:
		head += " · сорт по книге: " + str(name_beer(batch.profile()).get("name", ""))
	for first in range(0, lines.size(), PAGE_LINES):
		result.append(head + "\n\n" + "\n".join(lines.slice(first, first + PAGE_LINES)))
	return result
