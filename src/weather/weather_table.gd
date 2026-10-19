class_name WeatherTable
extends RefCounted
## The kinds of weather as data (assets/weather/weathers.json;
## WorldSchemas.weathers): each kind's name, state (FIELDS), the wind sea of
## the lake that goes with it (OceanFFT.PRESETS), the headings its wind blows
## to (WeatherSystem.pick_heading) and the kinds the weather may go to by
## itself, with the odds. "fair" is the look the level was authored
## with: nothing of the weather is drawn in it. WeatherSystem blends them.

const PATH := "res://assets/weather/weathers.json"
## The kinds, in the order the debug keys step through them.
const KINDS: Array[String] = ["clear", "fair", "overcast", "mist", "rain", "storm"]
## The numbers of a state. coverage, density, cumulus: the cloud layer, as
## SkySystem's exports. darkness: 0 white fair-weather cloud .. 1 a storm's
## dark base. cirrus: the high ice cloud. haze: fog everywhere, thinning with
## height. mist: the fog bank lying on the lake. rain: rain fog under the
## clouds and drops in the air. storm: lightning. wind: the clouds' speed over
## the authored one.
const FIELDS: Array[String] = ["coverage", "density", "cumulus", "darkness", "cirrus", "haze", "mist", "rain",
	"storm", "wind"]

static var _rows: Dictionary = {}

## Kind -> {name, lake, heading, state, next}, as PATH holds them.
static func rows() -> Dictionary:
	if _rows.is_empty():
		var data: Variant = DataFile.read(PATH, WorldSchemas.weathers())
		_rows = data if data is Dictionary else {}
	return _rows

## The row of `of_kind`; {} for a kind the table lacks.
static func row(of_kind: String) -> Dictionary:
	return rows().get(of_kind, {})

## What the player calls the weather `of_kind`, untranslated.
static func title(of_kind: String) -> String:
	return str(row(of_kind).get("name", of_kind))

## The headings, degrees from +X toward +Z, the wind of the weather `of_kind`
## blows to: from x to y; zeros for a kind the table lacks.
static func headings(of_kind: String) -> Vector2:
	return Values.vec2(row(of_kind).get("heading", [0.0, 0.0]))

## The state of the weather `of_kind`; zeros where the table has none.
static func state(of_kind: String) -> Dictionary:
	var preset: Dictionary = row(of_kind).get("state", {})
	var values := {}
	for field: String in FIELDS:
		values[field] = Values.real(preset.get(field, 0.0))
	return values
