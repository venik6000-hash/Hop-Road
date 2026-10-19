class_name BrewBody
extends Node
## The player's body at the brewery's work (BrewHouse): the held thing before
## the eye or at the station's work (tipped over where it pours, the paddle
## round the vessel, a tool's swing), the arms on what they hold or turn
## (BrewHands, BrewArms), and the body brought to a station's work: stepped
## up to it as near as there is room, crouched to a low one, leant to a bar
## out of the arm's reach, the eye on the work. Points are in the house's
## frame unless a name says world.

## Where a held thing hangs before the eye by its kind (the eye's frame,
## turned with the look but kept upright): within the arms' reach (BrewArms).
const HOLD := {"sack": Vector3(0.0, -0.2, -0.4), "vessel": Vector3(0.2, -0.5, -0.36), "tool": Vector3(0.26, -0.3, -0.4),
	"instrument": Vector3(0.2, -0.22, -0.4), "raw": Vector3(0.2, -0.42, -0.4), "log": Vector3(0.22, -0.38, -0.4)}
## A keg is carried across the body by its two heads, its middle before the
## chest: both heads within the arms' reach.
const KEG_HOLD := Vector3(0.0, -0.45, -0.36)
## Tilt of a tipped thing at full tip, radians.
const TIP := 1.9
## A held tool's swing at its work: the mallet's lift at a full wind-up,
## radians; how far a log or a handful is drawn back, and the shovel pushed
## along its pass, metres.
const STRIKE_LIFT := 1.2
const THROW_BACK := 0.18
const STRIPE_REACH := 0.25
## Seconds the fingers stay open where they let a thrown thing go.
const LET_GO := 0.3
## Where the body stands at a work the hands do away from it (a part, a pour,
## a paddle): this far from the point the right hand takes, short of its
## stand when there is no room; how far the eye may be over that point
## before the body crouches; the deepest crouch, and metres a second of it.
const ARM_STAND := 0.42
const OVER := 0.6
const CROUCH := 0.8
const CROUCH_PACE := 1.5
## How far to the left of a flat crank's middle the body stands.
const FLAT_CRANK_ASIDE := 0.3
## Room the body is tried for, a step at a time back towards the stand and
## on as many bearings round the point; the highest step or stand it gets
## onto there.
const ROOM_STEP := 0.1
const BEARINGS := 16
const STEP_UP := 0.35
## How high over where it pours a basket or a pot is held, tipped sideways.
const SIDE_OVER := 0.15
## How far before the eye a tipped thing is held over where it pours (no
## nearer its middle than a quarter metre); how far the body leans at a
## station to bring the shoulders (and the eye with them) to a bar out of the
## arm's reach, and metres a second of it.
const HOLD_OUT := 0.4
const LEAN := 0.8
const LEAN_PACE := 1.2
## Metres the eye and the shoulders go down for each metre of the lean over
## a low work: the body bows over it.
const BOW := 0.4
## The head's room, metres: the lean keeps the eye this far from a face,
## and this far back (level) from what it looks at OVER or more below it.
const HEAD := 0.15
const SIGHT := 0.3
## How far the body rises on its toes to a high one.
const RISE := 0.12
## A paddle at work: the blade goes round its vessel's middle, the hands hold
## it this high over the brim (the hatch, for the copper) on the stand's side,
## going round a little with the blade.
const STIR_TOP := 0.3
const STIR_HAND := 0.05

var house: BrewHouse
## The player's arms (Player.arms): the brewery puts them on its work while it has the hands.
var arms: BrewArms
## How far the body leans now, world space.
var leaned := Vector3.ZERO
var _player: Player
var _eye: BrewEye
var _let_go := 0.0
## How far the eye is lowered at the work (the body crouched).
var _crouch := 0.0
## What the eye is kept on at the station's work; whether the work is below
## the chest (the body bows over it as it leans).
var _look := Vector3.ZERO
var _low := false
## The held thing's place in the hold frame, as it was taken.
var _held_rest := Transform3D.IDENTITY

## The player whose body works.
func attach(player: Player, eye: BrewEye) -> void:
	_player = player
	_eye = eye
	arms = player.arms

## Whether the brewery has the hands: a thing held, a station worked, or the
## fingers still letting go (BodyChannels.claim).
func at_work() -> bool:
	return house.carry.held != "" or house.work.station != null or _let_go > 0.0

## The eye's frame turned with the look about the vertical, kept upright.
func hold_frame() -> Transform3D:
	return _player.eye_frame()

func _hold_offset(id: String) -> Vector3:
	if id.begins_with("keg_"):
		return KEG_HOLD
	return HOLD.get(house.layout.entry_of(id).kind, HOLD.tool)

## Utensil `id` comes into the hand: where it hangs before the eye from now on.
func take_hold(id: String) -> void:
	var node := house.layout.node_of(id)
	_held_rest = hold_frame().affine_inverse() * node.global_transform
	if id.begins_with("keg_"):
		# Its axis (its node's x, from the foot to the grip) across the view.
		_held_rest.basis = Basis.IDENTITY
	_held_rest.origin = _hold_offset(id) - _held_rest.basis * house.layout.grip_local(id)

## The fingers open on a thing thrown: they stay open for LET_GO.
func let_go() -> void:
	arms.let_go()
	_let_go = LET_GO

## The body of this frame: the held thing in the hand, then the arms on it.
func update(delta: float) -> void:
	if _player == null:
		return
	_hold()
	_place_hands(delta)

## The held thing before the eye, or at the station's work: tipped over where
## it pours, the paddle round the vessel. The weight slows the walk.
func _hold() -> void:
	var layout := house.layout
	var held := house.carry.held
	var day := house.day
	_player.pace = BrewCarry.pace(BrewCarry.weight(layout.entry_of(held), house.load_kg(held))) if held != "" else 1.0
	if layout.utensils.has("hoist_bucket") and held != "hoist_bucket" and day.hooked:
		layout.node_of("hoist_bucket").position = layout.anchors["lift_floor"] + Vector3.UP * day.lift
	if held == "":
		return
	var node := layout.node_of(held)
	var frame := hold_frame()
	var station := house.work.station
	if station == null:
		node.global_transform = frame * _held_rest
		return
	var work := station.work()
	var over := layout.pour_over(str(work.id), station)
	if over.is_finite() and layout.sideways(held):
		# Held to the right of where it pours and tipped over to the
		# left: what it pours into stays in sight.
		var rest := _held_rest
		rest.origin = rest.basis * -layout.grip_local(held)
		var spot := house.to_global(over + Vector3.UP * SIDE_OVER) + frame.basis.x * layout.radius(held)
		node.global_transform = Transform3D(Basis(frame.basis.z, station.gesture.amount * TIP) * frame.basis, spot) * rest
		return
	if over.is_finite():
		var mouth := over + Vector3.UP * 0.3
		var toward := (house.to_local(_eye.camera.global_position) - mouth) * Vector3(1.0, 0.0, 1.0)
		var spot := house.to_global(mouth + toward.normalized() * maxf(0.25, toward.length() - HOLD_OUT))
		var tip := Basis(frame.basis.x, -station.gesture.amount * TIP)
		var rest := _held_rest
		rest.origin = rest.basis * -layout.grip_local(held)
		node.global_transform = Transform3D(tip * frame.basis, spot) * rest
		return
	if work.gesture == "circle":
		var stir := _stir(str(work.id))
		var round := Vector3(cos(station.gesture.amount), 0.0, sin(station.gesture.amount))
		var foot: Vector3 = stir.centre + round * Values.real(stir.reach) + Vector3.DOWN * 0.15
		var top: Vector3 = stir.top + round * STIR_HAND
		var entry := layout.entry_of(held)
		var shaft := Values.vec3(entry.grip) - Values.vec3(entry.at)
		var along := (top - foot).normalized()
		# A shaft longer than the way from the blade to the hands goes
		# deeper: the hands stay at the top.
		var grip := foot + along * shaft.length()
		if grip.y > top.y:
			foot -= along * (grip.y - top.y) / maxf(along.y, 0.1)
		node.global_transform = house.global_transform * Transform3D(Basis(Quaternion(shaft.normalized(), along)), foot)
		return
	node.global_transform = _swing(work, station.gesture, frame) * frame * _held_rest

## Where a paddle stirs at work `work_id`: {centre (the middle its blade
## goes round), reach (how far out), top (where the hands hold it, over the
## brim on the stand's side; through the hatch, for the copper), look (what
## the eye is on: the mash, the copper's hatch)}.
func _stir(work_id: String) -> Dictionary:
	var layout := house.layout
	var stand := layout.stand(house.work.station_id)
	if work_id == "stir_copper":
		var hatch: Vector3 = layout.anchors["copper_hatch"]
		var centre := Vector3(hatch.x, layout.surface_height(BrewDay.COPPER), hatch.z + 0.3)
		var out := (stand - hatch) * Vector3(1.0, 0.0, 1.0)
		return {"centre": centre, "reach": 0.12, "top": hatch + out.normalized() * 0.15 + Vector3.UP * STIR_TOP * 0.9,
			"look": hatch}
	var brim: Vector3 = layout.anchors["mash_tun_brim"]
	var toward := (stand - brim) * Vector3(1.0, 0.0, 1.0)
	return {"centre": layout.surface_point(BrewDay.MASH_TUN), "reach": 0.25,
		"top": brim + toward.normalized() * (layout.brim_radius("mash_tun_brim") - 0.05) + Vector3.UP * STIR_TOP,
		"look": layout.surface_point(BrewDay.MASH_TUN)}

## A held tool's swing at its work, a short clip the gesture drives: the
## mallet raised by the wind-up and brought down, a log or a handful drawn
## back and flung, the shovel pushed along its pass. World space.
func _swing(work: Dictionary, gesture: BrewGesture, frame: Transform3D) -> Transform3D:
	match str(work.gesture):
		"strike":
			var grip := frame * _hold_offset(house.carry.held)
			var lift := Basis(frame.basis.x, gesture.amount * STRIKE_LIFT)
			return Transform3D(lift, grip - lift * grip)
		"throw":
			return Transform3D(Basis.IDENTITY, (frame.basis.z * THROW_BACK + Vector3.DOWN * 0.1) * gesture.amount)
		"stripe":
			return Transform3D(Basis.IDENTITY, -frame.basis.z * gesture.pass_part() * STRIPE_REACH)
	return Transform3D.IDENTITY

# ---- The arms -----------------------------------------------------------------------

## The hands on what they hold or turn (BrewHands), the arms bent to them
## (BrewArms). The arms stand in for the mug's hand while they show.
func _place_hands(delta: float) -> void:
	var station := house.work.station
	# Over a low work the body bows as it leans.
	var bow := BOW * leaned.length() if _low else 0.0
	_player.rig.crouch = move_toward(_player.rig.crouch, minf(_crouch + bow, CROUCH), CROUCH_PACE * delta)
	# The body's own frame, without the lean: the lean is reckoned from it.
	var frame := Transform3D(hold_frame().basis, _player.global_position + Vector3.UP * _player.rig.position.y)
	# The arms are the brewery's only while it has the hands: the rod or the
	# potato may have them now.
	var mine := _player.hands.has(BodyChannels.BREWERY)
	if mine:
		arms.global_transform = frame
	_let_go = maxf(_let_go - delta, 0.0)
	var shoulders: Array[Vector3] = [arms.shoulder(BrewHands.RIGHT), arms.shoulder(BrewHands.LEFT)]
	var hands := hands_now(frame, shoulders)
	var toward := _clear_lean(_lean(_far_round(hands), shoulders)) if station != null else Vector3.ZERO
	leaned = leaned.move_toward(toward, LEAN_PACE * delta)
	var lean := _player.global_basis.inverse() * leaned
	_player.rig.position = Vector3(lean.x, _player.rig.position.y, lean.z)
	if station != null:
		_aim(_player.rig.global_position)
	if mine:
		arms.global_transform = frame.translated(leaned)
		if _let_go <= 0.0:
			arms.reach(_in_reach(hands, [shoulders[0] + leaned, shoulders[1] + leaned]))
		arms.pose(delta)
	# The hands come back to the mug once the arms have let go of the last thing.
	if not at_work():
		_player.hands.release(BodyChannels.BREWERY)

## How far the body leans (world space, level) to bring the shoulders within
## the arm's reach of the wrist farthest out of it (BrewArms.wrist_for); LEAN
## at most.
func _lean(hands: Array[Dictionary], shoulders: Array[Vector3]) -> Vector3:
	var lean := Vector3.ZERO
	var reach := arms.span - 0.02
	# Each hand in turn pulls the shoulders level towards its wrist, a few
	# rounds, so that one lean serves both hands.
	for _round in 4:
		for hand: Dictionary in hands:
			var to := arms.wrist_for(hand) - shoulders[Values.whole(hand.side)] - lean
			var flat := to * Vector3(1.0, 0.0, 1.0)
			if to.length() <= reach or flat.length() < 0.01:
				continue
			# The level shift that leaves the bar just within the reach.
			var level := sqrt(maxf(reach * reach - to.y * to.y, 0.0))
			lean = (lean + flat.normalized() * (flat.length() - level)).limit_length(LEAN)
	return lean

## The hands on a crank where it goes farthest from the body: the body
## leans once for the whole round. Other hands as they are.
func _far_round(hands: Array[Dictionary]) -> Array[Dictionary]:
	var work := house.work.station.work()
	var moving := house.layout.moving
	if not work.has("part") or not moving.has(work.part) or str(moving[work.part].kind) != "spin":
		return hands
	var pivot := house.to_global(Values.vec3(moving[work.part].pivot))
	var away := ((pivot - _player.global_position) * Vector3(1.0, 0.0, 1.0)).normalized()
	var far: Array[Dictionary] = []
	for hand: Dictionary in hands:
		var at: Transform3D = hand.at
		var round := (at.origin - pivot) * Vector3(1.0, 0.0, 1.0)
		var moved := hand.duplicate()
		moved.at = Transform3D(at.basis, pivot + away * round.length() + Vector3.UP * (at.origin.y - pivot.y))
		far.append(moved)
	return far

## As much of `lean` (world space) as the head has room for: it stops
## short of a wall or a vessel.
func _clear_lean(lean: Vector3) -> Vector3:
	# The eye stays back from what it looks at, the more the higher it is
	# over it: it does not look straight down.
	var eye := _player.rig.global_position - leaned
	var look := house.to_global(_look)
	var back := (look - eye) * Vector3(1.0, 0.0, 1.0)
	if back.length() > 0.001:
		var along := lean.dot(back.normalized())
		var most := maxf(back.length() - SIGHT * clampf((eye.y - look.y) / OVER, 0.0, 1.0), 0.0)
		if along > most:
			lean -= back.normalized() * (along - most)
	if lean.length() < 0.01:
		return lean
	var head := SphereShape3D.new()
	head.radius = HEAD
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = head
	query.transform = Transform3D(Basis.IDENTITY, eye)
	query.motion = lean
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	var free := _player.get_world_3d().direct_space_state.cast_motion(query)
	return lean * free[0]

## The hands whose wrists are within the arm's reach of their shoulders
## (BrewArms.wrist_for). A hand out of it is not shown on its bar; without the
## right one the arms do not show at all.
func _in_reach(hands: Array[Dictionary], shoulders: Array[Vector3]) -> Array[Dictionary]:
	var near: Array[Dictionary] = []
	for hand: Dictionary in hands:
		if arms.wrist_for(hand).distance_to(shoulders[Values.whole(hand.side)]) <= arms.span:
			near.append(hand)
	if not near.any(func(hand: Dictionary) -> bool: return Values.whole(hand.side) == BrewHands.RIGHT):
		near.clear()
	return near

## Where the hands go now: on the held thing (the left one under it while it
## is tipped), or on the part the station's work turns.
func hands_now(frame: Transform3D, shoulders: Array[Vector3]) -> Array[Dictionary]:
	var layout := house.layout
	var station := house.work.station
	var right := frame.basis.x
	var hands: Array[Dictionary] = []
	var held := house.carry.held
	if held != "":
		# A basket or a pot tipped sideways is held by the one hand.
		var tipping: bool = station != null and station.work().gesture == "tilt" and not layout.sideways(held)
		hands = BrewHands.on_utensil(held, layout.entry_of(held), layout.node_of(held).global_transform, shoulders,
			right, tipping, station != null)
	elif station != null and station.work().has("part") and house.machinery != null:
		var work := station.work()
		var pivot := house.machinery.pivot(str(work.part))
		if pivot != null and layout.moving.has(work.part):
			var part: Dictionary = layout.moving[work.part]
			var pull := str(part.group) + "_pull"
			if layout.anchors.has(pull):
				# Taken by its pull: the hand on the pull, whatever the part's pose.
				part = part.duplicate()
				part.grip = [layout.anchors[pull].x, layout.anchors[pull].y, layout.anchors[pull].z]
				hands = BrewHands.on_part(part, house.global_transform * Transform3D(Basis.IDENTITY, Values.vec3(part.pivot)),
					shoulders, right)
			else:
				hands = BrewHands.on_part(part, pivot.global_transform, shoulders, right,
					Values.flag(work.gesture == "rock" or work.gesture == "circle"))
	return hands

# ---- At a station -------------------------------------------------------------------

## The body at the station's work: on its stand, or stepped up to the point
## the hands work at (as near as there is room) and crouched to a low one;
## the eye on that point, else on what the station looks at.
func approach() -> void:
	var layout := house.layout
	var station_id := house.work.station_id
	var stand := layout.stand(station_id)
	var look := layout.look(station_id)
	var point := _work_reach()
	var work := house.work.station.work()
	_crouch = 0.0
	_low = false
	if point.is_finite():
		stand = _stand_by(point, stand)
		if layout.flat_crank(work):
			stand = _aside(stand)
		_crouch = clampf(stand.y + Player.EYE_HEIGHT - point.y - OVER, -RISE, CROUCH)
		# A flat crank is turned standing: the head keeps over what hangs above it.
		_low = point.y < stand.y + Player.EYE_HEIGHT - _crouch - OVER * 0.5 and not layout.flat_crank(work)
		look = _work_look(point)
	_player.global_position = house.to_global(stand) + Vector3.UP * 0.02
	_look = look
	_aim(_player.global_position + Vector3.UP * (Player.EYE_HEIGHT - _crouch))

## Steps away from station `station_id`: the body back on its stand, as
## approaching put it there, straight again.
func leave(station_id: String) -> void:
	_player.global_position = house.to_global(house.layout.stand(station_id)) + Vector3.UP * 0.02
	leaned = Vector3.ZERO
	_player.rig.position = Vector3(0.0, _player.rig.position.y, 0.0)
	_crouch = 0.0

## The eye at `eye` (world) turned to what it is kept on at the work.
func _aim(eye: Vector3) -> void:
	var aim := house.to_global(_look) - eye
	_player.rig.yaw_deg = rad_to_deg(atan2(-aim.x, -aim.z))
	_player.rig.pitch_deg = rad_to_deg(asin(clampf(aim.normalized().y, -1.0, 1.0)))
	_player.rig.apply_look(Vector2.ZERO)

## What the eye is on at a work whose hands are at `point`: where a tipped
## thing pours, the inside of the vessel a paddle stirs, the middle a flat
## crank goes round, else the point.
func _work_look(point: Vector3) -> Vector3:
	var layout := house.layout
	var station := house.work.station
	var work := station.work()
	if layout.flat_crank(work):
		var pivot := Values.vec3(layout.moving[work.part].pivot)
		return Vector3(pivot.x, point.y, pivot.z)
	var over := layout.pour_over(str(work.id), station)
	if over.is_finite():
		return over
	if work.gesture == "circle" and house.carry.held != "":
		return _stir(str(work.id)).look
	return point

## The point the right hand works at the station's work: the part it turns
## (by its pull, where it has one), over where a tipped thing pours, a
## paddle's top; INF for a work done before the eye.
func _work_reach() -> Vector3:
	var layout := house.layout
	var station := house.work.station
	var work := station.work()
	if work.has("part") and layout.moving.has(work.part):
		var pull := str(layout.groups.get(work.part, "")) + "_pull"
		return layout.anchors[pull] if layout.anchors.has(pull) else Values.vec3(layout.moving[work.part].grip)
	var over := layout.pour_over(str(work.id), station)
	if over.is_finite():
		var stand := layout.stand(house.work.station_id)
		var toward := (stand - over) * Vector3(1.0, 0.0, 1.0)
		return over + Vector3.UP * 0.3 + toward.normalized() * 0.25
	if work.gesture == "circle" and house.carry.held != "":
		return _stir(str(work.id)).top
	return Vector3.INF

## The nearest spot to `point` where the body has room, a floor under it
## and a clear sight of the point: at each distance, first on the way back
## to `stand`, then on the bearings round the point farther and farther
## from that way. `stand` when no spot short of it serves.
func _stand_by(point: Vector3, stand: Vector3) -> Vector3:
	var away := (stand - point) * Vector3(1.0, 0.0, 1.0)
	var step := ARM_STAND
	while step < away.length():
		for turn in BEARINGS:
			var angle := TAU / BEARINGS * ceili(turn / 2.0) * (1.0 if turn % 2 == 1 else -1.0)
			var spot := Vector3(point.x, stand.y, point.z) + away.normalized().rotated(Vector3.UP, angle) * step
			spot.y = _ground(spot)
			if not is_nan(spot.y) and _room(spot) and _sees(spot, point):
				return spot
		step += ROOM_STEP
	return stand

## The body at a flat crank stands to the left of the middle it goes
## round, its right shoulder before it: the head bows past what hangs over
## the crank. `stand` when there is no room there.
func _aside(stand: Vector3) -> Vector3:
	var pivot := Values.vec3(house.layout.moving[house.work.station.work().part].pivot)
	var toward := ((pivot - stand) * Vector3(1.0, 0.0, 1.0)).normalized()
	var spot := stand + toward.cross(Vector3.UP) * -FLAT_CRANK_ASIDE
	spot.y = _ground(spot)
	return spot if not is_nan(spot.y) and _room(spot) else stand

## The floor under `spot` the body can step onto: a step or a stand up to
## STEP_UP over it, else `spot`'s own height; NAN with nothing under it.
func _ground(spot: Vector3) -> float:
	var hit := _eye.ray(house.to_global(spot + Vector3.UP * STEP_UP), house.to_global(spot + Vector3.DOWN * 0.05),
		_player.collision_mask)
	if hit.is_empty():
		return NAN
	var met: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	return house.to_local(met).y if normal.y > 0.7 else spot.y

## Whether the eye of the body standing at `spot` sees `point`, with no wall
## or vessel between. The ray goes from the point: a part inside its
## vessel's collider does not hide itself.
func _sees(spot: Vector3, point: Vector3) -> bool:
	return _eye.ray(house.to_global(point), house.to_global(spot + Vector3.UP * Player.EYE_HEIGHT),
		_player.collision_mask).is_empty()

## Whether the body has room standing at `spot`.
func _room(spot: Vector3) -> bool:
	var body := _player.collision
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.shape
	query.transform = Transform3D(Basis.IDENTITY, house.to_global(spot) + body.position + Vector3.UP * 0.05)
	query.collision_mask = _player.collision_mask
	query.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
