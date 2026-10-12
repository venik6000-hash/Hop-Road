class_name BuildingMachinery
extends Node3D
## What moves in a village building, by its table.
##
## `turning` (the mill): the shafts the water wheel drives. The builder marks
## the pieces of a shaft (`mill_turning`: its id), stands their origins on its
## axis and gives the axis, through `centre`, and the shaft's turns to one of
## the wheel (`ratio`; `rpm` at the wheel's own pace), signed, right-handed
## about the axis. The wheel runs day and night, as its water does; a shaft
## with a `clutch` (the hoist) stands.
##
## `moving` (the smithy): pieces a hand works (`tav_moving`: their id), by
## `group`. Pieces that `swing` about their axis or `slide` along it are
## pulled in strokes, `travel` (radians, metres) at the end of one: the
## bellows, whose lung a stroke shuts and lets fall open again. A piece that
## `spin`s is a wheel that runs down from a push: the grindstone. work() is
## the hand. Where a piece names the place a hand takes hold of it (`hand`),
## a WorkHandle stands for its group there, for the player's hand; it goes
## by the title of the table's station named as the group.

## Seconds a stroke takes, and the share of it that is the pull.
const STROKE := 2.6
const PULL := 0.4
## Strokes one working of a pull gives.
const STROKES := 4
## How fast the air a pull blows comes up, and how fast it dies down, 1/s.
const DRAUGHT_RISE := 2.5
const DRAUGHT_FALL := 0.45
## A wheel spun by hand: radians a second from a push, the seconds over which
## it loses all but 1/e of them, and the pace under which it stands.
const SPIN := 9.0
const RUN_DOWN := 3.5
const STANDS := 0.2

## The wheel's turns since the building loaded.
var turns := 0.0

var _wheel_rpm := 0.0
var _pivots := {}                     # id -> Node3D the pieces of that id hang on
var _shafts: Array[Dictionary] = []   # {pivot, axis, ratio}
var _parts: Array[Dictionary] = []    # {pivot, origin, axis, kind, travel, group}
var _groups := {}                     # group -> {spins, strokes, phase, shut, draught, speed, angle, moved}

## Stands in the building's frame; `table` is the building's.
func configure(table: Dictionary) -> void:
	for shaft: Dictionary in table.get("turning", []):
		if shaft.clutch:
			continue
		_shafts.append({"pivot": _pivot(str(shaft.id), shaft.centre), "axis": _vector(shaft.axis).normalized(),
			"ratio": float(shaft.ratio)})
		_wheel_rpm = float(shaft.rpm) / float(shaft.ratio)
	var titles := {}
	for station: Dictionary in table.get("stations", []):
		titles[str(station.id)] = str(station.title)
	var spinning := {}
	for part: Dictionary in table.get("moving", []):
		if str(part.kind) == "spin":
			spinning[str(part.group)] = true
	for part: Dictionary in table.get("moving", []):
		var group := str(part.group)
		var pivot := _pivot(str(part.id), part.pivot)
		_parts.append({"pivot": pivot, "origin": pivot.position, "axis": _vector(part.axis).normalized(),
			"kind": str(part.kind), "travel": float(part.travel), "group": group})
		if not _groups.has(group):
			_groups[group] = {"spins": spinning.has(group), "strokes": 0, "phase": 0.0, "shut": 0.0, "draught": 0.0,
				"speed": 0.0, "angle": 0.0, "moved": false}
		if part.has("hand"):
			var handle := WorkHandle.new()
			handle.name = group.to_pascal_case() + "Handle"
			handle.title = str(titles.get(group, part.title))
			handle.verb = "крутить" if spinning.has(group) else "качать"
			handle.machinery = self
			handle.group = group
			handle.position = _vector(part.hand)
			add_child(handle)
	set_process(not _shafts.is_empty() or not _groups.is_empty())

## Takes the marked pieces of a part scene onto their pivots, where they
## stand; the scene is in the building's frame, as this node is. What moves
## stays out of the lamps' shadow maps: a lamp draws its map again in every
## frame in which a caster in its reach moves (TavernSystem.SHADOW_LAYER).
func take(scene: Node3D) -> void:
	for item: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var extras: Dictionary = item.get_meta("extras", {})
		var id := str(extras.get("mill_turning", extras.get("tav_moving", "")))
		if not _pivots.has(id):
			continue
		var holder: Node3D = _pivots[id]
		var placed := item.transform
		var above := item.get_parent_node_3d()
		while above != null and above != scene.get_parent():
			placed = above.transform * placed
			above = above.get_parent_node_3d()
		item.get_parent().remove_child(item)
		holder.add_child(item)
		item.transform = (transform * holder.transform).affine_inverse() * placed
		item.layers &= ~TavernSystem.SHADOW_LAYER

## The hand on `group`: four strokes of what is pulled, a push to what spins.
func work(group: String) -> void:
	if not _groups.has(group):
		return
	var state: Dictionary = _groups[group]
	if state.spins:
		state.speed = SPIN
	else:
		state.strokes = STROKES

## How hard (0..1) the pulls of `group` blow now: the bellows' air on the fire.
func draught(group: String) -> float:
	return float(_groups[group].draught) if _groups.has(group) else 0.0

## The node the pieces marked `id` hang on, or null.
func pivot(id: String) -> Node3D:
	return _pivots.get(id) as Node3D

## How far shut (0..1) a pull is at `phase` (0..1) of its stroke: it comes
## down over the first PULL of it and is let go over the rest.
static func shut_at(phase: float) -> float:
	return smoothstep(0.0, PULL, phase) * (1.0 - smoothstep(PULL + 0.05, 1.0, phase))

func _process(delta: float) -> void:
	if not _shafts.is_empty():
		turns += _wheel_rpm / 60.0 * delta
		for shaft: Dictionary in _shafts:
			var axis: Vector3 = shaft.axis
			var ratio: float = shaft.ratio
			(shaft.pivot as Node3D).basis = Basis(axis, TAU * fposmod(turns * ratio, 1.0))
	for state: Dictionary in _groups.values():
		_advance(state, delta)
	for part: Dictionary in _parts:
		var state: Dictionary = _groups[part.group]
		if not state.moved:
			continue
		var node: Node3D = part.pivot
		var axis: Vector3 = part.axis
		var travel: float = part.travel
		var shut: float = state.shut
		match str(part.kind):
			"spin":
				node.basis = Basis(axis, float(state.angle))
			"swing":
				node.basis = Basis(axis, travel * shut)
			"slide":
				var origin: Vector3 = part.origin
				node.position = origin + axis * travel * shut

func _advance(state: Dictionary, delta: float) -> void:
	var speed: float = state.speed
	var strokes: int = state.strokes
	var blown: float = state.draught
	state.moved = speed > 0.0 or strokes > 0
	if state.spins:
		state.angle = fposmod(float(state.angle) + speed * delta, TAU)
		speed *= exp(-delta / RUN_DOWN)
		state.speed = speed if speed > STANDS else 0.0
		return
	var phase: float = state.phase
	if strokes > 0:
		phase += delta / STROKE
		if phase >= 1.0:
			phase -= 1.0
			strokes -= 1
		if strokes == 0:
			phase = 0.0
		state.phase = phase
		state.strokes = strokes
		state.shut = BuildingMachinery.shut_at(phase)
	var pulling := strokes > 0 and phase < PULL
	state.draught = move_toward(blown, 1.0 if pulling else 0.0, delta * (DRAUGHT_RISE if pulling else DRAUGHT_FALL))

func _pivot(id: String, at: Array) -> Node3D:
	var node := Node3D.new()
	node.name = id.to_pascal_case()
	node.position = _vector(at)
	add_child(node)
	_pivots[id] = node
	return node

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
