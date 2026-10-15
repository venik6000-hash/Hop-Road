class_name BrewCarry
extends RefCounted
## What the player carries in the brewery: one utensil of brewery.json at a
## time, and a step slower the heavier it is. Where a thing put down lands:
## in a place of its own near the aim (its home, a bucket's place, a keg's
## place, a keg's bung hole for the funnel), else on the flat where the aim
## meets it. All places are in the building's frame.

## Kg of a utensil of each kind of brewery.json, empty.
const WEIGHTS := {"tool": 2.0, "instrument": 1.0, "vessel": 5.0, "sack": 1.0, "raw": 3.0, "log": 4.0}
## Kg at which the step is slowest, and the slowest step's part of a free one.
const HEAVY := 80.0
const SLOWEST := 0.45
## Metres within which a thing put down snaps to a place of its own; a place
## also takes an aim that meets something up to RISE metres over it (a tap,
## the flank of a tun).
const SNAP := 0.35
const RISE := 0.8
## The least up of a face a thing can stand on.
const FLAT := 0.8
## Vessels that stand in a bucket's place (brewery.json anchors of kind "bucket").
const BUCKETS: Array[String] = ["water_bucket", "hoist_bucket", "cellar_bucket"]

## The kind of anchor `id` snaps to: "bucket", "keg", "funnel", or "" for none.
static func snaps_to(id: String) -> String:
	if BUCKETS.has(id):
		return "bucket"
	if id.begins_with("keg_"):
		return "keg"
	return "funnel" if id == "funnel" else ""

## The utensil in the hand, "" for none.
var held := ""

## The part of a free step a load of `kg` leaves.
static func pace(kg: float) -> float:
	return lerpf(1.0, SLOWEST, clampf(kg / HEAVY, 0.0, 1.0))

## Kg of `utensil` (a brewery.json entry) with `load_kg` in it.
static func weight(utensil: Dictionary, load_kg: float) -> float:
	return float(WEIGHTS.get(utensil.kind, 2.0)) + load_kg

## Where `utensil` lands when put down at `aim` on a face of `normal`:
## {at (Vector3), anchor (the id of the place it took, "" for none)}; {} when
## it cannot stand there. `anchors` are brewery.json's.
static func place(utensil: Dictionary, aim: Vector3, normal: Vector3, anchors: Array) -> Dictionary:
	var home := _vector(utensil.at)
	if home.distance_to(aim) <= SNAP:
		return {"at": home, "anchor": ""}
	var kind := snaps_to(str(utensil.id))
	if kind != "":
		for anchor: Dictionary in anchors:
			# A place may be aimed at elsewhere than where the thing's origin goes.
			var spot := _vector(anchor.get("aim", anchor.at))
			var rise := aim.y - spot.y
			if anchor.kind == kind and Vector2(aim.x - spot.x, aim.z - spot.z).length() <= SNAP and rise >= -SNAP and rise <= RISE:
				return {"at": _vector(anchor.at), "anchor": str(anchor.id), "yaw": float(anchor.get("yaw", 0.0))}
	if normal.y < FLAT:
		return {}
	return {"at": aim, "anchor": ""}

## The place of its own `utensil` snaps to on a line of sight that meets
## nothing within `reach` (the hook over the hoist's open shaft): the
## nearest anchor of its kind within SNAP of the line, {} when none. `from`
## and `toward` (a unit vector) are in the building's frame.
static func on_ray(utensil: Dictionary, from: Vector3, toward: Vector3, reach: float, anchors: Array) -> Dictionary:
	var kind := snaps_to(str(utensil.id))
	var best := INF
	var found := {}
	if kind == "":
		return found
	for anchor: Dictionary in anchors:
		var spot := _vector(anchor.get("aim", anchor.at))
		var along := (spot - from).dot(toward)
		var off := spot.distance_to(from + toward * along)
		if anchor.kind == kind and along > 0.0 and along <= reach and off <= SNAP and along < best:
			best = along
			found = {"at": _vector(anchor.at), "anchor": str(anchor.id), "yaw": float(anchor.get("yaw", 0.0))}
	return found

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
