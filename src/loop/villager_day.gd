class_name VillagerDay
extends RefCounted
## Where a villager is at an hour of the day. A sheet's `day` is a list of
## {from, to, at}: hours of the sky (0..24) and one of PLACES. An entry whose
## `from` is later than its `to` runs through midnight. Rain and storm send a
## villager from an open place to their shelter.

const PLACES: Array[String] = ["work", "road", "yard", "hall", "home"]
## The places under the sky.
const OPEN: Array[String] = ["road", "yard"]
## The weathers (WeatherSystem.kind) nobody stays out in.
const WET: Array[String] = ["rain", "storm"]
## The places a sheet may name as a shelter.
const SHELTERS: Array[String] = ["work", "hall", "home"]

## A sheet's `day` from parsed JSON: the entries with hours in 0..24, a span
## that is not empty and a known place; the rest are dropped.
static func entries(data: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not data is Array:
		return result
	for entry: Variant in data:
		if not entry is Dictionary:
			continue
		var start: Variant = entry.get("from")
		var end: Variant = entry.get("to")
		var at: Variant = entry.get("at")
		if not _is_hour(start) or not _is_hour(end) or not at is String or not PLACES.has(at):
			continue
		if float(start) == float(end):
			continue
		result.append({"from": float(start), "to": float(end), "at": at})
	return result

## Whether the entry covers the hour: `from` is in, `to` is out.
static func holds(entry: Dictionary, hour: float) -> bool:
	var h := fposmod(hour, 24.0)
	var start: float = entry["from"]
	var end: float = entry["to"]
	if start > end:
		return h >= start or h < end
	return h >= start and h < end

## The place of the first entry of `day` that covers the hour, `fallback` when
## none does; in the wet, the shelter instead of an open place, when the
## villager has one.
static func place(day: Array[Dictionary], hour: float, weather: String, shelter: String, fallback: String) -> String:
	var at := fallback
	for entry: Dictionary in day:
		if holds(entry, hour):
			at = entry.at
			break
	if OPEN.has(at) and WET.has(weather) and not shelter.is_empty():
		return shelter
	return at

static func _is_hour(value: Variant) -> bool:
	if not (value is float or value is int):
		return false
	var hour: float = float(value)
	return is_finite(hour) and hour >= 0.0 and hour <= 24.0
