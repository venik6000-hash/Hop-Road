class_name LightProfile
extends RefCounted
## How a kind of room takes the light (assets/light/profiles.json; docs/LEVEL.md,
## «Свет помещений»): how far the eye opens in it, how bright its probe's
## ambient light is by day and by night, how much of the valley's haze it
## keeps, and how bright the day comes in through its openings. A room of a
## table names its profile; a room a table gives by its probe alone (`probes`)
## may name one, else it takes the file's `probe_rooms`. A lamp names its kind,
## whose defaults (a shadow, the size of the light for a soft one) the row may
## leave out.

const FILE := "res://assets/light/profiles.json"

var name := ""
## The gain over the authored exposure in such a room by day and by night,
## and the stops the gain may stand over that for what the eye sees there.
var gain := Vector2.ONE
var over := Vector2.ZERO
## The energy of the probes' ambient light under the full day and at night.
var ambient := Vector2.ONE
## The share of the valley's haze the room keeps (EyeAdaptation.haze).
var haze := 0.0
## The day through an opening (Daylight); empty: the room has none.
var daylight := {}

static var _profiles := {}
static var _lamps := {}
static var _probe_rooms := ""

## The profile called `title`; null when the file has none of that name.
static func named(title: String) -> LightProfile:
	_load()
	var found: Variant = _profiles.get(title)
	return found if found is LightProfile else null

## The profile of a room a table gives by its probe alone and names none of.
static func of_probe_rooms() -> LightProfile:
	_load()
	return named(_probe_rooms)

## The defaults of a lamp of `kind`: {shadow, size}; empty when there is no such kind.
static func lamp_kind(kind: String) -> Dictionary:
	_load()
	return Values.table(_lamps.get(kind, {}))

static func _load() -> void:
	if not _profiles.is_empty():
		return
	var file := Values.table(DataFile.read(FILE, BuildingSchemas.light_profiles()))
	var rows := Values.table(file.get("profiles", {}))
	for title: String in rows:
		var row := Values.table(rows[title])
		var profile := LightProfile.new()
		profile.name = title
		var exposure := Values.table(row.exposure)
		profile.gain = Vector2(Values.real(exposure.day), Values.real(exposure.night))
		profile.over = Vector2(Values.real(exposure.over_day), Values.real(exposure.over_night))
		var ambient := Values.table(row.ambient)
		profile.ambient = Vector2(Values.real(ambient.day), Values.real(ambient.night))
		profile.haze = Values.real(row.haze)
		profile.daylight = Values.table(row.get("daylight", {}))
		_profiles[title] = profile
	_lamps = Values.table(file.get("lamps", {}))
	_probe_rooms = str(file.get("probe_rooms", ""))
