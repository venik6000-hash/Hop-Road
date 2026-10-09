class_name FishingState
extends RefCounted
## Habitat weighting adapted from Tidewater Bites.js (MIT; assets/external/tidewater).
## All persistent fish have an id: cooking, gifts and eating consume that id once.
const SPECIES := {
	"rudd": {"title": "Краснопёрка", "length": Vector2(16, 32), "mass": 0.32, "habitat": "shallows", "time": "day"},
	"perch": {"title": "Окунь", "length": Vector2(18, 38), "mass": 0.65, "habitat": "pier", "time": "day"},
	"trout": {"title": "Форель", "length": Vector2(24, 52), "mass": 1.3, "habitat": "deep", "time": "dawnDusk"},
	"pike": {"title": "Щука", "length": Vector2(38, 78), "mass": 2.6, "habitat": "reeds", "time": "dawnDusk"},
}
const CAPACITY := 8
var bag: Array[Dictionary] = []
var journal: Dictionary = {}
var next_id := 1
var save_path := "user://lakeside-fishing.json"
var rng := RandomNumberGenerator.new()

static func habitat(depth: float, shore_distance: float) -> Dictionary:
	if depth < 0.35:
		return {}
	return {"shallows": 1.0 - smoothstep(1.0, 3.5, depth),
		"pier": 0.25 + 0.75 * (1.0 - smoothstep(2.0, 12.0, shore_distance)),
		"reeds": smoothstep(0.4, 1.5, depth) * (1.0 - smoothstep(3.0, 8.0, depth)),
		"deep": smoothstep(2.5, 9.0, depth)}

static func activity(preference: String, hour: float) -> float:
	var dawn := exp(-pow(hour - 6.5, 2) / 2.5)
	var dusk := exp(-pow(hour - 18.5, 2) / 2.5)
	if preference == "dawnDusk":
		return 0.3 + 0.7 * maxf(dawn, dusk)
	return 1.0 if hour > 7.0 and hour < 18.0 else 0.25

func choose(depth: float, shore_distance: float, hour: float) -> String:
	var home := habitat(depth, shore_distance)
	if home.is_empty():
		return ""
	var weights: Dictionary = {}
	var total := 0.0
	for species: String in SPECIES:
		var fish: Dictionary = SPECIES[species]
		var weight: float = home[fish.habitat] * activity(fish.time, hour)
		weights[species] = weight
		total += weight
	var pick := rng.randf() * total
	for species: String in weights:
		pick -= float(weights[species])
		if pick <= 0.0:
			return species
	return "perch"

func catch_fish(species: String, hour: float) -> Dictionary:
	if not SPECIES.has(species):
		return {}
	var data: Dictionary = SPECIES[species]
	var length := rng.randf_range(data.length.x, data.length.y)
	var mass: float = data.mass * pow(length / data.length.y, 3.0)
	var fish := {"id": next_id, "species": species, "cm": snappedf(length, 0.1), "kg": snappedf(mass, 0.01), "hour": hour, "cooked": false}
	next_id += 1
	var record: Dictionary = journal.get(species, {"count": 0, "best_cm": 0.0, "best_kg": 0.0})
	record.count = int(record.count) + 1
	record.best_cm = maxf(record.best_cm, length)
	record.best_kg = maxf(record.best_kg, mass)
	journal[species] = record
	if bag.size() < CAPACITY:
		bag.append(fish)
	save()
	return fish

func first(cooked: bool) -> Dictionary:
	for fish in bag:
		if fish.cooked == cooked:
			return fish
	return {}

func take(id: int) -> Dictionary:
	for i in bag.size():
		if int(bag[i].id) == id:
			var fish := bag[i]
			bag.remove_at(i)
			save()
			return fish
	return {}

func cook(id: int) -> bool:
	for fish in bag:
		if int(fish.id) == id and not fish.cooked:
			fish.cooked = true
			save()
			return true
	return false

func save() -> void:
	if save_path.is_empty():
		return
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({"version": 1, "next_id": next_id, "bag": bag, "journal": journal}))
	file.close()
	DirAccess.rename_absolute(save_path + ".tmp", save_path)

func restore() -> void:
	if save_path.is_empty() or not FileAccess.file_exists(save_path):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or data.get("version") != 1:
		return
	if not data.get("bag", []) is Array:
		return
	bag.clear()
	journal.clear()
	next_id = 1
	var seen := {}
	for value: Variant in data.get("bag", []):
		if not value is Dictionary or not SPECIES.has(value.get("species", "")):
			continue
		var id := int(number(value.get("id"), 0, 0, 1000000000))
		if id <= 0 or seen.has(id) or bag.size() >= CAPACITY:
			continue
		seen[id] = true
		bag.append({"id": id, "species": value.species, "cm": number(value.get("cm"), 20, 1, 150),
			"kg": number(value.get("kg"), 0.2, 0.01, 20), "hour": number(value.get("hour"), 12, 0, 24), "cooked": value.get("cooked") == true})
		next_id = maxi(next_id, id + 1)
	if data.get("journal") is Dictionary:
		for species: String in SPECIES:
			var entry: Variant = data.journal.get(species)
			if entry is Dictionary:
				journal[species] = {"count": int(number(entry.get("count"), 0, 0, 1000000000)), "best_cm": number(entry.get("best_cm"), 0, 0, 150), "best_kg": number(entry.get("best_kg"), 0, 0, 20)}
	next_id = maxi(next_id, int(number(data.get("next_id"), 1, 1, 1000000001)))

static func number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback
