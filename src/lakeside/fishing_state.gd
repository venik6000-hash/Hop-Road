class_name FishingState
extends RefCounted
## Habitat weighting adapted from Tidewater Bites.js (MIT; assets/external/tidewater).
## All persistent fish have an id: cooking, gifts and eating consume that id once.
## The fish of the lake (fish.json): title, length range (cm), mass at the
## longest (kg), habitat (habitat()'s keys) and time (activity()).
const SPECIES := "res://assets/lakeside/fish.json"
## The waters a fish keeps to (habitat()) and its hours (activity()).
const HABITATS: Array[String] = ["shallows", "pier", "reeds", "deep"]
const TIMES: Array[String] = ["day", "dawnDusk"]
const CAPACITY := 8
## The bag or the journal has changed; the valley's save keeps them
## (SaveService, section "fishing").
signal changed
var bag: Array[Dictionary] = []
var journal: Dictionary = {}
var next_id := 1
var rng := RandomNumberGenerator.new()

static var _species: Dictionary = {}

## Species id -> its row of SPECIES.
static func species_table() -> Dictionary:
	if _species.is_empty():
		var data: Variant = DataFile.read(SPECIES, WorldSchemas.fish())
		_species = data if data is Dictionary else {}
	return _species

## What the player calls the fish of `species`, untranslated.
static func title(species: String) -> String:
	var row: Dictionary = species_table().get(species, {})
	return str(row.get("title", species))

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
	var table := species_table()
	for species: String in table:
		var fish: Dictionary = table[species]
		var weight: float = home[fish.habitat] * activity(str(fish.time), hour)
		weights[species] = weight
		total += weight
	var pick := rng.randf() * total
	for species: String in weights:
		pick -= Values.real(weights[species])
		if pick <= 0.0:
			return species
	return "perch"

func catch_fish(species: String, hour: float) -> Dictionary:
	if not species_table().has(species):
		return {}
	var data: Dictionary = species_table()[species]
	var span: Array = data.length
	var length := rng.randf_range(Values.real(span[0]), Values.real(span[1]))
	var mass: float = Values.real(data.mass) * pow(length / Values.real(span[1]), 3.0)
	var fish := {"id": next_id, "species": species, "cm": snappedf(length, 0.1), "kg": snappedf(mass, 0.01), "hour": hour, "cooked": false}
	next_id += 1
	var record: Dictionary = journal.get(species, {"count": 0, "best_cm": 0.0, "best_kg": 0.0})
	record.count = Values.whole(record.count) + 1
	record.best_cm = maxf(Values.real(record.best_cm), length)
	record.best_kg = maxf(Values.real(record.best_kg), mass)
	journal[species] = record
	if bag.size() < CAPACITY:
		bag.append(fish)
	changed.emit()
	return fish

func first(cooked: bool) -> Dictionary:
	for fish in bag:
		if fish.cooked == cooked:
			return fish
	return {}

func take(id: int) -> Dictionary:
	for i in bag.size():
		if Values.whole(bag[i].id) == id:
			var fish := bag[i]
			bag.remove_at(i)
			changed.emit()
			return fish
	return {}

func cook(id: int) -> bool:
	for fish in bag:
		if Values.whole(fish.id) == id and not fish.cooked:
			fish.cooked = true
			changed.emit()
			return true
	return false

## The bag and the journal as the valley's save holds them.
func to_dict() -> Dictionary:
	return {"next_id": next_id, "bag": bag.duplicate(true), "journal": journal.duplicate(true)}

## Takes the bag and the journal back from to_dict(), checked; what is not such
## a record leaves the state as it is.
func restore(saved_state: Variant) -> void:
	if not saved_state is Dictionary:
		return
	var data: Dictionary = saved_state
	if not data.get("bag", []) is Array:
		return
	bag.clear()
	journal.clear()
	next_id = 1
	var seen := {}
	for value: Variant in data.get("bag", []):
		if not value is Dictionary:
			continue
		var row: Dictionary = value
		if not species_table().has(row.get("species", "")):
			continue
		var id := int(Values.number(row.get("id"), 0, 0, 1000000000))
		if id <= 0 or seen.has(id) or bag.size() >= CAPACITY:
			continue
		seen[id] = true
		bag.append({"id": id, "species": row.species, "cm": Values.number(row.get("cm"), 20, 1, 150),
			"kg": Values.number(row.get("kg"), 0.2, 0.01, 20), "hour": Values.number(row.get("hour"), 12, 0, 24), "cooked": row.get("cooked") == true})
		next_id = maxi(next_id, id + 1)
	var saved_journal: Variant = data.get("journal")
	if saved_journal is Dictionary:
		var saved: Dictionary = saved_journal
		for species: String in species_table():
			var entry: Variant = saved.get(species)
			if entry is Dictionary:
				var record: Dictionary = entry
				journal[species] = {"count": int(Values.number(record.get("count"), 0, 0, 1000000000)), "best_cm": Values.number(record.get("best_cm"), 0, 0, 150), "best_kg": Values.number(record.get("best_kg"), 0, 0, 20)}
	next_id = maxi(next_id, int(Values.number(data.get("next_id"), 1, 1, 1000000001)))
