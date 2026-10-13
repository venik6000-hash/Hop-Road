class_name TavernPortals
extends Node
## The outdoors as the tavern's rooms see it: only through the openings of
## the shell (the `portals` of the interior's table: every window and outer
## door on every floor, the middle of each on the wall's line, the wall's
## normal into the building, the clear width, sill and top).
##
## While the eye is in a room, each opening gives a wedge: the eye's point and
## the opening's rectangle, carried on without end. What stands outside every
## wedge cannot be seen, and the systems outdoors do not draw it: the trees'
## and the grass's tiles ask `sight` themselves (they come and go as the eye
## walks), the stones, the old map's pieces and the village's buildings are
## looked over here. What is not seen but throws its shadow into a wedge or
## onto the building keeps casting it. Glass is seen through; a door's leaf
## standing shut closes what it covers of its opening. Walls between the eye
## and an opening are not asked about: an opening of another room gives its
## wedge all the same. The floors are (the table's `portal_floors`: the
## height of each and the one hole in it, the stairs' or the hatch's): an
## opening of another storey is seen only through the holes between.
##
## The wedges are those of an eye anywhere within a step of where it was
## looked from (step_at(): longer the further the openings are), so they
## hold until it has moved that far; `revision` counts every change.
## Outdoors, in a doorway's depth and under another camera nothing is hidden.

## One switch for an A/B in a window: off, everything is drawn as outdoors.
static var enabled := true
## Set, a line of counts goes to the log once a second.
static var debug := false
## The portals of the level that runs, for the systems outdoors; null without
## a tavern (the tools that build a part of the level alone).
static var current: TavernPortals
## The reach of the sun's shadows the render tier asks for, m; 0 until
## RenderQuality has named it.
static var tier_shadow_reach := 0.0

## The eye is looked from again once it has moved a step: STEP_SHARE of its
## distance to the nearest opening, between STEP_NEAR and STEP_FAR (m). The
## wedges hold for an eye within that step and SLACK more (the camera moves
## with the physics step, before this node's turn in the frame). A longer
## step is fewer looks and wider wedges: seen from d metres an opening
## grows by the angle asin(step / d) on each side.
const STEP_SHARE := 0.12
const STEP_NEAR := 0.3
const STEP_FAR := 0.9
const SLACK := 0.05
## An opening is taken this much wider and taller (m, each side): the frame's
## rebate and the joints of its dressed stones.
const FRAME := 0.15
## Half the thickest wall, m: what stands this far behind an opening's line
## is in the wall, not outdoors.
const WALL := 0.5
## An eye nearer an opening's line than its step and this (m) sees the
## whole outdoors on that side of the wall.
const NEAR := 0.05
## Parts of the full turn the eye's surroundings are told apart by, to pass
## over the wedges that look elsewhere.
const SECTORS := 60
const EVERYWHERE := (1 << SECTORS) - 1
## From indoors the sun's shadows are drawn this far (m) at most: the
## performance tier's reach.
const SHADOW_REACH := 90.0
## A shadow is followed down to this far under its caster's foot (m), with a
## sun no lower than LOWEST_SUN (the sine of its height) and no further than
## LONGEST_SHADOW (m).
const SHADOW_DROP := 15.0
const LOWEST_SUN := 0.05
const LONGEST_SHADOW := 400.0
## The light has turned this much (its direction's change): look again.
const SUN_STEP := 0.01
## The shadow map's reach is a depth along the view: at the picture's corner
## the same depth lies this many times as far from the eye.
const REACH_SLANT := 1.6
## A door's leaf hangs in an opening when its hinge is this near the jamb, m.
const HINGE_REACH := 0.5
## Leaves fill an opening when they fall short of its width, or of its top,
## by no more than this (m): the frame they shut against.
const LEAF_GAP := 0.25
## Leaves stand shut when less than this of their swing is left (an angle
## held by a node comes back rounded).
const SHUT := 0.001
## The old map's pieces are looked over by squares of this side, m.
const WATCH_CELL := 48.0
## What stands this near the building (m) is left alone: it is seen from the
## doorways and the yard's side of the walls too.
const KEEP := 1.0
## A village building is drawn while a wedge comes this near it (m): the
## reach of the lamps it hangs out.
const LAMP_REACH := 10.0
## Seconds between two lines of the log (see `debug`).
const LOG_EVERY := 1.0

## What a thing outdoors is to an eye indoors.
enum {SHOWN, SHADOW_ONLY, HIDDEN}

var tavern: TavernSystem
## The rooms an eye must be in for anything to be hidden (world space);
## the tavern's own unless set.
var rooms: Array[AABB] = []
var sight := Sight.new()
## Counts up whenever `sight` changes: who hides by it looks again.
var revision := 0
## For the log: what each system hides, by its name: (hidden, of how many).
var counts := {}
## The last look over the watched things, us.
var cull_usec := 0

var _openings: Array[Dictionary] = []   # {name, centre, inward, half, sill, top, doors, leaf_top}
var _floors: Array[Dictionary] = []     # {height, hole}: the hole a Rect2 of x and z
var _looked_from := Vector3.INF
var _looked_shut := -1
var _looked_light := Vector3.ZERO
## The stones, the old map's pieces and the buildings, by squares of
## WATCH_CELL: {box, casts, things}, each thing {node, centre, half, cast,
## state}; `cast` is the node's own shadow setting, -1 for a building.
var _watched := {}
var _watched_key := -1
var _logged := 0.0

## What an eye sees of the outdoors: the wedges, as planes whose normals look
## into them, and the light that throws the shadows.
class Sight extends RefCounted:
	## False outdoors: everything is seen.
	var active := false
	var eye := Vector3.ZERO
	## Toward the light that casts the shadows; zero when none does.
	var to_light := Vector3.ZERO
	## What is seen with no opening between and takes shadows: the building.
	var indoors := AABB()
	## No shadow is drawn further from the eye than this, m.
	var shadow_reach := INF
	## The eye may move this far from `eye` before it is looked from again, m.
	var step := 0.0
	## A plane holds the points p with normal.dot(p) > offset; `spreads` are
	## the normals without their signs. A wedge's planes stand in the order
	## they are likeliest to part a box from it: the jambs first.
	var normals := PackedVector3Array()
	var spreads := PackedVector3Array()
	var offsets := PackedFloat64Array()
	## The first plane of each wedge, and one more entry that closes the last.
	var first := PackedInt32Array([0])
	## The parts of the turn each wedge lies in (bits of SECTORS), and all of them.
	var sectors := PackedInt64Array()
	var covered := 0
	## The wedges that lie in the sectors of a mask, by mask, as they are asked for.
	var _facing := {}

	func wedge_count() -> int:
		return sectors.size()

	## The wedges that share a sector with `mask`.
	func facing(mask: int) -> PackedInt32Array:
		if _facing.has(mask):
			return _facing[mask]
		var found := PackedInt32Array()
		for wedge in sectors.size():
			if sectors[wedge] & mask != 0:
				found.append(wedge)
		_facing[mask] = found
		return found

	## Adds what an eye within `slack` of `eye` sees through an upright
	## rectangle on a wall's line: `centre` on that line, `inward` the wall's
	## normal toward the eye's side, between the heights `sill` and `top`.
	## `through` names the floors between the eye and the opening ({height,
	## hole}): the eye sees it through their holes alone.
	func add_wedge(centre: Vector3, inward: Vector3, half_width: float, sill: float, top: float, slack: float,
			through: Array[Dictionary] = []) -> void:
		var mask := TavernPortals.EVERYWHERE
		var depth := inward.dot(eye - centre)
		# An eye in the opening's depth, or past it, is given that whole side.
		if depth > slack + TavernPortals.NEAR:
			var across := Vector3.UP.cross(inward).normalized()
			var middle := Vector3(centre.x, (sill + top) * 0.5, centre.z)
			var bearing := atan2(middle.z - eye.z, middle.x - eye.x)
			var low := 0.0
			var high := 0.0
			for side in 4:
				# The two jambs, then the sill and the head.
				var upright := side < 2
				var along := Vector3.UP if upright else across
				var reach := across * half_width if upright else Vector3.UP * ((top - sill) * 0.5)
				var at := middle + reach * (1.0 if side & 1 else -1.0)
				_add_plane(TavernPortals.edge_normal(eye, at, along, middle, slack), at)
				if upright:
					var flat := Vector2(at.x - eye.x, at.z - eye.z)
					var turn := angle_difference(bearing, flat.angle())
					var spread := asin(minf(slack / flat.length(), 1.0))
					if turn < 0.0:
						low = turn - spread
					else:
						high = turn + spread
			mask = TavernPortals.sector_mask(bearing + low, bearing + high)
		for slab: Dictionary in through:
			var height: float = slab.height
			# An eye at the floor's own height is in the hole or looks along it.
			if absf(eye.y - height) <= slack + TavernPortals.NEAR:
				continue
			var hole: Rect2 = slab.hole
			var heart := Vector3(hole.get_center().x, height, hole.get_center().y)
			for side in 4:
				var along := Vector3.RIGHT if side < 2 else Vector3.BACK
				var reach := Vector3.BACK * (hole.size.y * 0.5) if side < 2 else Vector3.RIGHT * (hole.size.x * 0.5)
				var at := heart + reach * (1.0 if side & 1 else -1.0)
				_add_plane(TavernPortals.edge_normal(eye, at, along, heart, slack), at)
		# Nothing outdoors stands on the room's side of the wall.
		_add_plane(-inward, centre + inward * TavernPortals.WALL)
		first.append(normals.size())
		sectors.append(mask)
		covered |= mask

	func _add_plane(normal: Vector3, through: Vector3) -> void:
		normals.append(normal)
		spreads.append(normal.abs())
		offsets.append(normal.dot(through))

	## Whether any part of the box (its middle, half its size) can be seen.
	func sees(centre: Vector3, half: Vector3) -> bool:
		if not active:
			return true
		var mask := TavernPortals.sector_of(eye, centre, half)
		if mask & covered == 0:
			return false
		for wedge: int in facing(mask):
			var inside := true
			for plane in range(first[wedge], first[wedge + 1]):
				if normals[plane].dot(centre) + spreads[plane].dot(half) <= offsets[plane]:
					inside = false
					break
			if inside:
				return true
		return false

	func sees_box(box: AABB) -> bool:
		return sees(box.get_center(), box.size * 0.5)

	## Whether any part of a sphere can be seen (asked of the cube round it).
	func sees_sphere(centre: Vector3, radius: float) -> bool:
		return sees(centre, Vector3.ONE * radius)

	## The way the shadow of a thing `height` m tall goes, down to SHADOW_DROP
	## under its foot.
	func shadow_of(height: float) -> Vector3:
		if to_light == Vector3.ZERO:
			return Vector3.ZERO
		return -to_light * minf((height + TavernPortals.SHADOW_DROP) / maxf(to_light.y, TavernPortals.LOWEST_SUN),
			TavernPortals.LONGEST_SHADOW)

	## Whether the box, or the shadow it throws, reaches anything seen: a
	## wedge, the building or its rooms.
	func shaded_by(centre: Vector3, half: Vector3) -> bool:
		if not active:
			return true
		var sweep := shadow_of(half.y * 2.0)
		if shadow_reach < INF and Geometry3D.get_closest_point_to_segment(eye, centre, centre + sweep).distance_to(eye) \
				> shadow_reach + half.length():
			return false
		if TavernPortals.sweep_meets(centre, half, sweep, indoors):
			return true
		var mask := TavernPortals.sector_of(eye, centre + sweep * 0.5, half + sweep.abs() * 0.5)
		if mask & covered == 0:
			return false
		for wedge: int in facing(mask):
			var inside := true
			for plane in range(first[wedge], first[wedge + 1]):
				var normal := normals[plane]
				if normal.dot(centre) + spreads[plane].dot(half) + maxf(normal.dot(sweep), 0.0) <= offsets[plane]:
					inside = false
					break
			if inside:
				return true
		return false

	## What the box is to the eye: SHOWN, SHADOW_ONLY (unseen, but `casts`
	## and its shadow is seen) or HIDDEN.
	func verdict(centre: Vector3, half: Vector3, casts: bool) -> int:
		if sees(centre, half):
			return TavernPortals.SHOWN
		if casts and shaded_by(centre, half):
			return TavernPortals.SHADOW_ONLY
		return TavernPortals.HIDDEN

	## Whether any square of a quadtree over the ground (its corner `origin`,
	## x and z, and `size`, split down to `leaf` m) is seen between the heights
	## `low` and `high` where `holds` (x, z, size) says the square has what is
	## asked about: the lake's water.
	func sees_ground(origin: Vector2, size: float, low: float, high: float, leaf: float, holds: Callable) -> bool:
		if not active:
			return true
		if not holds.call(origin.x, origin.y, size):
			return false
		var half := size * 0.5
		if not sees(Vector3(origin.x + half, (low + high) * 0.5, origin.y + half), Vector3(half, (high - low) * 0.5, half)):
			return false
		if size <= leaf:
			return true
		for quarter in 4:
			var corner := origin + Vector2(half if quarter & 1 else 0.0, half if quarter & 2 else 0.0)
			if sees_ground(corner, half, low, high, leaf, holds):
				return true
		return false

## The normal, looking into the wedge, of the plane through an opening's edge
## (the point `at` on it, its direction `along`) that bounds what eyes within
## `slack` of `eye` see past that edge; `inside` is the opening's middle.
static func edge_normal(eye: Vector3, at: Vector3, along: Vector3, inside: Vector3, slack: float) -> Vector3:
	var to_eye := eye - at
	to_eye -= along * to_eye.dot(along)
	var distance := to_eye.length()
	var toward := to_eye / distance
	var normal := along.cross(toward)
	if normal.dot(inside - at) < 0.0:
		normal = -normal
	# Seen past an edge, the far side of the eye's slack looks widest: the
	# plane leans away from the eye until that side touches it.
	var lean := minf(slack / distance, 1.0)
	return normal * sqrt(1.0 - lean * lean) - toward * lean

## The bits of the SECTORS between the bearings `from` and `to` (radians).
static func sector_mask(from: float, to: float) -> int:
	var start := floori(from / TAU * SECTORS)
	var count := floori(to / TAU * SECTORS) - start + 1
	if count >= SECTORS:
		return EVERYWHERE
	var bits := (1 << count) - 1
	var turn := posmod(start, SECTORS)
	return ((bits << turn) | (bits >> (SECTORS - turn))) & EVERYWHERE

## The sectors a box lies in for `eye`.
static func sector_of(eye: Vector3, centre: Vector3, half: Vector3) -> int:
	var x := centre.x - eye.x
	var z := centre.z - eye.z
	# Which side of the eye the box lies on, along x and along z; 0: astride.
	var side_x := signf(x) if absf(x) > half.x else 0.0
	var side_z := signf(z) if absf(z) > half.z else 0.0
	if side_x == 0.0 and side_z == 0.0:
		return EVERYWHERE
	# The two corners the eye sees it between.
	var from := 0.0
	var to := 0.0
	if side_z == 0.0:
		from = atan2(z - half.z, x - side_x * half.x)
		to = atan2(z + half.z, x - side_x * half.x)
	elif side_x == 0.0:
		from = atan2(z - side_z * half.z, x - half.x)
		to = atan2(z - side_z * half.z, x + half.x)
	else:
		from = atan2(z + side_z * half.z, x - side_x * half.x)
		to = atan2(z - side_z * half.z, x + side_x * half.x)
	var turn := angle_difference(from, to)
	return sector_mask(from, from + turn) if turn >= 0.0 else sector_mask(to, to - turn)

## Whether a box carried along `sweep` may pass through `target`.
static func sweep_meets(centre: Vector3, half: Vector3, sweep: Vector3, target: AABB) -> bool:
	var middle := target.get_center()
	var reach := target.size * 0.5
	var between := middle - centre
	for axis in 3:
		var low: float = minf(sweep[axis], 0.0) - half[axis] - reach[axis]
		var high: float = maxf(sweep[axis], 0.0) + half[axis] + reach[axis]
		if between[axis] < low or between[axis] > high:
			return false
	# Across its way the sweep is no wider than the box.
	var flat := Vector3(-sweep.z, 0.0, sweep.x)
	if flat.length_squared() > 1e-6:
		flat = flat.normalized()
		for across: Vector3 in [flat, sweep.cross(flat).normalized()]:
			if absf(across.dot(between)) > across.abs().dot(half) + across.abs().dot(reach):
				return false
	return true

## A leaf's width and the height of its top (m), from the leaf's own mesh.
static func leaf_measure(door: TavernDoor) -> Vector2:
	var item: MeshInstance3D = null
	if door.get_child_count() > 0:
		item = door.get_child(0) as MeshInstance3D
	if item == null or item.mesh == null:
		return Vector2.ZERO
	var box := item.transform * item.mesh.get_aabb()
	return Vector2(maxf(box.size.x, box.size.z), door.position.y + box.end.y)

func _enter_tree() -> void:
	current = self
	# For a look at the running game: `-- --portals-off`, `-- --portals-debug`.
	var asked := OS.get_cmdline_user_args()
	if "--portals-off" in asked:
		enabled = false
	if "--portals-debug" in asked:
		debug = true
	# Before every system that asks `sight` in its own _process.
	process_priority = -100

func _exit_tree() -> void:
	_release()
	if current == self:
		current = null

## Adds the openings of one table (its `portals`) and the floors between
## the storeys (its `portal_floors`).
func add(rows: Array, floors: Array = []) -> void:
	for row: Dictionary in floors:
		var hole := Rect2()
		for corners: Array in row.holes:
			var one := Rect2(float(corners[0]), float(corners[1]), float(corners[2]) - float(corners[0]),
				float(corners[3]) - float(corners[1]))
			hole = hole.merge(one) if hole.has_area() else one
		_floors.append({"height": float(row.height), "hole": hole.grow(FRAME)})
	for row: Dictionary in rows:
		var p: Array = row.position
		var n: Array = row.inward
		var opening := {"name": str(row.name), "centre": Vector3(p[0], p[1], p[2]), "inward": Vector3(n[0], n[1], n[2]),
			"half": float(row.width) * 0.5, "sill": float(row.sill), "top": float(row.top)}
		opening.doors = _leaves_in(opening)
		opening.leaf_top = _filled_to(opening)
		_openings.append(opening)
	_looked_from = Vector3.INF

## The leaves of the tavern's doors that hang in `opening`.
func _leaves_in(opening: Dictionary) -> Array[TavernDoor]:
	var leaves: Array[TavernDoor] = []
	if tavern == null:
		return leaves
	var inward: Vector3 = opening.inward
	var across := Vector3.UP.cross(inward).normalized()
	for door: TavernDoor in tavern.doors:
		var hinge: Vector3 = door.position - opening.centre
		if absf(hinge.dot(across)) < float(opening.half) + HINGE_REACH and absf(hinge.dot(inward)) < WALL + HINGE_REACH \
				and door.position.y > float(opening.sill) - HINGE_REACH and door.position.y < float(opening.top):
			leaves.append(door)
	return leaves

## The height up to which the leaves of `opening`, shut, fill it: its sill
## when they are too narrow for it or it has none.
func _filled_to(opening: Dictionary) -> float:
	var leaves: Array[TavernDoor] = opening.doors
	var width := 0.0
	var top := INF
	for door: TavernDoor in leaves:
		var measure := leaf_measure(door)
		width += measure.x
		top = minf(top, measure.y)
	if leaves.is_empty() or width < float(opening.half) * 2.0 - LEAF_GAP:
		return float(opening.sill)
	return top

## Hangs `door` in the opening called `opening_name` (the tests' way; the
## game finds the leaves by their hinges).
func hang(opening_name: String, door: TavernDoor) -> void:
	for opening: Dictionary in _openings:
		if opening.name == opening_name:
			(opening.doors as Array[TavernDoor]).append(door)
			opening.leaf_top = _filled_to(opening)

func opening_count() -> int:
	return _openings.size()

## Whether an eye at `eye` is in a room.
func is_inside(eye: Vector3) -> bool:
	if rooms.is_empty() and tavern != null:
		rooms = tavern.room_boxes()
	for room: AABB in rooms:
		if room.has_point(eye):
			return true
	return false

## How far an eye at `eye` may move before it is looked from again, m.
func step_at(eye: Vector3) -> float:
	var nearest := INF
	for opening: Dictionary in _openings:
		nearest = minf(nearest, eye.distance_to(opening.centre) - float(opening.half))
	return clampf(nearest * STEP_SHARE, STEP_NEAR, STEP_FAR)

## What an eye within a step of `eye` sees of the outdoors, with shadows
## thrown by a light toward `to_light` (zero: none) no further than
## `shadow_reach` m from the eye, as the doors stand.
func look(eye: Vector3, to_light: Vector3, building: AABB, shadow_reach := INF) -> Sight:
	var seen := Sight.new()
	seen.active = true
	seen.eye = eye
	seen.step = step_at(eye)
	seen.to_light = to_light
	seen.indoors = building
	seen.shadow_reach = shadow_reach
	for opening: Dictionary in _openings:
		var sill: float = opening.sill - FRAME
		var top: float = opening.top + FRAME
		if not (opening.doors as Array).is_empty() and TavernDaylight.openness(opening) < SHUT:
			# Shut leaves leave what is over them: an arch's head.
			sill = maxf(sill, float(opening.leaf_top))
			if sill > top - FRAME - LEAF_GAP:
				continue
		var centre: Vector3 = opening.centre
		var through: Array[Dictionary] = []
		for slab: Dictionary in _floors:
			if (eye.y < float(slab.height)) != (centre.y < float(slab.height)):
				through.append(slab)
		seen.add_wedge(centre, opening.inward, float(opening.half) + FRAME, sill, top, seen.step + SLACK, through)
	return seen

## The openings whose leaves stand shut, as bits.
func _shut() -> int:
	var bits := 0
	for number in _openings.size():
		var opening: Dictionary = _openings[number]
		if not (opening.doors as Array).is_empty() and TavernDaylight.openness(opening) < SHUT:
			bits |= 1 << number
	return bits

## Toward the light that throws shadows now: the sun, or the moon at night.
func _light() -> Vector3:
	var sky := tavern.sky_system if tavern != null else null
	if sky == null:
		return Vector3.ZERO
	if sky.sun.visible and sky.sun.shadow_enabled:
		return sky.sun_direction
	if sky.moon.visible and sky.moon.shadow_enabled:
		return sky.moon_direction
	return Vector3.ZERO

## The rain's shelter map is drawn once, from above, in the level's first
## frames: nothing may be hidden from it.
func _shelter_drawing() -> bool:
	var shelter := tavern.get_parent().get_node_or_null("RainShelter") as RainShelter
	return shelter != null and shelter.is_processing()

func _process(delta: float) -> void:
	if debug:
		_logged += delta
		if _logged >= LOG_EVERY:
			_logged = 0.0
			print(report())
	var camera := get_viewport().get_camera_3d()
	var inside := enabled and camera != null and tavern != null and not _openings.is_empty() \
		and is_inside(camera.global_position) and not _shelter_drawing()
	if not inside:
		if sight.active:
			sight = Sight.new()
			_looked_from = Vector3.INF
			_changed(true)
		return
	var eye := camera.global_position
	var shut := _shut()
	var light := _light()
	if not sight.active or eye.distance_to(_looked_from) >= sight.step or shut != _looked_shut \
			or light.distance_to(_looked_light) >= SUN_STEP:
		var entered := not sight.active
		_looked_from = eye
		_looked_shut = shut
		_looked_light = light
		# Until the render tier has named its reach the lamps keep their own.
		var reach := reach_for(tier_shadow_reach, true) * REACH_SLANT if tier_shadow_reach > 0.0 else INF
		sight = look(eye, light, tavern.global_transform * TavernSystem.BUILDING_BOUNDS, reach)
		_changed(entered)

## `sight` is another: the watched things are looked over, and at a doorway
## the sun's shadows take the reach of the side the eye is on.
func _changed(crossed: bool) -> void:
	revision += 1
	if crossed and tier_shadow_reach > 0.0 and tavern.sky_system != null:
		set_shadow_reach(tavern.sky_system, tier_shadow_reach)
	var start := Time.get_ticks_usec()
	if sight.active:
		_collect()
	_cull()
	cull_usec = Time.get_ticks_usec() - start

## The reach of the sun's shadows (m) for a render tier that asks for
## `reach`: less for an eye in the rooms.
static func reach_for(reach: float, indoors: bool) -> float:
	return minf(reach, SHADOW_REACH) if indoors else reach

## Gives the sun and the moon the reach of their shadows: the render tier's
## (`reach`, m) outdoors, SHADOW_REACH at most for an eye in the rooms.
static func set_shadow_reach(sky: SkySystem, reach: float) -> void:
	tier_shadow_reach = reach
	var distance := reach_for(reach, current != null and current.sight.active)
	for light: DirectionalLight3D in [sky.sun, sky.moon]:
		light.directional_shadow_max_distance = distance
	# Past the shadow map the trees' shadow is the canopy field's
	# (src/vegetation/shaders/canopy.gdshaderinc).
	RenderingServer.global_shader_parameter_set("sun_shadow_reach",
		Vector2(sky.sun.directional_shadow_fade_start, 1.0) * distance)

## Takes under watch what stands still outdoors and holds its own place: the
## stones, the old map's pieces, each village building as one. Again whenever
## the level has other children than at the last look.
func _collect() -> void:
	var level := tavern.get_parent()
	var key := level.get_child_count()
	for child: Node in level.get_children():
		if child is RockField or child.name == &"Map":
			key = key * 31 + child.get_child_count()
	if key == _watched_key:
		return
	_release()
	_watched_key = key
	var keep := (tavern.global_transform * TavernSystem.BUILDING_BOUNDS).grow(KEEP)
	for child: Node in level.get_children():
		if child is VillageBuilding:
			var building := child as VillageBuilding
			# The lighthouse's beam reaches far past its tower: it stays.
			if building.visible and building.optic == null and building.bounds.has_volume():
				_watch(building, building.bounds.grow(LAMP_REACH), -1, keep)
		elif child is RockField or child.name == &"Map":
			for item: GeometryInstance3D in child.find_children("*", "GeometryInstance3D", true, false):
				if not item.is_visible_in_tree():
					continue
				if item is MeshInstance3D and (item as MeshInstance3D).mesh != null:
					_watch(item, item.global_transform * (item as MeshInstance3D).mesh.get_aabb(), item.cast_shadow, keep)
				elif item is MultiMeshInstance3D and (item as MultiMeshInstance3D).multimesh.custom_aabb.has_volume():
					_watch(item, item.global_transform * (item as MultiMeshInstance3D).multimesh.custom_aabb,
						item.cast_shadow, keep)

func _watch(node: Node3D, box: AABB, cast: int, keep: AABB) -> void:
	if box.intersects(keep):
		return
	var middle := box.get_center()
	var key := Vector2i(floori(middle.x / WATCH_CELL), floori(middle.z / WATCH_CELL))
	if not _watched.has(key):
		_watched[key] = {"box": box, "casts": false, "things": []}
	var square: Dictionary = _watched[key]
	square.box = (square.box as AABB).merge(box)
	square.casts = bool(square.casts) or cast != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(square.things as Array).append({"node": node, "centre": middle, "half": box.size * 0.5, "cast": cast, "state": SHOWN})

## Shows or hides each watched thing as `sight` has it: a square nothing of
## which is seen or shades the seen at once, the others thing by thing.
func _cull() -> void:
	var hidden := 0
	var shadows := 0
	var total := 0
	for square: Dictionary in _watched.values():
		var box: AABB = square.box
		var whole := SHOWN
		if sight.active:
			whole = sight.verdict(box.get_center(), box.size * 0.5, bool(square.casts))
		for thing: Dictionary in square.things:
			var cast: int = thing.cast
			var state := whole
			if whole != HIDDEN and sight.active:
				state = sight.verdict(thing.centre, thing.half, cast != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			# A building is many pieces under one node: it is drawn or it is not.
			if cast < 0 and state == SHADOW_ONLY:
				state = SHOWN
			total += 1
			hidden += int(state == HIDDEN)
			shadows += int(state == SHADOW_ONLY)
			if state != int(thing.state):
				_set_state(thing, state)
	counts[&"things"] = Vector2i(hidden, total)
	counts[&"things as shadows"] = Vector2i(shadows, total)

func _set_state(thing: Dictionary, state: int) -> void:
	thing.state = state
	var node: Node3D = thing.node
	if not is_instance_valid(node):
		return
	node.visible = state != HIDDEN
	if int(thing.cast) >= 0:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY \
			if state == SHADOW_ONLY else int(thing.cast)

## Gives every watched thing back as it was and forgets them.
func _release() -> void:
	for square: Dictionary in _watched.values():
		for thing: Dictionary in square.things:
			if int(thing.state) != SHOWN:
				_set_state(thing, SHOWN)
	_watched.clear()
	_watched_key = -1

## The line of the log: the wedges, the openings shut, and what each system
## hides of how many.
func report() -> String:
	var parts := PackedStringArray()
	for system: StringName in counts:
		var count: Vector2i = counts[system]
		parts.append("%s=%d/%d" % [system, count.x, count.y])
	var shut := 0
	if sight.active:
		for number in _openings.size():
			shut += (_looked_shut >> number) & 1
	return "PORTALS active=%s wedges=%d shut=%d revision=%d %s watch=%.2fms" % [sight.active, sight.wedge_count(), shut,
		revision, " ".join(parts), cull_usec / 1000.0]
