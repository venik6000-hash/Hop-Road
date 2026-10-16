class_name BrewHands
extends RefCounted
## Where the brewer's hands go (docs/plans/brewing.md, stage 7): on the thing
## the hand holds, on the moving part a work turns. No graphics: BrewArms puts
## the arms there.
##
## A hand is {side (RIGHT, LEFT), at, clip}. `at` is the middle of the bar the
## hand closes on, world space: x along the bar from the index finger to the
## little one, y from the bar to the back of the hand, z = x × y. `clip` is a
## finger clip of brew_hands.glb: "grip" on a handle, "hold" on a body (a sack's
## corner, a keg, a log).

const RIGHT := 0
const LEFT := 1
## Utensils both hands hold by the shaft: metres down the shaft from the grip
## towards the utensil's foot where the left hand takes it.
const SHAFTS := {"mash_paddle": 0.35, "malt_shovel": 0.35, "kiln_rake": 0.35}
## Half the width of a sack's mouth: the hands take its corners.
const SACK_HALF := 0.16
## A lever: a swinging part whose grip is this far from its pivot is held
## along its length (a pump handle).
const LEVER := 0.4
## Pump handles: how far from the grip towards the pivot the left hand takes them.
const LEVER_LEFT := 0.18
## A windlass's crank: the left hand beside the right one along the handle.
const CRANK_LEFT := 0.1
## The left hand under a tipped vessel's bottom, this high over its foot.
const UNDER := 0.04
## The fishing rod (lakeside_rod.gd): metres from its butt up to the right
## hand; the left hand under the reel, the rod's frame.
const ROD_BUTT := 0.06
const ROD_REEL := Vector3(0.035, -0.07, -0.05)
## A thing on the left palm (the baked potato): metres from its middle down to the palm.
const PALM := 0.07

## The hands on utensil `id` of the brewery's table (`entry`: {kind, at, grip},
## building frame) whose node stands at `node` (world; its origin at `at`).
## `tipping`: it is tipped at a station (the left hand goes under it);
## `working`: at a station (a shaft is carried in one hand, worked in two).
static func on_utensil(id: String, entry: Dictionary, node: Transform3D, shoulders: Array[Vector3],
		right: Vector3, tipping := false, working := false) -> Array[Dictionary]:
	var foot := node.origin
	var grip := node * (_vector(entry.grip) - _vector(entry.at))
	var shaft := grip - foot
	var hands: Array[Dictionary] = []
	match str(entry.kind):
		"sack":
			# By the corners of its mouth, one to each side of the body.
			var across := Vector3.UP.cross(right)
			hands.append(hand(RIGHT, grip + right * SACK_HALF, across, shoulders[RIGHT], right, "hold"))
			hands.append(hand(LEFT, grip - right * SACK_HALF, across, shoulders[LEFT], right, "hold"))
			return hands
		"vessel":
			if id.begins_with("keg_"):
				# A keg by its two heads: the foot is on one, the grip in the
				# middle, the other head as far beyond it. The right hand takes
				# the head on the body's right.
				var heads: Array[Vector3] = [foot, grip * 2.0 - foot]
				if heads[0].dot(right) > heads[1].dot(right):
					heads.reverse()
				hands.append(hand(RIGHT, heads[1], Vector3.UP, shoulders[RIGHT], right, "hold"))
				hands.append(hand(LEFT, heads[0], Vector3.UP, shoulders[LEFT], right, "hold"))
				return hands
			hands.append(hand(RIGHT, grip, node.basis.x, shoulders[RIGHT], right, "grip"))
		"log":
			hands.append(hand(RIGHT, grip, node.basis.x, shoulders[RIGHT], right, "hold"))
		"raw":
			hands.append(hand(RIGHT, grip, node.basis.x, shoulders[RIGHT], right, "grip"))
		_:
			# A tool or an instrument: by its shaft, which runs from the grip to the foot.
			var along := shaft if shaft.length() > 0.05 else node.basis.x
			hands.append(hand(RIGHT, grip, along, shoulders[RIGHT], right, "grip"))
			if SHAFTS.has(id) and working:
				var lower := grip + (foot - grip).normalized() * float(SHAFTS[id])
				hands.append(hand(LEFT, lower, along, shoulders[LEFT], right, "grip"))
	if tipping and str(entry.kind) in ["vessel", "raw"]:
		hands.append(hand(LEFT, foot + Vector3.UP * UNDER, right, shoulders[LEFT], right, "hold", true))
	return hands

## The hands on moving part `entry` of the table ({kind, pivot, axis, grip},
## building frame) whose pivot node stands at `pivot` (world). `both`: the
## work wants both hands (a pump, a windlass).
static func on_part(entry: Dictionary, pivot: Transform3D, shoulders: Array[Vector3], right: Vector3,
		both := false) -> Array[Dictionary]:
	var lever := _vector(entry.grip) - _vector(entry.pivot)
	var grip := pivot * lever
	var axis := (pivot.basis * _vector(entry.axis)).normalized()
	var arm := pivot.basis * lever
	var bar := axis
	match str(entry.kind):
		"swing":
			if lever.length() >= LEVER:
				bar = arm
			elif absf(lever.normalized().dot(_vector(entry.axis).normalized())) > 0.9:
				# A tap's key over its plug: its cross-piece is taken across the view.
				bar = right
		"slide":
			bar = axis.cross(Vector3.UP)
			if bar.length() < 0.1:
				bar = right
	var hands: Array[Dictionary] = [hand(RIGHT, grip, bar, shoulders[RIGHT], right, "grip")]
	if both:
		var second := grip + bar.normalized() * CRANK_LEFT if str(entry.kind) == "spin" else grip.lerp(pivot.origin, LEVER_LEFT)
		hands.append(hand(LEFT, second, bar, shoulders[LEFT], right, "grip"))
	return hands

## The hands on the fishing rod whose butt stands at `rod` (world) with its
## tip at `tip`: the right on the butt, the left on the reel.
static func on_rod(rod: Transform3D, tip: Vector3, shoulders: Array[Vector3], right: Vector3) -> Array[Dictionary]:
	var along := (tip - rod.origin).normalized()
	return [hand(RIGHT, rod.origin + along * ROD_BUTT, along, shoulders[RIGHT], right, "grip"),
		hand(LEFT, rod * ROD_REEL, rod.basis.x, shoulders[LEFT], right, "grip")]

## The left hand palm up under a thing whose middle is at `point` (the baked potato).
static func on_palm(point: Vector3, shoulders: Array[Vector3], right: Vector3) -> Array[Dictionary]:
	return [hand(LEFT, point + Vector3.DOWN * PALM, right, shoulders[LEFT], right, "hold", true)]

## A hand of `side` on a bar at `point` running along `along` (either way),
## the arm coming from `shoulder`; `right` is the body's right. Over the bar
## (the back of the hand up and away from the body) unless `under` (the palm
## up, a vessel's bottom on it). The fingers run down the bar and out to the
## hand's own side, as an arm reaching from the shoulder takes a bar.
static func hand(side: int, point: Vector3, along: Vector3, shoulder: Vector3, right: Vector3, clip: String,
		under := false) -> Dictionary:
	var away := point - shoulder
	away.y = 0.0
	away = away.normalized() if away.length() > 0.001 else right.cross(Vector3.UP)
	var x := along.normalized() if along.length() > 0.001 else right
	var outward := right * (1.0 if side == RIGHT else -1.0)
	if x.dot(Vector3.DOWN * 0.8 + outward * 0.6 - away * 0.3) < 0.0:
		x = -x
	var back := (Vector3.DOWN if under else Vector3.UP) * 0.7 + away * 0.3
	var y := back - x * back.dot(x)
	if y.length() < 0.01:
		y = away - x * away.dot(x)
	y = y.normalized()
	return {"side": side, "at": Transform3D(Basis(x, y, x.cross(y)), point), "clip": clip}

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
